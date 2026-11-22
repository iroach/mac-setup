#!/bin/zsh
# build-speed.sh: measure how fast a Mac builds native code, by building pinned
# open-source projects the same way on every Mac and timing them.
#
#   zsh ~/mac-setup/speed-tests/build-speed.sh                     # build every project that can run here
#   zsh ~/mac-setup/speed-tests/build-speed.sh --project openssl   # one project (repeat or use commas for more)
#   zsh ~/mac-setup/speed-tests/build-speed.sh --runs 1            # one build per project instead of 3
#   zsh ~/mac-setup/speed-tests/build-speed.sh --save              # also add the results to build-results.csv
#   zsh ~/mac-setup/speed-tests/build-speed.sh --start-only        # only the program-start test (about 15 seconds)
#   zsh ~/mac-setup/speed-tests/build-speed.sh --submit            # submit the results in a GitHub issue, for review
#       --name "MacBook Pro M5 Pro"       what to call this machine (default: its model name;
#                                         in a VM, its chip, such as "Apple M5 Pro (Virtual)")
#       --note "a VM was running"         a note to keep with the run
#
# Projects (pinned versions; sources are checked against a SHA-256 before use):
#   openssl      OpenSSL 3.5.9: C and generated assembly             (Command Line Tools)
#   ffmpeg       FFmpeg 8.1.3: large C codebase, macOS media frameworks (Command Line Tools)
#   sdl          SDL 3.4.20: C plus Objective-C Cocoa (AppKit) code   (Command Line Tools, cmake)
#   netnewswire  NetNewsWire mac-7.3.1: Swift app, macOS and iOS     (Xcode)
#   ghostty      Ghostty 1.4.0: Zig core plus Swift macOS app        (Xcode, Zig 0.17.0)
# Projects that need Xcode are skipped, with the reason, when it isn't there.
#
# Each build starts from a fresh copy of the source and uses every CPU core. The
# configure step is timed separately; the score is the median build time of the runs.
# Downloads are cached in ~/Library/Caches/mac-setup/build-speed, so timing never
# includes the network. Build folders are always deleted; logs stay in the cache.
# Every run first does a program-start test, which shows what security software
# (antivirus, EDR) adds to each program start and file, apart from compile speed:
#   start: running /usr/bin/true 1,000 times      (ms per program start)
#   clang: compiling an empty C file 200 times     (ms per compile)
#   file:  writing 5,000 small files               (µs per file)
# Each is done 3 times; the median goes into every CSV row of the run.
#
# Every run ends with CSV rows for build-results.csv. --save appends them and
# rebuilds the build summary in README.md (with build-summary.sh). --submit opens a
# "Build speed results" issue form with the rows filled in instead: no git needed,
# and a maintainer reviews them before they're added.
# (Help text ends on the line above.)

set -uo pipefail   # -e is set inside main, which runs in a subshell (see the end)
zmodload zsh/datetime

HERE=${0:A:h}
CSV=$HERE/build-results.csv
CACHE=$HOME/Library/Caches/mac-setup/build-speed
ALL=(openssl ffmpeg sdl netnewswire ghostty)
RUNS=3 SAVE=0 NAME="" NOTE="" START_ONLY=0 SUBMIT=0
ISSUE_URL=https://github.com/iroach/mac-setup/issues/new
PROJECTS=()
while (( $# )); do
  case "$1" in
    --project) PROJECTS+=(${(s:,:)${2:?--project needs a value}}); shift ;;
    --runs)    RUNS=${2:?--runs needs a value}; shift ;;
    --save)    SAVE=1 ;;
    --start-only) START_ONLY=1 ;;
    --submit)  SUBMIT=1 ;;
    --name)    NAME=${2:?--name needs a value}; shift ;;
    --note)    NOTE=${2:?--note needs a value}; shift ;;
    -h|--help) sed -n '2,/Help text ends/p' "${0:A}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -P "%F{red}Unknown option: $1%f (see --help)" >&2; exit 1 ;;
  esac
  shift
