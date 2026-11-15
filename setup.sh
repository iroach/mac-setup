#!/bin/zsh
# setup.sh: set up a new Mac.
#
#   Homebrew  -> command-line tools and apps (Brewfile)
#   uv        -> Python
#   mise      -> Ruby (+ Rails) and Node
#   rustup    -> Rust
#   Oh My Zsh -> shell
#   Claude Code (native installer, updates itself)
#   dotfiles/ -> Git settings (included), gitignore, Ghostty config, zsh aliases (linked)
#   Finally pins Ghostty to the Dock and opens it with the new shell loaded.
#
# Safe to run again, also on a Mac that's already set up: each step skips what is
# already done, and installed Homebrew packages are not upgraded. See README.md.
#
# On a new Mac (needs nothing but the built-in curl):
#   curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh | zsh
# From an existing copy:
#   zsh ~/mac-setup/setup.sh
#
# Everything runs inside main(), which is only called on the last line. So when the
# script is piped into zsh, nothing runs until the whole file has downloaded.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"   # where this file is (meaningless when piped; checked below)
REPO="iroach/mac-setup"
PYTHON_VERSION="3.13"
RUBY_VERSION="4.0"
NODE_VERSION="lts"

step() { print -P "\n%F{blue}==>%f %B$1%b"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Add a line to a file once.
add_line() {
  local line="$1" file="$2"
  touch "$file"
  grep -qxF "$line" "$file" || print -r -- "$line" >> "$file"
}

main() {

# Find the rest of the repo (Brewfile, dotfiles). If this script was run straight
# from the web, download the repo into ~/mac-setup with curl (git isn't installed yet).
SETUP_DIR="$SCRIPT_DIR"
if [[ ! -f "$SETUP_DIR/Brewfile" ]]; then
  # Run from the web: use ~/mac-setup, and make sure it matches the latest version on GitHub.
  SETUP_DIR="$HOME/mac-setup"
  if [[ -d "$SETUP_DIR/.git" ]]; then
    step "Updating $SETUP_DIR"
    git -C "$SETUP_DIR" pull --ff-only \
      || print -P "  %F{yellow}Couldn't update $SETUP_DIR (local changes?). Using it as it is.%f"
  else
    step "Downloading $REPO to $SETUP_DIR"
    mkdir -p "$SETUP_DIR"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C "$SETUP_DIR"
  fi
fi

# Ask for the password once and keep sudo alive until the script ends.
step "Checking administrator access"
if ! sudo -n true 2>/dev/null; then   # skip the prompt if sudo already works without a password
  sudo -v
  while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
fi

# --- 1. Homebrew (also installs the Xcode Command Line Tools, which include git) ---
step "Homebrew"
# Homebrew lives in /opt/homebrew on Apple Silicon and /usr/local on Intel.
# (sysctl, not uname -m: under Rosetta, uname -m says x86_64 on Apple Silicon too.)
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]]; then
  BREW=/opt/homebrew/bin/brew
else
  BREW=/usr/local/bin/brew
fi
if [[ ! -x "$BREW" ]]; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW" shellenv)"
add_line "eval \"\$($BREW shellenv)\"" ~/.zprofile

# --- 2. Tools and apps from the Brewfile ---
step "Brewfile"
# Homebrew only installs from third-party taps you have marked as trusted.
brew tap openai/tools
brew trust --formula openai/tools/tart openai/tools/softnet
# --no-upgrade: install what's missing, but leave already-installed packages at their versions.
# Not fatal: on a Mac that's already set up, an app installed outside Homebrew
# (e.g. Ghostty downloaded from its website) makes its cask fail. Everything else still installs.
if ! brew bundle --no-upgrade --file="$SETUP_DIR/Brewfile"; then
  print -P "  %F{yellow}Some Brewfile items didn't install (see above). Often an app already in /Applications; continuing.%f"
fi

# --- 3. Oh My Zsh (before editing ~/.zshrc, since its installer replaces that file) ---
step "Oh My Zsh"
if [[ ! -d ~/.oh-my-zsh ]]; then
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Oh My Zsh plugins
sed -i '' 's/^plugins=(.*)$/plugins=(git gh aws rails aliases alias-finder)/' ~/.zshrc

# Shell setup for the tools below, kept in one marked block.
if ! grep -q '# >>> mac-setup >>>' ~/.zshrc 2>/dev/null; then
  cat >> ~/.zshrc <<'EOF'

# >>> mac-setup >>>
export PATH="$HOME/.local/bin:$PATH"          # uv tools, uv's python, Claude Code
eval "$(mise activate zsh)"                    # Ruby, Node
eval "$(zoxide init zsh)"
source <(fzf --zsh)
# <<< mac-setup <<<
EOF
fi
export PATH="$HOME/.local/bin:$PATH"

# --- 4. Python with uv ---
step "Python $PYTHON_VERSION (uv)"
uv python install "$PYTHON_VERSION" --default   # adds `python` and `python3` to ~/.local/bin

