#!/bin/zsh
# disk-speed.sh: measure a Mac's disk speed with fio, like Blackmagic Disk Speed Test
# but from the command line (also works in a VM, where the App Store doesn't).
#
#   zsh ~/mac-setup/speed-tests/disk-speed.sh                 # test the disk your home folder is on
#   zsh ~/mac-setup/speed-tests/disk-speed.sh /Volumes/Ext    # test another disk
#   zsh ~/mac-setup/speed-tests/disk-speed.sh --quick         # skip the large uncached read test
#   zsh ~/mac-setup/speed-tests/disk-speed.sh --save          # also add the run to results.csv
#       --name "Tart VM on MacBook Pro"   what to call this machine (default: its model name)
#       --note "a VM was running"         a note to keep with the run
#
# Every run ends with a CSV row for results.csv. --save appends it and rebuilds
# the summary in README.md (with summary.sh).
#
# Tests (same settings on every Mac, so results can be compared):
#   sequential write and read: 1 MB blocks, 10 GB file, 8 requests in flight
#   random 4K read+write mix:  1 GB file, 32 requests in flight, 30 seconds
#   uncached sequential read:  a file bigger than RAM, so macOS can't serve it from memory
#
# Writes use fresh random data (--refill_buffers). Blackmagic writes data that's
# easier on the SSD, so its write number can be higher than this one.
# Needs fio (installed with Homebrew if missing). Test files are always deleted.
# (Help text ends on the line above.)

set -uo pipefail   # -e is set inside main, which runs in a subshell (see the end)

HERE=${0:A:h}
CSV=$HERE/results.csv
QUICK=0 SAVE=0 NAME="" NOTE=""
TARGET="$HOME"
while (( $# )); do
  case "$1" in
    --quick) QUICK=1 ;;
    --save)  SAVE=1 ;;
    --name)  NAME=${2:?--name needs a value}; shift ;;
    --note)  NOTE=${2:?--note needs a value}; shift ;;
    -h|--help) sed -n '2,/Help text ends/p' "${0:A}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGET="$1" ;;
  esac
  shift
done

if (( SAVE )) && [[ ! -w "$CSV" ]]; then
  print -P "%F{red}--save needs $CSV%f (run the script from a clone of the repo)" >&2
  exit 1
fi

