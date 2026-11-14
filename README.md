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
| Cloud | AWS CLI, Cloudflare (cf, wrangler, cloudflared) |

Each language version is managed by exactly one tool, so there is never any doubt about which `python`, `ruby` or `node` you get.

## Use

On a new Mac, open Terminal and run:

```sh
curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh | zsh
```

That needs nothing but the built-in `curl`. The script downloads this repo to `~/mac-setup`, asks for your password once, installs Homebrew (which also installs the Xcode Command Line Tools and git) and then everything else. At the end it turns `~/mac-setup` into a Git repo, so `git pull` works later.

It is safe to run again (`zsh ~/mac-setup/setup.sh`), including on a Mac that is already set up: steps that are already done are skipped, installed Homebrew packages are not upgraded, and your own `~/.gitconfig` is kept.

On a new Mac, set your Git identity afterwards (it stays in `~/.gitconfig`, not in this repo):

```sh
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

## What is in here

- `setup.sh`: the setup script
- `Brewfile`: command-line tools, apps and fonts. Refresh it from a Mac with `brew bundle dump --file=Brewfile --force`, then trim.
- `dotfiles/`: used by `setup.sh`
  - `gitconfig`: shared Git settings, included from your `~/.gitconfig`
  - `gitignore_global` → linked to `~/.gitignore_global`
  - `ghostty/config` → linked to `~/.config/ghostty/config`
  - `zsh/aliases.zsh` → linked to `~/.oh-my-zsh/custom/aliases.zsh` (loaded automatically). Includes `update-mac-setup` (pull the latest version and rerun the setup) and `bwls [search]` (a readable list of Bitwarden items).

  A linked file replaces the existing one, which is kept as `<name>.backup`.

Secrets (tokens, keys) do not belong here. Keep them in a password or secrets manager.

## Testing

Tested on a clean macOS 27 virtual machine made with [Tart](https://tart.run):

```sh
tart clone ghcr.io/cirruslabs/macos-golden-gate-vanilla:latest golden-gate-vanilla
tart clone golden-gate-vanilla test && tart run test
```
