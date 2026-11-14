# mac-setup

Sets up a new Mac for development with one script.

| Area | Tool |
|---|---|
| Command-line tools and apps | [Homebrew](https://brew.sh), from the [`Brewfile`](Brewfile) |
| Python | [uv](https://docs.astral.sh/uv/) |
| Ruby (+ Rails) and Node | [mise](https://mise.jdx.dev) |
| Rust | [rustup](https://rustup.rs) |
| Shell | [Oh My Zsh](https://ohmyz.sh), zoxide, fzf |
| Terminal | [Ghostty](https://ghostty.org) |
| AI tools | Claude (app and Claude Code), Codex, Copilot CLI |
| Cloud | AWS CLI, Cloudflare (wrangler, cloudflared) |

Each language version is managed by exactly one tool, so there is never any doubt about which `python`, `ruby` or `node` you get.

## Use

On a new Mac, open Terminal and run:

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh)"
```

That needs nothing but the built-in `curl`. The script downloads this repo to `~/mac-setup`, asks for your password once, installs Homebrew (which also installs the Xcode Command Line Tools and git) and then everything else. At the end it turns `~/mac-setup` into a Git repo, so `git pull` works later.

It is safe to run again (`zsh ~/mac-setup/setup.sh`): steps that are already done are skipped.

Afterwards, set your Git identity (kept out of this repo):

```sh
git config --file ~/.gitconfig.local user.name  "Your Name"
git config --file ~/.gitconfig.local user.email "you@example.com"
```

## What is in here

- `setup.sh`: the setup script
- `Brewfile`: command-line tools, apps and fonts. Refresh it from a Mac with `brew bundle dump --file=Brewfile --force`, then trim.
- `dotfiles/`: linked into your home folder by `setup.sh` (an existing file is kept as `<name>.backup`)
  - `gitconfig` → `~/.gitconfig`
  - `gitignore_global` → `~/.gitignore_global`
  - `ghostty/config` → `~/.config/ghostty/config`

Secrets (tokens, keys) do not belong here. Keep them in a password or secrets manager.

## Testing

Tested on a clean macOS 27 virtual machine made with [Tart](https://tart.run):

```sh
tart clone ghcr.io/cirruslabs/macos-golden-gate-vanilla:latest golden-gate-vanilla
tart clone golden-gate-vanilla test && tart run test
```