done
(( ${#PROJECTS} )) && [[ $PROJECTS != all ]] || PROJECTS=($ALL)
(( START_ONLY )) && PROJECTS=()
for p in $PROJECTS; do
  (( ${ALL[(Ie)$p]} )) || { print -P "%F{red}Unknown project: $p%f (one of: $ALL)" >&2; exit 1; }
done
[[ $RUNS == <1-> ]] || { print -P "%F{red}--runs needs a number of 1 or more%f" >&2; exit 1; }

if (( SAVE )) && [[ ! -w "$CSV" ]]; then
  print -P "%F{red}--save needs $CSV%f (run the script from a clone of the repo)" >&2
  exit 1
fi

# --- Pinned sources ---------------------------------------------------------
OPENSSL_VER=3.5.9
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz
OPENSSL_SHA=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
FFMPEG_VER=8.1.3
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.xz
FFMPEG_SHA=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3
SDL_VER=3.4.20
SDL_URL=https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VER/SDL3-$SDL_VER.tar.gz
SDL_SHA=f3bb06f55bed9557227a700af2ea62e49497ebdf58037732a731a5fb3ef8581f
NNW_VER=mac-7.3.1
NNW_GIT=https://github.com/Ranchero-Software/NetNewsWire.git
NNW_COMMIT=3015ffced9efc0f01f5aa9ec7769bcc2d49224e1
GHOSTTY_VER=1.4.0
GHOSTTY_URL=https://release.files.ghostty.org/$GHOSTTY_VER/ghostty-$GHOSTTY_VER.tar.gz
GHOSTTY_SHA=cb188ac6c3a8278d5fd7bfef15d8c017104c87f638b5560eb38024a71ae0f005
ZIG_VER=0.17.0
ZIG_SHA_aarch64=b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a
ZIG_SHA_x86_64=4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6

main() {
  set -e
  mkdir -p "$CACHE/logs"
  local jobs model chip arch ram_gb macos vm=False pcores ecores clang_v xcode_v="" power=AC low_power=False
  jobs=$(sysctl -n hw.ncpu)
  model=$(sysctl -n hw.model)
  chip=$(sysctl -n machdep.cpu.brand_string)
  arch=$(uname -m)
  ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  macos=$(sw_vers -productVersion)
  # (Pipelines here read all their input, never head or awk's exit: with pipefail, a
  # writer killed by SIGPIPE would fail the pipeline, and set -e would end the run.)
  # Apple silicon: performance and efficiency cores. Intel reports all its physical
  # cores as one level, so p_cores is the physical cores and e_cores is blank.
  pcores=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu)
  ecores=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || true)
  local cores_text="$jobs cores ($pcores performance, $ecores efficiency)"
  [[ -n "$ecores" ]] || cores_text="$jobs threads ($pcores cores)"
  [[ $(sysctl -n kern.hv_vmm_present 2>/dev/null) == 1 ]] && vm=True
  [[ $vm == False ]] || cores_text="$jobs virtual CPUs"
  # Without the Command Line Tools (or Xcode), clang is only a stub that opens an
  # install prompt; say so instead of failing on the first compile.
  if ! xcode-select -p >/dev/null 2>&1; then
    print -P "%F{red}The Command Line Tools aren't installed.%f Install them with: xcode-select --install" >&2
    print "Then run this again." >&2
    exit 1
  fi
  clang_v=$(clang --version 2>/dev/null | sed -n '1s/ (.*//p')
  find_xcode
  [[ -n "$XCODE_DIR" ]] && xcode_v=$(DEVELOPER_DIR=$XCODE_DIR xcodebuild -version 2>/dev/null | sed -n '1s/^Xcode //p')
  [[ $(pmset -g batt 2>/dev/null | sed -n 1p) == *"Battery Power"* ]] && power=battery
  [[ $(pmset -g 2>/dev/null | awk '/lowpowermode/ {print $2}') == 1 ]] && low_power=True
  # A VM's model name ("Apple Virtual Machine 1") doesn't say what it runs on; its chip does.
  [[ -n "$NAME" || $vm == False ]] || NAME=$chip
  [[ -n "$NAME" ]] || NAME=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ && !n++ {print $2}')
  [[ -n "$NAME" ]] || NAME=$model

  print -P "\n%B$NAME%b ($model)"
  print "  $chip ($arch), $cores_text, ${ram_gb} GB RAM, macOS $macos, VM: $vm"
  print "  $clang_v; Xcode: ${xcode_v:-not installed}; power: $power${${low_power:#False}:+, Low Power Mode on}"
  [[ $power == AC ]] || print -P "  %F{yellow}On battery: the Mac may run slower. Plug it in for comparable results.%f"
  [[ $low_power == False ]] || print -P "  %F{yellow}Low Power Mode is on: results will be slower. Turn it off for comparable results.%f"

  print -P "\n%F{blue}==>%f %BProgram-start test%b"
  start_test
  local start_ms=$START_MS clang_ms=$CLANG_MS file_us=$FILE_US
  local start_line="$(printf '  %-12s %s ms per program start, %s ms per empty clang compile, %s µs per small file' \
    start $start_ms $clang_ms $file_us)"
  print "$start_line"
  # Everything about the machine and this run, for every CSV row.
  local machine="$(date +%F),$(q "$NAME"),$(q "$model"),$(q "$chip"),$arch,$jobs,$pcores,$ecores,$ram_gb,$macos,$vm,$(q "$clang_v"),$(q "$xcode_v"),$power,$low_power"
  local tail="$start_ms,$clang_ms,$file_us,$(q "$NOTE")"

  local p reason rows=() lines=("$start_line") i cfg bld work med mn mx spread failed
  # From here a failing project doesn't end the run: it's reported, and the other
  # projects' results are still printed and saved. (set -e is off in main, and each
  # step runs in a subshell with set -e on, outside any if or ||, where zsh would
  # ignore it.)
  set +e
  # --start-only: one row with no project.
  (( START_ONLY )) && rows+=("$machine,,,,,,,,,$tail")
  for p in $PROJECTS; do
    print -P "\n%F{blue}==>%f %B$p%b"
    if reason=$(can_run_$p); then :; else
      print -P "  %F{yellow}Skipped:%f $reason"
      lines+=("$(printf '  %-12s %s' $p "skipped: $reason")")
      continue
    fi
    LOG=$CACHE/logs/$p.log
    : > "$LOG"
    ( set -e; fetch_$p )
    if (( $? )); then
      print -P "  %F{red}Failed:%f couldn't download or set up $p (log: $LOG)"
      lines+=("$(printf '  %-12s %s' $p "failed: couldn't download or set up (log: $LOG)")")
      continue
    fi
    cfg=() bld=() failed=""
    for i in {1..$RUNS}; do
      work=$DIR/$p
      rm -rf "$work"; mkdir -p "$work"
      print -n "  run $i of $RUNS: configure "
      step "$work" configure_$p; if (( $? )); then failed=configure; break; fi
      cfg+=($REPLY); print -n "${REPLY}s, build "
      step "$work" build_$p;     if (( $? )); then failed=build; break; fi
      bld+=($REPLY); print "${REPLY}s"
      rm -rf "$work"
    done
    rm -rf "$work"
    if [[ -n $failed ]]; then
      lines+=("$(printf '  %-12s %s' $p "failed: the $failed step (log: $LOG)")")
      continue
    fi
    med=$(median $bld) mn=${${(on)bld}[1]} mx=${${(on)bld}[-1]}
    spread=$(awk -v a=$mn -v b=$mx -v m=$med 'BEGIN {printf "%.1f", (b - a) / m * 100}')
    lines+=("$(printf '  %-12s %-10s build %7ss (runs %ss to %ss, spread %s%%), configure %ss' \
      $p $(ver_$p) $med $mn $mx $spread $(median $cfg))")
    rows+=("$machine,$p,$(q "$(ver_$p)"),$jobs,$RUNS,$(median $cfg),$med,$mn,$mx,$tail")
  done
  set -e

  print -P "\n%BResults%b (lower is better)"
  print -l -- $lines
  (( ${#rows} )) || return 0
  print "\n  CSV rows for build-results.csv:"
  print -l -- $rows
  if (( SAVE )); then
    print -rl -- $rows >> "$CSV"
    print -P "\n%F{blue}==>%f Added to $CSV"
    zsh "$HERE/build-summary.sh"
  fi
  (( SUBMIT )) && submit $rows
  return 0
}

# Open the "Build speed results" issue form with these rows filled in. Over SSH
# (in a VM, say), print the link instead, for a Mac that's signed in to GitHub.
submit() {
  local url="$ISSUE_URL?template=build-results.yml&title=$(urlencode "Build results: $NAME")&rows=$(urlencode "${(F)@}")"
  print -P "\n%F{blue}==>%f Submit these results: fill in the form and select Create"
  print -r -- "SUBMIT-URL: $url"
  [[ -z "${SSH_CONNECTION:-}" ]] && open "$url" 2>/dev/null || true
}

# Percent-encode a string for a URL, byte by byte.
urlencode() {
  local LC_ALL=C s=$1 out="" c i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=${s[i]}
    case $c in
      [A-Za-z0-9.~_-]) out+=$c ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  print -rn -- $out
}

# --- Projects ----------------------------------------------------------------
# Each project has: can_run_X (prints why not and fails if it can't run here),
# fetch_X (fills the cache, untimed), configure_X and build_X (run in $PWD = a
# fresh work folder, output to the log), and ver_X.

can_run_openssl() { command -v perl >/dev/null || { print "needs perl"; return 1; }; }
fetch_openssl()   { fetch "$OPENSSL_URL" "$OPENSSL_SHA"; }
ver_openssl()     { print $OPENSSL_VER; }
configure_openssl() {
  tar -xzf "$CACHE/${OPENSSL_URL:t}" --strip-components 1
  ./Configure no-docs --prefix="$PWD/install"
}
build_openssl()   { make -j$jobs build_sw; }

can_run_ffmpeg()  { :; }
fetch_ffmpeg()    { fetch "$FFMPEG_URL" "$FFMPEG_SHA"; }
ver_ffmpeg()      { print $FFMPEG_VER; }
configure_ffmpeg() {
  tar -xJf "$CACHE/${FFMPEG_URL:t}" --strip-components 1
  # Only what ships with macOS, so Homebrew libraries on one Mac don't change the build.
  # On Intel, skip the x86 assembly, which would need nasm.
  local intel=()
  [[ $arch == x86_64 ]] && intel=(--disable-x86asm)
  ./configure --disable-doc --disable-autodetect \
    --enable-videotoolbox --enable-audiotoolbox --enable-avfoundation --enable-coreimage --enable-appkit $intel
}
build_ffmpeg()    { make -j$jobs; }

can_run_sdl()     { :; }
fetch_sdl()       { need_brew cmake; fetch "$SDL_URL" "$SDL_SHA"; }
ver_sdl()         { print $SDL_VER; }
configure_sdl() {
  tar -xzf "$CACHE/${SDL_URL:t}" --strip-components 1
  cmake -S . -B build -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
}
build_sdl()       { cmake --build build -j $jobs; }

can_run_netnewswire() {
  [[ -n "$XCODE_DIR" ]] || { print "needs Xcode"; return 1; }
  DEVELOPER_DIR=$XCODE_DIR xcodebuild -license check >/dev/null 2>&1 || { print "accept the Xcode license first: sudo xcodebuild -license accept"; return 1; }
}
fetch_netnewswire() {
  local src=$CACHE/netnewswire-$NNW_VER
  if [[ $(git -C "$src" rev-parse HEAD 2>/dev/null) != $NNW_COMMIT ]]; then
    rm -rf "$src"
    print "  Downloading NetNewsWire $NNW_VER"
    git clone -q --depth 1 --branch $NNW_VER -c advice.detachedHead=false $NNW_GIT "$src"
    [[ $(git -C "$src" rev-parse HEAD) == $NNW_COMMIT ]] || { print -P "  %F{red}Tag $NNW_VER isn't commit $NNW_COMMIT%f" >&2; rm -rf "$src"; return 1; }
  fi
  # Swift packages, fetched once and reused (sources only, nothing compiled).
  [[ -d $CACHE/netnewswire-packages/checkouts ]] || {
    print "  Downloading NetNewsWire's Swift packages"
    DEVELOPER_DIR=$XCODE_DIR xcodebuild -resolvePackageDependencies -project "$src/NetNewsWire.xcodeproj" \
      -scheme NetNewsWire -clonedSourcePackagesDirPath $CACHE/netnewswire-packages >> "$LOG" 2>&1
  }
}
ver_netnewswire() { print $NNW_VER; }
configure_netnewswire() { cp -R "$CACHE/netnewswire-$NNW_VER/" .; }
# The Mac app and the iOS app (for the simulator, which needs no signing), one after the other.
# Debug, the everyday developer build; Release re-signs the share extension, which needs a signing identity.
build_netnewswire() {
  local s args=(build -project NetNewsWire.xcodeproj -derivedDataPath "$PWD/dd"
    -clonedSourcePackagesDirPath $CACHE/netnewswire-packages -disableAutomaticPackageResolution
    -configuration Debug -jobs $jobs CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=)
  for s in "NetNewsWire generic/platform=macOS" "NetNewsWire-iOS generic/platform=iOS Simulator"; do
    DEVELOPER_DIR=$XCODE_DIR xcodebuild $args -scheme ${s%% *} -destination "${s#* }"
  done
}

can_run_ghostty() {
  [[ -n "$XCODE_DIR" ]] || { print "needs Xcode"; return 1; }
  DEVELOPER_DIR=$XCODE_DIR xcodebuild -license check >/dev/null 2>&1 || { print "accept the Xcode license first: sudo xcodebuild -license accept"; return 1; }
  # Ghostty compiles Metal shaders; since Xcode 26 the Metal Toolchain is a separate download.
  DEVELOPER_DIR=$XCODE_DIR xcrun -sdk macosx metal --version >/dev/null 2>&1 || {
    print "needs Xcode's Metal Toolchain (about 850 MB); run: xcodebuild -downloadComponent MetalToolchain"; return 1; }
  [[ $arch == (arm64|x86_64) ]] || { print "no Zig for $arch"; return 1; }
}
fetch_ghostty() {
  need_brew gettext msgfmt
  fetch "$GHOSTTY_URL" "$GHOSTTY_SHA"
  local zarch=${arch/arm64/aarch64}
  local zsha=ZIG_SHA_$zarch
  fetch https://ziglang.org/download/$ZIG_VER/zig-$zarch-macos-$ZIG_VER.tar.xz ${(P)zsha}
  ZIG=$CACHE/zig-$zarch-macos-$ZIG_VER/zig
  [[ -x $ZIG ]] || tar -xJf "$CACHE/zig-$zarch-macos-$ZIG_VER.tar.xz" -C "$CACHE"
  # Zig packages, fetched once into the cache (sources only, nothing compiled).
  [[ -f $CACHE/ghostty-$GHOSTTY_VER.fetched ]] || {
    print "  Downloading Ghostty's Zig packages"
    local tmp=$DIR/ghostty-fetch
    mkdir -p $tmp
    tar -xzf "$CACHE/${GHOSTTY_URL:t}" --strip-components 1 -C $tmp
    (cd $tmp && ZIG_GLOBAL_CACHE_DIR=$CACHE/zig-global zig_env $ZIG build --fetch $GHOSTTY_OPTS) >> "$LOG" 2>&1
    rm -rf $tmp
    touch $CACHE/ghostty-$GHOSTTY_VER.fetched
  }
}
GHOSTTY_OPTS=(-Doptimize=ReleaseFast -Dxcframework-target=native)
# Run a command with Xcode as the developer folder, even when xcode-select points at
# the Command Line Tools. Ghostty runs xcodebuild with only PATH set (no DEVELOPER_DIR),
# so Xcode's own xcodebuild, which finds Xcode from its own location, goes first on PATH.
zig_env() {
  mkdir -p $DIR/xcode-bin
  ln -sf $XCODE_DIR/usr/bin/xcodebuild $DIR/xcode-bin/xcodebuild
  DEVELOPER_DIR=$XCODE_DIR PATH=$DIR/xcode-bin:$PATH "$@"
}
ver_ghostty()     { print $GHOSTTY_VER; }
configure_ghostty() {
  tar -xzf "$CACHE/${GHOSTTY_URL:t}" --strip-components 1
  # A fresh Zig cache for every run with the fetched packages linked in, so no
  # compiled objects carry over from an earlier run.
  mkdir -p zig-global
  ln -s $CACHE/zig-global/p zig-global/p
}
build_ghostty() {
  local ZIG=$CACHE/zig-${arch/arm64/aarch64}-macos-$ZIG_VER/zig
  ZIG_GLOBAL_CACHE_DIR=$PWD/zig-global zig_env $ZIG build $GHOSTTY_OPTS
  [[ -d zig-out/Ghostty.app ]]
}

# --- Helpers -----------------------------------------------------------------

# Xcode's developer folder: the selected one if it's Xcode, else /Applications/Xcode*.app.
find_xcode() {
  XCODE_DIR=""
  local d=$(xcode-select -p 2>/dev/null)
  if [[ $d == *.app/* ]]; then XCODE_DIR=$d
  else
    for d in /Applications/Xcode*.app(N/On); do XCODE_DIR=$d/Contents/Developer; break; done
  fi
}

# Download a URL into the cache unless it's there with the right SHA-256.
fetch() {
  local url=$1 sha=$2 f=$CACHE/${1:t}
  [[ -f $f && $(shasum -a 256 "$f" | cut -d' ' -f1) == $sha ]] && return 0
  print "  Downloading ${url:t}"
  curl -fsSL --retry 2 -o "$f.part" "$url"
  [[ $(shasum -a 256 "$f.part" | cut -d' ' -f1) == $sha ]] || {
    print -P "  %F{red}${url:t} doesn't match its pinned SHA-256; not using it.%f" >&2
    rm -f "$f.part"; return 1
  }
  mv "$f.part" "$f"
}

# Install a Homebrew formula if its command is missing (formula name, command name).
need_brew() {
  command -v ${2:-$1} >/dev/null && return 0
  command -v brew >/dev/null || { print -P "  %F{red}${2:-$1} isn't installed and Homebrew isn't available.%f" >&2; return 1; }
  print -P "  %F{blue}==>%f Installing $1"
  brew install $1 >> "$LOG" 2>&1
}

# Run a project step in a folder with output to the log; REPLY = seconds taken.
step() {
  local dir=$1 fn=$2 t0=$EPOCHREALTIME
  print "\n=== $fn $(date '+%T') ===" >> "$LOG"
  ( cd "$dir" || exit 1; set -e; $fn ) >> "$LOG" 2>&1
  if (( $? )); then
    print -P "\n  %F{red}$fn failed.%f Last lines of $LOG:" >&2
    tail -30 "$LOG" | sed 's/^/    /' >&2
    return 1
  fi
  REPLY=$(awk -v a=$t0 -v b=$EPOCHREALTIME 'BEGIN {printf "%.1f", b - a}')
}

# Program-start test: the cost of starting a program, of a minimal compiler run, and
# of writing a small file (in $DIR, on the same disk as the builds). Builds do these
# thousands of times, and security software can add to each one. Sets START_MS,
# CLANG_MS and FILE_US to the medians of 3 rounds.
start_test() {
  local r i t d a=() b=() c=()
  print 'int x;' > $DIR/empty.c
  for r in 1 2 3; do
    t=$EPOCHREALTIME; for i in {1..1000}; do /usr/bin/true; done
    a+=($(( (EPOCHREALTIME - t) )))                 # seconds for 1,000 = ms each
    t=$EPOCHREALTIME; for i in {1..200}; do clang -c $DIR/empty.c -o $DIR/empty.o; done
    b+=($(( (EPOCHREALTIME - t) * 5 )))             # ms each
    d=$DIR/files; mkdir $d
    t=$EPOCHREALTIME; for i in {1..5000}; do print x > $d/$i; done
    c+=($(( (EPOCHREALTIME - t) * 200 )))           # µs each
    rm -rf $d
  done
  rm -f $DIR/empty.[co]
  START_MS=$(median %.2f $a) CLANG_MS=$(median $b) FILE_US=$(median %.0f $c)
}

# Median of numbers, printed with one decimal (or the format given first, such as %.2f).
median() {
  local f=%.1f
  [[ $1 == %* ]] && { f=$1; shift; }
  print -l -- "$@" | sort -n | awk -v f=$f '{v[NR] = $1} END {printf f, NR % 2 ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2}'
}
q() { print -rn -- "\"${1//\"/\"\"}\""; }    # quote a CSV text field

# The builds happen in $DIR, which is deleted however the script ends: finished,
# failed, Ctrl+C, or Terminal window closed. main runs in a background subshell so
# this script always gets control back to clean up (as in disk-speed.sh).
DIR=$(mktemp -d "$HOME/.build-speed.XXXXXX")
sub=""
# Stop main and everything it started (make, clang, xcodebuild, zig), and wait until
# they have all exited, so no compiler is still writing into $DIR when it's deleted.
zmodload zsh/zselect
tree() { local c; print $1; for c in $(pgrep -P $1); do tree $c; done; }
stop() {
  local pids=() p i alive
  print -P "\n%F{yellow}Stopped by $1;%f stopping the builds and deleting $DIR" >&2
  if [[ -n "$sub" ]]; then
    for i in 1 2; do          # twice: catch anything started while the first pass ran
      pids+=($(tree $sub))
      kill -TERM $pids 2>/dev/null
    done
    for i in {1..100}; do     # up to 10 seconds
      alive=0
      for p in $pids; do kill -0 $p 2>/dev/null && alive=1; done
      (( alive )) || break
      zselect -t 10
    done
  fi
  for i in {1..20}; do rm -rf "$DIR" 2>/dev/null; [[ -e "$DIR" ]] || break; zselect -t 20; done
  exit 130
}
trap 'stop INT' INT
trap 'stop TERM' TERM
trap 'stop HUP' HUP
( trap '' HUP; main ) &
sub=$!
wait "$sub"; rc=$?
rm -rf "$DIR"
# A failed build prints its own message; this makes any other failure visible too.
(( rc == 0 )) || print -P "%F{red}build-speed.sh stopped with exit code $rc.%f" >&2
exit $rc
