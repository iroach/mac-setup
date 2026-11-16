# Brewfile: command-line tools and apps for a new Mac.
# Install with: brew bundle --file=~/mac-setup/Brewfile
#
# Language versions are NOT managed here:
#   Python -> uv     Ruby/Node -> mise     Rust -> rustup

# Third-party taps (setup.sh marks their formulas as trusted first)
tap "openai/tools"

# --- Version managers ---
brew "mise"
brew "uv"

# --- Needed to build Ruby with mise ---
brew "libyaml"
brew "openssl@3"
brew "gmp"

# --- Shell and terminal tools ---
brew "git"
brew "gh"
# brew "gitui"           # off: not used lately. Uncomment to install.
brew "neovim"
brew "fzf"
brew "zoxide"
brew "jq"
brew "wget"

# --- Development ---
brew "cmake"
# brew "watchman"        # off: for React Native (Metro) and Jest watch mode. Uncomment to install.
# brew "cocoapods"       # off: projects pin it in their Gemfile (`bundle exec pod`). Uncomment to install.
brew "swiftlint"
# No JDK: if a project needs Java, `mise use java@temurin-21` (prebuilt, per project, works on Intel).
# brew "pkl"             # off: only used for a workshop. Uncomment to install.
# brew "postgresql@17"   # off: not needed on every Mac. Uncomment to install, or run it in Docker per project.

# --- Cloud and work tools ---
brew "awscli"
brew "cloudflared"     # Cloudflare tunnels (cf and wrangler are installed with npm by setup.sh)
brew "bitwarden-cli"
brew "openconnect"

# --- Media, documents and other utilities ---
brew "ffmpeg"
brew "pandoc"
# No pdfly: if needed, `uv tool install pdfly` (prebuilt, no Homebrew Python build).
brew "libpst"
brew "guile"
brew "jmeter"
brew "nmap"

# --- Virtual machines ---
brew "openai/tools/tart"

# --- Apps ---
cask "ghostty"
# No Claude desktop app: Claude Code (the CLI) is installed by setup.sh with Anthropic's installer.
cask "codex"
cask "copilot-cli"
cask "meld"
cask "git-credential-manager"

# No fonts: Ghostty uses the built-in SF Mono. Nerd Fonts (e.g. font-jetbrains-mono-nerd-font)
# unpack 100-150 font files / 250-400 MB each and stall setup for minutes.
