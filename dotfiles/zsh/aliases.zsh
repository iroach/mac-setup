# Personal aliases and functions.
# Linked to ~/.oh-my-zsh/custom/aliases.zsh by setup.sh; Oh My Zsh loads it automatically.

# update-mac-setup: get the latest ~/mac-setup from GitHub, run setup.sh,
# then restart the shell so new aliases and settings load.
update-mac-setup() {
  git -C ~/mac-setup pull --ff-only \
    && zsh ~/mac-setup/setup.sh \
    && exec zsh
}

# bwls [search]: list Bitwarden items as "name  username" columns (no passwords).
# Unlock first: export BW_SESSION="$(bw unlock --raw)"
bwls() {
  bw list items ${1:+--search "$1"} \
    | jq -r '.[] | [.name, (.login.username // "-")] | @tsv' \
    | sort -f \
    | column -t -s $'\t'
}
