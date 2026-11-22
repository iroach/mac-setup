#!/bin/zsh
# vm-build-speed.sh: run build-speed.sh inside a Tart VM on this Mac, to compare
# with the same test run directly on the Mac. Security software on the host
# (EDR, antivirus) can't see inside the VM, so the difference shows its cost.
#
#   zsh ~/mac-setup/speed-tests/vm-build-speed.sh prepare IMAGE   # once: make the build-speed-base VM from IMAGE
#   zsh ~/mac-setup/speed-tests/vm-build-speed.sh run [options]   # run the test in a fresh copy of it
#
# prepare: clones IMAGE (a local VM name, or a registry image such as a Cirrus Labs
#   macOS image) to build-speed-base, starts it, and installs Homebrew (with the
#   Command Line Tools) and cmake. The VM needs an "admin" user with Remote Login on
#   and passwordless sudo, as Cirrus Labs images have. SSH uses your key if the VM
#   already accepts it, else the password in VM_PASSWORD (default: admin), once, to
#   add your key.
# run: clones build-speed-base to a throwaway VM with fixed CPUs and memory, shares
#   this repo with it, runs build-speed.sh there with the options given, and deletes
#   the VM afterwards. Options go to build-speed.sh (--project, --runs, --save,
#   --submit, --note, --start-only); --submit opens the issue form on this Mac. Also:
#     --name "Tart VM on MacBook Pro M5 Pro"   machine name (default: "Tart VM on <this Mac's model>")
#     --cpu 4 --memory 8                       VM size (default 4 CPUs, 8 GB, the same on every Mac)
# With --save, the results go straight into this repo's build-results.csv.
# Needs tart (installed by setup.sh; see the README) and an SSH key (~/.ssh/id_ed25519).
# (Help text ends on the line above.)

set -euo pipefail

SELF=${0:A}
HERE=${SELF:h}
REPO=${HERE:h}
BASE=${BUILD_SPEED_BASE:-build-speed-base}   # the prepared VM; override to keep several
KEY=$HOME/.ssh/id_ed25519
SSH_OPTS=(-i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR -o ConnectTimeout=5)

usage() { sed -n '2,/Help text ends/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; }
die()   { print -P "%F{red}$*%f" >&2; exit 1; }
say()   { print -P "%F{blue}==>%f $*"; }

command -v tart >/dev/null || die "tart isn't installed: brew tap openai/tools && brew trust --formula openai/tools/tart && brew install openai/tools/tart"
[[ -f $KEY.pub ]] || die "Needs an SSH key at $KEY (ssh-keygen -t ed25519)"

VM=""          # the VM this script started, stopped and (for run) deleted on exit
DELETE=0
cleanup() {
  [[ -n "$VM" ]] || return 0
  tart stop "$VM" >/dev/null 2>&1 || true
  (( DELETE )) && tart delete "$VM" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Start $VM without a window (sharing this repo as "mac-setup"), and wait for SSH.
boot() {
  tart run --no-graphics --dir=mac-setup:$REPO "$VM" >/dev/null 2>&1 &
  local i
  say "Starting $VM"
  for i in {1..90}; do
    IP=$(tart ip "$VM" 2>/dev/null) && nc -z -G 2 $IP 22 >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "$VM didn't start, or Remote Login is off in it"
}

# Run a command in the VM as admin. Uses the key; if the VM doesn't accept it yet,
# logs in once with VM_PASSWORD to add it.
vm() { ssh $SSH_OPTS -o BatchMode=yes admin@$IP "$@"; }
key_login() {
  vm true 2>/dev/null && return 0
  say "Adding your SSH key to the VM (password login, once)"
  local askpass=$(mktemp)
  print -r -- "#!/bin/sh
printf '%s\n' \"\$VM_PASSWORD\"" > $askpass; chmod 700 $askpass
  VM_PASSWORD=${VM_PASSWORD:-admin} SSH_ASKPASS=$askpass SSH_ASKPASS_REQUIRE=force \
    ssh $SSH_OPTS -o PubkeyAuthentication=no admin@$IP \
    'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys' < $KEY.pub \
    || { rm -f $askpass; die "Couldn't log in to the VM as admin (set VM_PASSWORD to its password)"; }
  rm -f $askpass
  vm true || die "The VM still doesn't accept your SSH key"
}

prepare() {
  local image=${1:?prepare needs an image, such as a local VM name}
  tart list --quiet 2>/dev/null | grep -qx $BASE && die "$BASE already exists; delete it first: tart delete $BASE"
  say "Cloning $image to $BASE"
  tart clone "$image" $BASE
  VM=$BASE DELETE=0
  boot
  key_login
  vm 'sudo -n true' 2>/dev/null || die "admin needs passwordless sudo in the VM"
  say "Installing Homebrew, the Command Line Tools and cmake in the VM (several minutes)"
  vm '[[ -x /opt/homebrew/bin/brew ]] || NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >/dev/null
      eval "$(/opt/homebrew/bin/brew shellenv)"
      brew list cmake >/dev/null 2>&1 || brew install -q cmake >/dev/null
      print "  $(sw_vers -productVersion), $(xcode-select -p), $(cmake --version | sed -n 1p)"'
  say "$BASE is ready. Run the test with: zsh $SELF run"
}

run() {
  local cpu=4 memory=8 name="" args=()
  while (( $# )); do
    case "$1" in
      --cpu)    cpu=${2:?}; shift ;;
      --memory) memory=${2:?}; shift ;;
      --name)   name=${2:?}; shift ;;
      *)        args+=("$1") ;;
    esac
    shift
  done
  [[ -n "$name" ]] || name="Tart VM on $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ && !n++ {print $2}')"
  tart list --quiet 2>/dev/null | grep -qx $BASE || die "No $BASE VM yet. Make it first: zsh $SELF prepare IMAGE"
  VM=build-speed-run-$$ DELETE=1
  tart clone $BASE $VM
  tart set $VM --cpu $cpu --memory $(( memory * 1024 ))
  boot
  key_login
  say "Waiting 60 seconds for the VM to finish starting up (indexing and so on)"
  sleep 60
  say "Running build-speed.sh in the VM ($cpu CPUs, $memory GB) as \"$name\""
  # -t: a terminal, so Ctrl+C here stops the test in the VM too. With --submit, the
  # VM prints the issue link (it isn't signed in to GitHub) and this Mac opens it.
  local out=$(mktemp)
  ssh -t $SSH_OPTS -o BatchMode=yes admin@$IP \
    "eval \"\$(/opt/homebrew/bin/brew shellenv)\"; zsh '/Volumes/My Shared Files/mac-setup/speed-tests/build-speed.sh' --name ${(q)name} ${(j: :)${(q)args}}" \
    | tee $out
  local url=$(sed -n 's/^SUBMIT-URL: \([^[:space:]]*\).*/\1/p' $out | tr -d '\r')
  rm -f $out
  [[ -n "$url" ]] && open "$url"
  return 0
}

case "${1:-}" in
  prepare) shift; prepare "$@" ;;
  run)     shift; run "$@" ;;
  -h|--help|"") usage ;;
  *) die "Unknown command: $1 (prepare or run; see --help)" ;;
esac