main() {
  set -e
  if ! command -v fio >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      print -P "%F{blue}==>%f Installing fio"
      brew install fio
    else
      print -P "%F{red}fio isn't installed and Homebrew isn't available.%f Install fio first." >&2
      exit 1
    fi
  fi

  local ram_gb free_gb big_gb model chip macos vm=False filevault=False
  ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  free_gb=$(( $(df -k "$DIR" | awk 'NR==2 {print $4}') / 1048576 ))
  big_gb=$(( ram_gb + 8 ))
  model=$(sysctl -n hw.model)
  chip=$(sysctl -n machdep.cpu.brand_string)
  macos=$(sw_vers -productVersion)
  [[ $(sysctl -n kern.hv_vmm_present 2>/dev/null) == 1 ]] && vm=True
  [[ $(fdesetup status 2>/dev/null) == "FileVault is Off."* ]] || filevault=True
  # The model name ("MacBook Pro"), not the computer name, which often has a person's name in it.
  [[ -n "$NAME" ]] || NAME=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}')
  [[ -n "$NAME" ]] || NAME=$model

  print -P "\n%B$NAME%b ($model)"
  print "  $chip, ${ram_gb} GB RAM, macOS $macos, VM: $vm, FileVault: $filevault"
  print "  Testing: $(df -h "$DIR" | awk 'NR==2 {print $1 " (" $4 " free)"}') at $TARGET"

  (( free_gb >= 12 )) || { print -P "%F{red}Need at least 12 GB free, have ${free_gb} GB.%f" >&2; exit 1; }

  print -P "\n%F{blue}==>%f Running (about 1 to 2 minutes)"
  local common=(--thread --direct=1 --ioengine=posixaio --output-format=json)
  local f="$DIR/fiotest"

  run fio --name=w --rw=write --bs=1m --size=10g --iodepth=8 --refill_buffers --end_fsync=1 "${common[@]}" --filename="$f"
  local seq_w=$(mbs write)
  run fio --name=r --rw=read --bs=1m --size=10g --iodepth=8 "${common[@]}" --filename="$f"
  local seq_r=$(mbs read)
  rm -f "$f"

  run fio --name=rand --rw=randrw --bs=4k --size=1g --iodepth=32 --runtime=30 --time_based "${common[@]}" --filename="$f"
  local rnd_r=$(iops read) rnd_w=$(iops write)
  rm -f "$f"

  local big_r="" big_msg="skipped" quick=True
  if (( QUICK )); then
    :
  elif (( free_gb < big_gb + 4 )); then
    big_msg="skipped (needs $(( big_gb + 4 )) GB free)"
  else
    run fio --name=bw --rw=write --bs=1m --size=${big_gb}g --iodepth=8 --refill_buffers --end_fsync=1 "${common[@]}" --filename="$f"
    run fio --name=br --rw=read --bs=1m --size=${big_gb}g --iodepth=8 "${common[@]}" --filename="$f"
    big_r=$(mbs read) big_msg="$(fmt $big_r) MB/s" quick=False
    rm -f "$f"
  fi

  print
  printf "  %-34s %s\n" \
    "Sequential write (1 MB blocks)" "$(fmt $seq_w) MB/s" \
    "Sequential read  (1 MB blocks)" "$(fmt $seq_r) MB/s" \
    "Sequential read, uncached (${big_gb} GB)" "$big_msg" \
    "Random 4K read" "$(fmt $rnd_r) IOPS" \
    "Random 4K write" "$(fmt $rnd_w) IOPS"
  print "\n  The 10 GB read can be served partly from memory; the uncached read is the real disk speed."

  # Same columns as results.csv.
  local row
  row="$(date +%F),$(q "$NAME"),$(q "$model"),$(q "$chip"),$ram_gb,$macos,$vm,$filevault,$quick,$seq_w,$seq_r,$big_r,$rnd_r,$rnd_w,$(q "$NOTE")"
  print "\n  CSV row for results.csv:\n$row"
  if (( SAVE )); then
    print -r -- "$row" >> "$CSV"
    print -P "\n%F{blue}==>%f Added to $CSV"
    zsh "$HERE/summary.sh"
  fi
}

# Run fio, keeping its JSON report in $DIR/out.json.
run() { "$@" > "$DIR/out.json"; }
# Read a result from the last report (plutil reads JSON; no extra tools needed).
mbs()  { plutil -extract "jobs.0.$1.bw_bytes" raw "$DIR/out.json" | awk '{printf "%.0f", $1/1000000}'; }
iops() { plutil -extract "jobs.0.$1.iops" raw "$DIR/out.json" | awk '{printf "%.0f", $1}'; }
fmt()  { awk -v n="$1" 'BEGIN {printf "%\047d", n}'; }    # 12345 -> 12,345
q()    { print -rn -- "\"${1//\"/\"\"}\""; }             # quote a CSV text field

[[ -d "$TARGET" && -w "$TARGET" ]] || { print -P "%F{red}Can't write to $TARGET%f" >&2; exit 1; }

# The test files go in $DIR, which is deleted however the script ends: finished,
# failed, Ctrl+C, or Terminal window closed. main runs in a background subshell so
# this script always gets control back to clean up (zsh's EXIT trap doesn't fire
# reliably when a function exits on an error or signal).
# fio ignores HUP (closed window) and is stopped with INT instead: killed by HUP it
# leaks a shared-memory segment, and after a few of those fio can't start at all.
DIR=$(mktemp -d "$TARGET/.disk-speed.XXXXXX")
sub=""
stop() {
  if [[ -n "$sub" ]]; then
    pkill -INT -P "$sub" fio 2>/dev/null
    wait "$sub" 2>/dev/null
  fi
  rm -rf "$DIR"
  exit 130
}
trap stop INT TERM HUP
( trap '' HUP; main ) &
sub=$!
wait "$sub"; rc=$?
rm -rf "$DIR"
exit $rc
