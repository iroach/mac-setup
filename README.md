# mac-setup

Sets up a Mac for development with one command.

| Area | Tool |
|---|---|
| Command-line tools and apps | [Homebrew](https://brew.sh), from the [`Brewfile`](Brewfile) |
| Python | [uv](https://docs.astral.sh/uv/) |
| Ruby (+ Rails) and Node | [mise](https://mise.jdx.dev) |
| Rust | [rustup](https://rustup.rs) |
| Shell | [Oh My Zsh](https://ohmyz.sh), zoxide, fzf |
| Terminal | [Ghostty](https://ghostty.org) (pinned to the Dock) |
| AI tools | Claude Code, Codex, Copilot CLI |
| Cloud | AWS CLI, Cloudflare (`cf`, `wrangler`, `cloudflared`) |
| Passwords | Bitwarden CLI (`bw`) |

Each language version is managed by exactly one tool, so there is never any doubt about which `python`, `ruby` or `node` you get. Homebrew is not used for language versions.

## Set up a Mac

Open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh | zsh
```

That needs nothing but the built-in `curl`, and works on Apple Silicon and Intel Macs.

On an Intel Mac, the first run takes hours, not minutes: see [On an Intel Mac](#on-an-intel-mac).

The script:

1. downloads this repo to `~/mac-setup` (or updates it, if it's already there)
2. asks for your password once
3. installs Homebrew, which also installs the Xcode Command Line Tools and git
4. installs everything in the `Brewfile`
5. installs Oh My Zsh, then Python (uv), Rust (rustup), Ruby, Rails and Node (mise), and Claude Code
6. sets up the dotfiles (see below)
7. turns `~/mac-setup` into a Git repo connected to GitHub
8. prints the installed versions, pins Ghostty to the Dock and opens it with the new shell loaded

Then set your Git identity. It stays in `~/.gitconfig`, not in this repo:

```sh
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### On a Mac that's already set up

The script is safe to run again, including on a Mac set up by hand:

- steps that are already done are skipped
- Homebrew packages and Rails that are already installed are **not** upgraded (`brew bundle --no-upgrade`, `gem install --conservative`). `update-mac` upgrades Homebrew packages later. To upgrade Rails: `gem update rails`
- an app already in `/Applications` but not installed by Homebrew (e.g. Ghostty from its website) makes its Brewfile line fail; the script warns and carries on
- your `~/.gitconfig` is kept; the shared settings are only *included* from it
- a dotfile it replaces is kept as `<name>.backup`

Things worth checking first on an older Mac:

- A `~/.tool-versions` or `~/.ruby-version` in your **home folder** (e.g. left over from asdf) overrides mise's global Ruby and Node everywhere under your home folder. Delete it, or run `mise install` to install what it asks for.
- `python3` becomes uv's Python, ahead of any python.org or Homebrew Python on your PATH.
- Shared Git settings win where they overlap with yours (e.g. `core.editor = nvim`).

### On an Intel Mac

The script works, but the first run is slow. Homebrew supports Intel Macs only at its lowest tier and plans to stop running on them in or after September 2027 ([Support Tiers](https://docs.brew.sh/Support-Tiers)). Most packages have no prebuilt Intel version, so Homebrew compiles them.

- **Why it takes hours:** `uv`, `mise`, `zoxide`, `bitwarden-cli` and `cocoapods` are written in Rust (or need it to build). To build any of them, Homebrew first builds its own Rust, and Rust needs LLVM. `neovim` pulls in 29 dependencies, including a whole Python just to build documentation for one of them. Some things do come prebuilt (e.g. GHC for `pandoc`).
- **Times seen on a 16-thread Core i9:** LLVM 1 h 12 min, Rust 28 min, `uv` 15 min, `gettext` 10 min. Most of the rest take seconds to a few minutes each.
- **It looks stuck but isn't:** Homebrew shows little while compiling. `top -o cpu` shows `clang` or `rustc` working. A single `rustc` at 100% for a long time is the final optimization step of a Rust program, so it's nearly done. To see what's still to install: `brew bundle check --verbose --no-upgrade --file=~/mac-setup/Brewfile`.
- **Keep it awake:** run `caffeinate -dims` in another terminal (a sleeping Mac pauses the build), and keep a laptop plugged in.
- **Stopping is safe:** a rerun skips what's done. Only the package being built at that moment starts over.
- **Afterwards:** `brew autoremove` removes build-only packages such as LLVM and Rust (about 2 GB). Check what it lists first. A later `brew upgrade` of `uv`, `mise` or `zoxide` builds again from source, and `update-mac` runs `brew upgrade`, so an update can take a while when one of them has a new version.
- Tart and any app without an Intel build fail their Brewfile line; the script warns and carries on.

## Update

```sh
update-mac
```

This pulls the latest version of `~/mac-setup`, upgrades Homebrew packages (`brew upgrade`), reruns `setup.sh`, and restarts the shell. The long form is `cd ~/mac-setup && git pull && brew upgrade && zsh setup.sh`.

After pushing a change, `raw.githubusercontent.com` can serve the old `setup.sh` for up to about 5 minutes, so the curl one-liner may lag behind. `update-mac` doesn't have that delay.

## What is in here

- `setup.sh`: the setup script. Its body is a `main` function called on the last line, so a partial download runs nothing when piped into zsh.
- `Brewfile`: command-line tools and apps. To see what a Mac has that's not in here: `brew bundle dump --file=- | diff - Brewfile`.
- `dotfiles/`:
  - `gitconfig`: shared Git settings, included from your `~/.gitconfig` (`include.path`)
  - `gitignore_global` → linked to `~/.gitignore_global`
  - `ghostty/config` → linked to `~/.config/ghostty/config`
  - `zsh/aliases.zsh` → linked to `~/.oh-my-zsh/custom/aliases.zsh` (Oh My Zsh loads it automatically). It contains:
    - `update-mac`: pull the latest setup, upgrade Homebrew packages and rerun the setup
    - `bwls [search]`: a readable list of Bitwarden items, name and username only. Unlock first: `export BW_SESSION="$(bw unlock --raw)"`
    - the `ghostty` command on your PATH (e.g. `ghostty +list-themes`)
- `CLAUDE.md`: notes for working on this repo with Claude Code

Secrets (tokens, keys) do not belong here. Keep them in a password or secrets manager.

## Changing things

- **Add a tool or app:** add a line to the `Brewfile`. For a third-party tap, add the `tap` line and a `brew trust --formula …` line in `setup.sh` (Homebrew only installs from trusted taps).
- **Add a language tool:** Python tools with `uv tool install`, Node tools in the `npm install -g` line, Rust tools with `cargo install`.
- **Add an alias or shell function:** `dotfiles/zsh/aliases.zsh`.
- Keep every step safe to rerun, and test on a clean VM (below) before relying on it.

## Testing

Test on a clean macOS virtual machine made with [Tart](https://tart.run) (Apple Silicon only):

```sh
brew install openai/tools/tart     # may first need: brew trust --formula openai/tools/tart openai/tools/softnet

# once: download a clean macOS 27 image (~30 GB) to use as a template
tart clone ghcr.io/cirruslabs/macos-golden-gate-vanilla:latest golden-gate-vanilla

# each test: a fresh copy with a bigger disk
tart delete test 2>/dev/null; tart clone golden-gate-vanilla test
tart set test --disk-size 100
tart run test
```

In the VM (login `admin` / `admin`), open Terminal and run:

```sh
sudo diskutil apfs resizeContainer disk0s2 0     # use the bigger disk ("too small" error = already done)
curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh | zsh
```

Then, in the Ghostty window it opens, check:

```sh
which update-mac bwls ghostty
python --version; ruby --version; node --version; cf --version; claude --version
git config --global --get-all include.path       # → ~/mac-setup/dotfiles/gitconfig
git -C ~/mac-setup status                        # → up to date with origin/main
```

Notes on the VM:

- The vanilla image differs from a brand-new Mac in two ways: the Xcode Command Line Tools are already installed, and `sudo` needs no password. So those two parts of the script aren't really exercised.
- Copy and paste between your Mac and the VM doesn't work with the vanilla image (that needs the Tart guest agent), so type the commands.
- `tart list` shows your VMs; `tart delete test` removes one; `tart prune --entries=caches` removes downloaded images.

## Open ideas

- **Bitwarden without retyping the master password:** [`rbw`](https://github.com/doy/rbw) (unofficial, unlocks once and auto-locks after a timeout), or a `bwu` function that keeps the `bw` session in the macOS Keychain.
- **Developer secrets:** Bitwarden Secrets Manager (`bws run -- <command>`) instead of tokens in shell files.
- **Faster Intel setup:** on Intel, install `uv`, `mise` and `zoxide` with their official installers (`https://astral.sh/uv/install.sh`, `https://mise.run`, zoxide's `install.sh`), which download prebuilt Intel versions in seconds. Skip the optional Rust and Haskell tools (`bitwarden-cli`, `cocoapods`, `pandoc`) with `unless Hardware::CPU.intel?` in the Brewfile. Nothing would need LLVM or Rust built then. This goes against "Homebrew for command-line tools", so it's Intel only, and those three tools would update with `uv self update` and `mise self-update` instead of `brew upgrade`.
