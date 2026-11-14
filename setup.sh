#!/bin/zsh
# setup.sh: set up a new Mac.
#
#   Homebrew  -> command-line tools and apps (Brewfile)
#   uv        -> Python
#   mise      -> Ruby (+ Rails) and Node
#   rustup    -> Rust
#   Oh My Zsh -> shell
#   Claude Code (native installer, updates itself)
#
# Safe to run again: each step skips what is already done.
#
# On a new Mac (needs nothing but the built-in curl):
#   zsh -c "$(curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh)"
# From an existing copy:
#   zsh ~/mac-setup/setup.sh

set -euo pipefail

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

# Find the rest of the repo (Brewfile, dotfiles). If this script was run straight
# from the web, download the repo into ~/mac-setup with curl (git isn't installed yet).
SETUP_DIR="${0:A:h}"
if [[ ! -f "$SETUP_DIR/Brewfile" ]]; then
  SETUP_DIR="$HOME/mac-setup"
  if [[ ! -f "$SETUP_DIR/Brewfile" ]]; then
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
if ! have brew && [[ ! -x /opt/homebrew/bin/brew ]]; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
add_line 'eval "$(/opt/homebrew/bin/brew shellenv)"' ~/.zprofile

# --- 2. Tools and apps from the Brewfile ---
step "Brewfile"
# Homebrew only installs from third-party taps you have marked as trusted.
brew tap openai/tools
brew trust --formula openai/tools/tart openai/tools/softnet
brew bundle --file="$SETUP_DIR/Brewfile"

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

# --- 8. Dotfiles (an existing file is kept as <name>.backup) ---
step "Dotfiles"
link() {
  local src="$SETUP_DIR/dotfiles/$1" dest="$2"
  mkdir -p "${dest:h}"
  [[ -e "$dest" && ! -L "$dest" ]] && mv "$dest" "$dest.backup"
  ln -sfn "$src" "$dest"
  print "  $dest -> $src"
}
link gitconfig        ~/.gitconfig
link gitignore_global ~/.gitignore_global
link ghostty/config   ~/.config/ghostty/config
if [[ ! -f ~/.gitconfig.local ]]; then
  print -P "  %F{yellow}Set your Git name and email (kept out of this repo):%f"
  print '    git config --file ~/.gitconfig.local user.name  "Your Name"'
  print '    git config --file ~/.gitconfig.local user.email "you@example.com"'
fi

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

print -P "\n%F{green}Done.%f Open a new terminal (or Ghostty) to load the new shell setup."
