#!/bin/zsh
# build-summary.sh: rebuild the build speed table in README.md from build-results.csv.
#
#   zsh ~/mac-setup/speed-tests/build-summary.sh
#
# One row per machine (the machine column, so each VM host gets its own row), one
# column per project: the best median build time in seconds. The program-start
# columns come from the machine's newest run that has them. Runs on AC power with
# Low Power Mode off come first, then the fastest. The table goes between the
# <!-- build-summary:start --> and <!-- build-summary:end --> lines in README.md.

set -euo pipefail

here=${0:A:h}
csv=$here/build-results.csv
readme=$here/README.md

table=$(awk '
  # Split one CSV line into F[1..n], handling "quoted, fields" and "" escapes (as in summary.sh).
  function parse(line,   i, c, f, q, n) {
    n = 0; f = ""; q = 0
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (q) {
        if (c == "\"") { if (substr(line, i + 1, 1) == "\"") { f = f c; i++ } else q = 0 }
        else f = f c
      } else if (c == "\"") q = 1
      else if (c == ",") { F[++n] = f; f = "" }
      else f = f c
    }
    F[++n] = f
    return n
  }
  BEGIN { np = split("openssl ffmpeg sdl netnewswire ghostty", P, " ") }
  NR == 1 { parse($0); for (i in F) col[F[i]] = i; next }
  NF == 0 { next }
  {
    parse($0)
    m = F[col["machine"]]; p = F[col["project"]]
    if (!(m in seen)) {
      seen[m] = 1; order[++machines] = m
      cores = F[col["cores"]]
      if (F[col["p_cores"]] != "") cores = cores " (" F[col["p_cores"]] "P+" F[col["e_cores"]] "E)"
      info[m] = sprintf("| %s | %s | %s | %s | %s GB | %s |", m, F[col["model"]], F[col["chip"]], cores, F[col["ram_gb"]], F[col["vm"]])
    }
    if (F[col["start_ms"]] != "")
      start[m] = sprintf(" %s | %s | %s |", F[col["start_ms"]], F[col["clang_ms"]], F[col["file_us"]])
    if (F[col["date"]] > last[m]) last[m] = F[col["date"]]
    if (p == "") next                 # a --start-only run
    rank = (F[col["power"]] != "AC") * 2 + (F[col["low_power"]] == "True")
    t = F[col["build_s_median"]] + 0
    k = m SUBSEP p
    if (!(k in best) || rank < brank[k] || (rank == brank[k] && t < best[k])) {
      best[k] = t; brank[k] = rank
    }
  }
  END {
    h = "| Machine | Model | Chip | Cores | RAM | VM | Start (ms) | clang (ms) | File (µs) |"; s = "|---|---|---|---|--:|---|--:|--:|--:|"
    for (j = 1; j <= np; j++) { h = h " " P[j] " (s) |"; s = s "--:|" }
    print h " Date |"; print s "---|"
    for (i = 1; i <= machines; i++) {
      m = order[i]; line = info[m] ((m in start) ? start[m] : " – | – | – |")
      for (j = 1; j <= np; j++) { k = m SUBSEP P[j]; line = line " " ((k in best) ? sprintf("%.1f", best[k]) : "–") " |" }
      print line " " last[m] " |"
    }
  }
' "$csv")

grep -q '^<!-- build-summary:start -->$' "$readme" && grep -q '^<!-- build-summary:end -->$' "$readme" || {
  print -P "%F{red}README.md needs <!-- build-summary:start --> and <!-- build-summary:end --> lines.%f" >&2
  exit 1
}

tmp=$(mktemp)
TABLE=$table awk '
  /^<!-- build-summary:start -->$/ { print; print ENVIRON["TABLE"]; skip = 1; next }
  /^<!-- build-summary:end -->$/   { skip = 0 }
  !skip
' "$readme" > "$tmp"
cat "$tmp" > "$readme"   # keeps README.md's permissions, unlike mv
rm -f "$tmp"
print "Updated the build summary in $readme"
