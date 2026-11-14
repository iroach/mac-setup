# Working on mac-setup

A public repo that sets up a Mac with one command: `curl -fsSL https://raw.githubusercontent.com/iroach/mac-setup/main/setup.sh | zsh`. See README.md for what it installs and how to test it.

## Decisions already made (don't revisit without asking)

- One tool per language: **uv** for Python, **mise** for Ruby and Node, **rustup** for Rust. Homebrew is for command-line tools and apps only, never language versions. Don't add Python to mise or Node/Ruby/Python to the Brewfile.
- mise reads `.ruby-version`, `.nvmrc` and `.node-version` because `setup.sh` sets `idiomatic_version_file_enable_tools`; `.tool-versions` is read by default.
- `~/.gitconfig` stays the user's own file; `dotfiles/gitconfig` is added with `include.path`, never symlinked over it (tools like `gh` and Git Credential Manager write to `~/.gitconfig`, and those writes must not land in this public repo).
- Other dotfiles are symlinked by the `link` function in `setup.sh`; an existing file is kept as `<name>.backup`.
- Personal aliases and functions go in `dotfiles/zsh/aliases.zsh`.
- Cloudflare: `cf` (Cloudflare's new CLI, beta) and `wrangler` come from npm; `cloudflared` from Homebrew.
- Claude Code uses Anthropic's native installer (it updates itself), not the Homebrew cask.

## Rules for setup.sh

- It's zsh (`print -P`, `${0:A:h}`), not bash or sh.
- Every step must be safe to rerun, and safe on a Mac that's already set up by hand: check before installing, `brew bundle --no-upgrade`, don't replace user files without a `.backup`.
- The body stays inside `main()`, called on the last line with `</dev/tty`, so `curl … | zsh` never runs a partial download and prompts read the keyboard.
- Git isn't available until Homebrew has installed the Command Line Tools, so nothing before step 1 may use git.
- Third-party Homebrew taps need `brew trust --formula …` before `brew bundle`.

## Before pushing

- Check: `zsh -n setup.sh` and `zsh -n dotfiles/zsh/aliases.zsh`.
- Test real changes on a clean Tart VM (README → Testing). Don't run `setup.sh` on the user's own Mac to test it.
- This repo is **public**: no tokens, keys, email addresses or other personal details in files or commit messages. Scan before committing: `grep -rnIE 'ghp_|github_pat_|sk-|AKIA|token=|password=' . --exclude-dir=.git`.
- Commit with the GitHub noreply address for the `iroach` account, not a personal email.
- The repo belongs to the `iroach` GitHub account. If `gh` is logged in to several accounts, push with that one: `GH_TOKEN=$(gh auth token -u iroach) git push` or `gh auth switch -u iroach`.
