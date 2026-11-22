#!/bin/zsh
# summary.sh: rebuild the summary table in README.md from results.csv.
#
#   zsh ~/mac-setup/speed-tests/summary.sh
#
# One row per model: its best-case run. Runs with VM and FileVault off come first,
# then full runs (with the uncached read) before --quick ones, then the fastest
# uncached read, then the fastest sequential read. The table goes between the
# <!-- summary:start --> and <!-- summary:end --> lines in README.md.

set -euo pipefail

here=${0:A:h}
csv=$here/results.csv
readme=$here/README.md

table=$(awk '
  # Split one CSV line into F[1..n], handling "quoted, fields" and "" escapes.
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
  function num(v) { return v == "" ? "–" : sprintf("%\047d", v) }
  function better(r, best) {   # is row r a better best case than row best?
    if (R[r, "rank"] != R[best, "rank"]) return R[r, "rank"] < R[best, "rank"]
    if (R[r, "unc"] + 0 != R[best, "unc"] + 0) return R[r, "unc"] + 0 > R[best, "unc"] + 0
    return R[r, "sr"] + 0 > R[best, "sr"] + 0
  }
  NR == 1 { parse($0); for (i in F) col[F[i]] = i; next }
  NF == 0 { next }
  {
    parse($0)
    r = NR
    R[r, "line"] = sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |", \
      F[col["machine"]], F[col["model"]], F[col["vm"]], F[col["filevault"]], \
      num(F[col["seq_write_mbs"]]), num(F[col["seq_read_mbs"]]), num(F[col["seq_read_uncached_mbs"]]), \
      num(F[col["rand_read_iops"]]), num(F[col["rand_write_iops"]]), F[col["date"]])
    R[r, "rank"] = (F[col["vm"]] == "True") * 4 + (F[col["filevault"]] == "True") * 2 + (F[col["seq_read_uncached_mbs"]] == "")
    R[r, "unc"] = F[col["seq_read_uncached_mbs"]]
    R[r, "sr"] = F[col["seq_read_mbs"]]
    m = F[col["model"]]
    if (!(m in best)) { order[++models] = m; best[m] = r }
    else if (better(r, best[m])) best[m] = r
  }
  END {
    print "| Machine | Model | VM | FileVault | Seq. write (MB/s) | Seq. read (MB/s) | Seq. read, uncached (MB/s) | Random 4K read (IOPS) | Random 4K write (IOPS) | Date |"
    print "|---|---|---|---|--:|--:|--:|--:|--:|---|"
    for (i = 1; i <= models; i++) print R[best[order[i]], "line"]
  }
' "$csv")

grep -q '^<!-- summary:start -->$' "$readme" && grep -q '^<!-- summary:end -->$' "$readme" || {
  print -P "%F{red}README.md needs <!-- summary:start --> and <!-- summary:end --> lines.%f" >&2
  exit 1
}

tmp=$(mktemp)
TABLE=$table awk '
  /^<!-- summary:start -->$/ { print; print ENVIRON["TABLE"]; skip = 1; next }
  /^<!-- summary:end -->$/   { skip = 0 }
  !skip
' "$readme" > "$tmp"
cat "$tmp" > "$readme"   # keeps README.md's permissions, unlike mv
rm -f "$tmp"
print "Updated the summary in $readme"
