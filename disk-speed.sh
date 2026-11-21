#!/bin/zsh
# disk-speed.sh: measure a Mac's disk speed with fio, like Blackmagic Disk Speed Test
# but from the command line (also works in a VM, where the App Store doesn't).
#
#   zsh ~/mac-setup/disk-speed.sh                 # test the disk your home folder is on
#   zsh ~/mac-setup/disk-speed.sh /Volumes/Ext    # test another disk
#   zsh ~/mac-setup/disk-speed.sh --quick         # skip the large uncached read test
#
# Tests (same settings on every Mac, so results can be compared):
#   sequential write and read: 1 MB blocks, 10 GB file, 8 requests in flight
#   random 4K read+write mix:  1 GB file, 32 requests in flight, 30 seconds
#   uncached sequential read:  a file bigger than RAM, so macOS can't serve it from memory
#
# Writes use fresh random data (--refill_buffers). Blackmagic writes data that's
# easier on the SSD, so its write number can be higher than this one.
# Needs fio (installed with Homebrew if missing). Test files are always deleted.

set -euo pipefail

QUICK=0
TARGET="$HOME"
for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    -h|--help) sed -n '2,16p' "${0:A}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) TARGET="$arg" ;;
  esac
done

main() {
  if ! command -v fio >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      print -P "%F{blue}==>%f Installing fio"
      brew install fio
    else
      print -P "%F{red}fio isn't installed and Homebrew isn't available.%f Install fio first." >&2
      exit 1
    fi
  fi
  [[ -d "$TARGET" && -w "$TARGET" ]] || { print -P "%F{red}Can't write to $TARGET%f" >&2; exit 1; }

  DIR=$(mktemp -d "$TARGET/.disk-speed.XXXXXX")
  trap 'rm -rf "$DIR"' EXIT INT TERM

  local ram_gb free_gb big_gb
  ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  free_gb=$(( $(df -k "$DIR" | awk 'NR==2 {print $4}') / 1048576 ))
  big_gb=$(( ram_gb + 8 ))

  print -P "\n%B$(scutil --get ComputerName 2>/dev/null || hostname -s)%b"
  print "  $(sysctl -n machdep.cpu.brand_string), ${ram_gb} GB RAM, macOS $(sw_vers -productVersion)"
  print "  Testing: $(df -h "$DIR" | awk 'NR==2 {print $1 " (" $4 " free)"}') at $TARGET"
  sysctl -n kern.hv_vmm_present 2>/dev/null | grep -qx 1 && print "  Running in a virtual machine"

  (( free_gb >= 12 )) || { print -P "%F{red}Need at least 12 GB free, have ${free_gb} GB.%f" >&2; exit 1; }

  print -P "\n%F{blue}==>%f Running (about 1 to 2 minutes)"
  local common=(--direct=1 --ioengine=posixaio --output-format=json)
  local f="$DIR/fiotest"

  run fio --name=w --rw=write --bs=1m --size=10g --iodepth=8 --refill_buffers --end_fsync=1 "${common[@]}" --filename="$f"
  local seq_w=$(mbs write)
  run fio --name=r --rw=read --bs=1m --size=10g --iodepth=8 "${common[@]}" --filename="$f"
  local seq_r=$(mbs read)
  rm -f "$f"

  run fio --name=rand --rw=randrw --bs=4k --size=1g --iodepth=32 --runtime=30 --time_based "${common[@]}" --filename="$f"
  local rnd_r=$(iops read) rnd_w=$(iops write)
  rm -f "$f"

  local big_r="skipped"
  if (( QUICK )); then
    :
  elif (( free_gb < big_gb + 4 )); then
    big_r="skipped (needs $(( big_gb + 4 )) GB free)"
  else
    run fio --name=bw --rw=write --bs=1m --size=${big_gb}g --iodepth=8 --refill_buffers --end_fsync=1 "${common[@]}" --filename="$f"
    run fio --name=br --rw=read --bs=1m --size=${big_gb}g --iodepth=8 "${common[@]}" --filename="$f"
    big_r="$(mbs read) MB/s"
    rm -f "$f"
  fi

  print
  printf "  %-34s %s\n" \
    "Sequential write (1 MB blocks)" "$seq_w MB/s" \
    "Sequential read  (1 MB blocks)" "$seq_r MB/s" \
    "Sequential read, uncached (${big_gb} GB)" "$big_r" \
    "Random 4K read" "$rnd_r IOPS" \
    "Random 4K write" "$rnd_w IOPS"
  print "\n  The 10 GB read can be served partly from memory; the uncached read is the real disk speed."
}

# Run fio, keeping its JSON report in $DIR/out.json.
run() { "$@" > "$DIR/out.json"; }
# Read a result from the last report (plutil reads JSON; no extra tools needed).
mbs()  { plutil -extract "jobs.0.$1.bw_bytes" raw "$DIR/out.json" | awk '{printf "%\047.0f", $1/1000000}'; }
iops() { plutil -extract "jobs.0.$1.iops" raw "$DIR/out.json" | awk '{printf "%\047.0f", $1}'; }

main
