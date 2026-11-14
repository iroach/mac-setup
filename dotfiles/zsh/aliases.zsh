# Personal aliases and functions.
# Linked to ~/.oh-my-zsh/custom/aliases.zsh by setup.sh; Oh My Zsh loads it automatically.

# bwls [search]: list Bitwarden items as "name  username" columns (no passwords).
# Unlock first: export BW_SESSION="$(bw unlock --raw)"
bwls() {
  bw list items ${1:+--search "$1"} \
    | jq -r '.[] | [.name, (.login.username // "-")] | @tsv' \
    | sort -f \
    | column -t -s $'\t'
}
