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

That needs nothing but the built-in `curl`. The script:

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
- Homebrew packages that are already installed are **not** upgraded (`brew bundle --no-upgrade`)
- an app already in `/Applications` but not installed by Homebrew (e.g. Ghostty from its website) makes its Brewfile line fail; the script warns and carries on
- your `~/.gitconfig` is kept; the shared settings are only *included* from it
- a dotfile it replaces is kept as `<name>.backup`

Things worth checking first on an older Mac:

- A `~/.tool-versions` or `~/.ruby-version` in your **home folder** (e.g. left over from asdf) overrides mise's global Ruby and Node everywhere under your home folder. Delete it, or run `mise install` to install what it asks for.
- `python3` becomes uv's Python, ahead of any python.org or Homebrew Python on your PATH.
- Shared Git settings win where they overlap with yours (e.g. `core.editor = nvim`).

## Update

```sh
update-mac
```

This pulls the latest version of `~/mac-setup`, reruns `setup.sh`, and restarts the shell. The long form is `cd ~/mac-setup && git pull && zsh setup.sh`.

After pushing a change, `raw.githubusercontent.com` can serve the old `setup.sh` for up to about 5 minutes, so the curl one-liner may lag behind. `update-mac` doesn't have that delay.

## What is in here

- `setup.sh`: the setup script. Its body is a `main` function called on the last line, so a partial download runs nothing when piped into zsh.
- `Brewfile`: command-line tools and apps. To see what a Mac has that's not in here: `brew bundle dump --file=- | diff - Brewfile`.
- `dotfiles/`:
  - `gitconfig`: shared Git settings, included from your `~/.gitconfig` (`include.path`)
  - `gitignore_global` → linked to `~/.gitignore_global`
  - `ghostty/config` → linked to `~/.config/ghostty/config`
  - `zsh/aliases.zsh` → linked to `~/.oh-my-zsh/custom/aliases.zsh` (Oh My Zsh loads it automatically). It contains:
    - `update-mac`: pull the latest setup and rerun it
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
