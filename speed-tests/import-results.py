#!/usr/bin/env python3
"""Add build-speed results from a "Build speed results" issue to build-results.csv.

    gh issue view 42 --json body -q .body | python3 -I speed-tests/import-results.py 42

Reads the issue body on stdin (or from $ISSUE_BODY), checks every row strictly,
and appends the new ones. The issue form's answers and the issue number go into
each row's notes. Exits with an error, changing nothing, if any row is wrong.
The issue body is untrusted input: nothing from it is run, only checked and copied.
"""
import csv
import io
import os
import re
import sys
from pathlib import Path

CSV_PATH = Path(__file__).resolve().parent / "build-results.csv"
PROJECTS = {"", "openssl", "ffmpeg", "sdl", "netnewswire", "ghostty"}
QUOTED = {"machine", "model", "chip", "clang", "xcode", "version", "notes"}
MANAGED = {
    "Personal Mac, no security software added": "not work managed",
    "Work-managed Mac, with security software": "work managed",
    "Virtual machine": "VM",
    "Not sure": "",
}

TEXT = re.compile(r"^[^\x00-\x1f|\x7f]*$")      # printable, no | (it would break the README table)
INT = re.compile(r"^\d{1,4}$")
NUM = re.compile(r"^\d{1,5}(\.\d{1,2})?$")
CHECKS = {
    "date": re.compile(r"^20\d\d-[01]\d-[0-3]\d$"),
    "machine": re.compile(r"^[^\x00-\x1f|\x7f\"]{1,60}$"),
    "model": re.compile(r"^[A-Za-z0-9,]{1,30}$"),
    "chip": re.compile(r"^[^\x00-\x1f|\x7f]{1,80}$"),
    "arch": re.compile(r"^(arm64|x86_64)$"),
    "cores": INT, "ram_gb": INT,
    "p_cores": re.compile(r"^(\d{1,4})?$"), "e_cores": re.compile(r"^(\d{1,4})?$"),
    "macos": re.compile(r"^\d{2}(\.\d{1,2}){0,2}$"),
    "vm": re.compile(r"^(True|False)$"), "low_power": re.compile(r"^(True|False)$"),
    "clang": re.compile(r"^[^\x00-\x1f|\x7f]{0,60}$"), "xcode": re.compile(r"^[^\x00-\x1f|\x7f]{0,30}$"),
    "power": re.compile(r"^(AC|battery)$"),
    "version": re.compile(r"^[A-Za-z0-9.\-]{0,20}$"),
    "notes": re.compile(r"^[^\x00-\x1f|\x7f]{0,200}$"),
}
BUILD = ["jobs", "runs", "configure_s", "build_s_median", "build_s_min", "build_s_max"]
START = ["start_ms", "clang_ms", "file_us"]


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def sections(body):
    """The issue form's answers, by heading ("### Results" -> "Results")."""
    out, name = {}, None
    for line in body.replace("\r\n", "\n").split("\n"):
        if line.startswith("### "):
            name = line[4:].strip()
            out[name] = []
        elif name:
            out[name].append(line)
    return {k: "\n".join(v).strip() for k, v in out.items()}


def clean_text(s, limit):
    s = " ".join(s.split())                       # no newlines or runs of spaces
    s = re.sub(r"[\x00-\x1f|\x7f\"]", "", s)       # no control characters, |, or quotes
    return s[:limit]


def check_row(row, header, n):
    if len(row) != len(header):
        fail(f"row {n} has {len(row)} fields, expected {len(header)}")
    r = dict(zip(header, row))
    for col, rx in CHECKS.items():
        if not rx.match(r[col]):
            fail(f"row {n}: {col} {r[col]!r} isn't valid")
    if r["project"] not in PROJECTS:
        fail(f"row {n}: unknown project {r['project']!r}")
    for col in START:
        if r[col] and not NUM.match(r[col]):
            fail(f"row {n}: {col} {r[col]!r} isn't a number")
    if r["project"]:
        for col in BUILD:
            if not (INT if col in ("jobs", "runs") else NUM).match(r[col]):
                fail(f"row {n}: {col} {r[col]!r} isn't a number")
        if not (float(r["build_s_min"]) <= float(r["build_s_median"]) <= float(r["build_s_max"])):
            fail(f"row {n}: build times aren't min <= median <= max")
    else:
        if any(r[c] for c in ["version"] + BUILD):
            fail(f"row {n}: a row without a project can't have build times")
        if not all(r[c] for c in START):
            fail(f"row {n}: a row without a project needs the program-start results")
    return r


def to_line(r, header):
    def field(col):
        v = r[col]
        if col not in QUOTED or (col == "version" and not r["project"]):   # as build-speed.sh writes them
            return v
        return '"' + v.replace('"', '""') + '"'
    return ",".join(field(c) for c in header)


def main():
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        fail("usage: import-results.py ISSUE_NUMBER < issue-body")
    issue = sys.argv[1]
    body = os.environ.get("ISSUE_BODY") or sys.stdin.read()
    form = sections(body)

    rows_text = form.get("Results", "")
    rows_text = re.sub(r"^```[a-z]*\n?|\n?```$", "", rows_text.strip(), flags=re.M)
    lines = [l.strip() for l in rows_text.split("\n") if l.strip()]
    if not lines:
        fail("the Results section is empty")
    if len(lines) > 20:
        fail(f"{len(lines)} rows; at most 20 per issue")

    managed = form.get("How is this Mac set up?", "")
    if managed not in MANAGED:
        fail(f"unknown answer to 'How is this Mac set up?': {managed!r}")
    note = form.get("Notes", "")
    note = "" if note == "_No response_" else clean_text(note, 100)

    with CSV_PATH.open(newline="") as f:
        existing = list(csv.reader(f))
    header = existing[0]
    # Rows already there, compared without notes (imported rows have extra notes).
    known = {tuple(r[:-1]) for r in existing[1:]}

    new = []
    for n, line in enumerate(lines, 1):
        if line.startswith("date,"):
            continue                              # a pasted header line
        row = next(csv.reader(io.StringIO(line)))
        r = check_row(row, header, n)
        if tuple(row[:-1]) in known:
            print(f"row {n} is already in build-results.csv; skipping")
            continue
        r["notes"] = "; ".join(x for x in (r["notes"], MANAGED[managed], note) if x) + f" (#{issue})"
        r["notes"] = r["notes"].lstrip()
        known.add(tuple(row[:-1]))
        new.append(to_line(r, header))
    if not new:
        fail("no new rows to add")

    with CSV_PATH.open("a", newline="") as f:
        f.write("\n".join(new) + "\n")
    print(f"Added {len(new)} row(s) from #{issue} to {CSV_PATH.name}")


if __name__ == "__main__":
    main()
