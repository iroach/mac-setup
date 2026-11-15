# Personal aliases and functions.
# Linked to ~/.oh-my-zsh/custom/aliases.zsh by setup.sh; Oh My Zsh loads it automatically.

# ghostty command (e.g. ghostty +list-themes). The app doesn't add it to PATH itself.
[[ -d /Applications/Ghostty.app/Contents/MacOS ]] && path=(/Applications/Ghostty.app/Contents/MacOS $path)

# update-mac: get the latest ~/mac-setup from GitHub, upgrade Homebrew packages,
# run setup.sh, then restart the shell so new aliases and settings load.
# brew upgrade runs here, not in setup.sh, so a first run on a Mac set up by hand
# doesn't upgrade anything. It runs before setup.sh so tools like uv are current
# when setup.sh uses them. A failed upgrade (e.g. one app) doesn't stop the rest.
update-mac() {
  git -C ~/mac-setup pull --ff-only || return
  brew upgrade || print -P "%F{yellow}Some Homebrew upgrades failed (see above); continuing.%f"
  zsh ~/mac-setup/setup.sh && exec zsh
}

# bwls [search]: list Bitwarden items as "name  username" columns (no passwords).
# Unlock first: export BW_SESSION="$(bw unlock --raw)"
bwls() {
  bw list items ${1:+--search "$1"} \
    | jq -r '.[] | [.name, (.login.username // "-")] | @tsv' \
    | sort -f \
    | column -t -s $'\t'
}