# --- 5. Rust with rustup ---
step "Rust (rustup)"
if [[ ! -x ~/.cargo/bin/rustup ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
add_line '. "$HOME/.cargo/env"' ~/.zprofile
source ~/.cargo/env
rustup update stable

# --- 6. Ruby, Rails and Node with mise ---
step "Ruby $RUBY_VERSION, Node $NODE_VERSION (mise)"
# Point Ruby's build at Homebrew's libraries.
export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@3) --with-libyaml-dir=$(brew --prefix libyaml) --with-gmp-dir=$(brew --prefix gmp) --enable-yjit"
# Also honour projects' .ruby-version, .nvmrc and .node-version files (mise ignores them by default).
mise settings set idiomatic_version_file_enable_tools ruby,node
mise use -g "ruby@$RUBY_VERSION" "node@$NODE_VERSION"
mise exec -- gem install rails --no-document
# Cloudflare: cf = Cloudflare API (beta), wrangler = Workers/Pages development
mise exec -- npm install -g yarn cf wrangler
mise reshim

# --- 7. Claude Code ---
step "Claude Code"
if ! have claude; then
  curl -fsSL https://claude.ai/install.sh | bash
fi

# --- 8. Dotfiles ---
step "Dotfiles"

# Git: ~/.gitconfig stays your own file (name, email, credentials; tools like gh and
# Git Credential Manager write to it). It just includes the shared settings from this repo.
GIT_SHARED="$SETUP_DIR/dotfiles/gitconfig"
if [[ -L ~/.gitconfig ]]; then   # undo the symlink made by earlier versions of this script
  rm ~/.gitconfig
  [[ -f ~/.gitconfig.backup ]] && mv ~/.gitconfig.backup ~/.gitconfig
fi
if ! git config --global --get-all include.path 2>/dev/null | grep -qxF "$GIT_SHARED"; then
  git config --global --add include.path "$GIT_SHARED"
fi
print "  ~/.gitconfig includes $GIT_SHARED"
if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
  print -P "  %F{yellow}Set your Git name and email:%f"
  print '    git config --global user.name  "Your Name"'
  print '    git config --global user.email "you@example.com"'
fi

# Other dotfiles are linked (an existing file is kept as <name>.backup).
link() {
  local src="$SETUP_DIR/dotfiles/$1" dest="$2"
  if [[ ! -e "$src" ]]; then
    print -P "  %F{yellow}Skipping $dest: $src is missing%f"
    return 0
  fi
  mkdir -p "${dest:h}"
  [[ -e "$dest" && ! -L "$dest" ]] && mv "$dest" "$dest.backup"
  ln -sfn "$src" "$dest"
  print "  $dest -> $src"
}
link gitignore_global ~/.gitignore_global
link ghostty/config   ~/.config/ghostty/config
link zsh/aliases.zsh  ~/.oh-my-zsh/custom/aliases.zsh

# --- 9. Make ~/mac-setup a Git repo (if it was downloaded with curl) so `git pull` works ---
if [[ ! -d "$SETUP_DIR/.git" ]]; then
  step "Connecting $SETUP_DIR to GitHub"
  git -C "$SETUP_DIR" init -q -b main
  git -C "$SETUP_DIR" remote add origin "https://github.com/$REPO.git"
  git -C "$SETUP_DIR" fetch -q origin main
  git -C "$SETUP_DIR" reset -q origin/main   # keeps the files, just records them as the repo's
  git -C "$SETUP_DIR" branch -q --set-upstream-to=origin/main main
fi

# --- Summary ---
step "Installed versions"
eval "$(mise activate zsh --shims)"
for cmd in brew git uv python ruby rails node yarn cf wrangler cloudflared aws rustc cargo claude; do
  printf "  %-7s %s\n" "$cmd" "$($cmd --version 2>&1 | head -1)"
done

print -P "\n%F{green}Done.%f"

# --- Pin Ghostty to the Dock (skipped if it's already there) ---
if [[ -d /Applications/Ghostty.app ]] \
   && ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q 'file:///Applications/Ghostty.app/'; then
  defaults write com.apple.dock persistent-apps -array-add \
    '<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file:///Applications/Ghostty.app/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>'
  killall Dock   # restart the Dock so it shows up
  print "Added Ghostty to the Dock."
fi

# --- Last step: open Ghostty, which starts with the new shell setup loaded ---
if [[ -d /Applications/Ghostty.app ]] && open -a Ghostty 2>/dev/null; then
  print "Opened Ghostty with the new setup."
else
  print "Open a new terminal to load the new shell setup."
fi
}

# When piped (curl … | zsh), zsh's input is the download, so give main() the keyboard
# instead; otherwise a prompt inside the script would read lines of the script itself.
if { : </dev/tty } 2>/dev/null; then
  main "$@" </dev/tty
else
  main "$@"
fi
