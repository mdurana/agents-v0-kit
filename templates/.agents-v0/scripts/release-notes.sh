#!/bin/sh
# release-notes.sh — release notes and changelog entries from the delivery artifacts.
#
# Usage: sh .agents-v0/scripts/release-notes.sh <milestone-manifest | requirements-artifact...>
#                                    [--version <x.y.z>] [--include-unreleased] [--insert <CHANGELOG.md>]
# For each story (the artifact column of a milestone manifest, or the artifacts named) it prints the
# user story, each acceptance criterion (AC-n) with its text, and the Release approval date and
# approver. A story without an Approved `release` row is left out (named on stderr) unless
# --include-unreleased. Output is Markdown under "## [<version>] - <date>", or "## [Unreleased]"
# without --version. --insert puts the entry under the first "## [Unreleased]" heading of the file
# (keep-a-changelog layout) and prints nothing else.
# The version is a decision for the release owner (semantic versioning: a breaking contract change
# is major, a feature minor, a fix patch). This script never tags and never edits a version file.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }
[ $# -ge 1 ] || { printf 'usage: %s <manifest | artifact...> [--version X] [--include-unreleased] [--insert CHANGELOG.md]\n' "$0" >&2; exit 1; }

ARGS="$(printf '%s\n' "$@")" python3 - <<'PY'
import datetime
import os
import re
import sys

args = os.environ["ARGS"].splitlines()
version, insert, include_all, sources = None, None, False, []
i = 0
while i < len(args):
    a = args[i]
    if a == "--version":
        version = args[i + 1]; i += 2
    elif a == "--insert":
        insert = args[i + 1]; i += 2
    elif a == "--include-unreleased":
        include_all = True; i += 1
    elif a.startswith("-"):
        print(f"FAIL: unknown option {a}", file=sys.stderr)
        raise SystemExit(1)
    else:
        sources.append(a); i += 1


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


artifacts = []
for src in sources:
    text = read(src)
    if text is None:
        print(f"FAIL: not found: {src}", file=sys.stderr)
        raise SystemExit(1)
    if re.search(r"^#+\s*Stories", text, re.M | re.I):
        in_table = False
        for line in text.splitlines():
            if re.match(r"^#+\s*Stories", line, re.I):
                in_table = True
                continue
            if in_table and re.match(r"^#+\s", line):
                break
            if in_table and line.strip().startswith("|"):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cells) >= 3 and cells[2].startswith("docs/") and "<" not in cells[2]:
                    artifacts.append((cells[0], cells[2]))
    else:
        artifacts.append((os.path.basename(src)[:-3], src))


def release_row(text):
    inside = False
    for line in text.splitlines():
        if re.match(r"^#+\s*delivery approvals", line, re.I):
            inside = True
            continue
        if inside and re.match(r"^#+\s", line):
            break
        if inside and line.strip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 5 and cells[0].lower() == "release":
                return cells
    return None


entries, skipped = [], []
for story_id, path in artifacts:
    text = read(path)
    if text is None:
        skipped.append(f"{story_id}: {path} not found")
        continue
    row = release_row(text)
    approved = bool(row and re.match(r"^(approved|approve|yes|pass)\b", row[3], re.I))
    if not approved and not include_all:
        skipped.append(f"{story_id}: no Approved release row in {path}")
        continue
    m = re.search(r"As an? .+?, I want .+?, so that .+?\.", text)
    block = [f"### {story_id}: {m.group(0) if m else os.path.basename(path)}"]
    seen = set()
    for line in text.splitlines():
        am = re.search(r"\bAC-(\d+)\b", line)
        if not am or am.group(0) in seen or re.match(r"^#+\s*delivery", line, re.I):
            continue
        seen.add(am.group(0))
        label = re.sub(r"[|*`]", " ", line.replace(am.group(0), "", 1))
        label = re.sub(r"^[\s:\-–—.)]+", "", re.sub(r"\s+", " ", label)).strip()
        block.append(f"- {am.group(0)}: {label}" if label else f"- {am.group(0)}")
    if row and approved:
        block.append(f"- Released {row[4] or 'on an unrecorded date'}, approved by {row[2] or 'an unrecorded approver'}")
    entries.append("\n".join(block))

date = datetime.date.today().isoformat()
heading = f"## [{version}] - {date}" if version else "## [Unreleased]"
note = "\n\n".join([heading] + entries) if entries else f"{heading}\n\n(no story with an Approved release row)"
for item in skipped:
    print(f"skipped {item}", file=sys.stderr)

if insert:
    current = read(insert)
    if current is None:
        print(f"FAIL: {insert} not found", file=sys.stderr)
        raise SystemExit(1)
    body = note.split("\n", 1)[1] if version is None and "\n" in note else note
    if re.search(r"^## \[Unreleased\]", current, re.M):
        text = body.strip("\n") if version is None else note
        new = re.sub(r"^## \[Unreleased\]\s*$", lambda _m: "## [Unreleased]\n\n" + text, current, count=1, flags=re.M)
    else:
        new = current.rstrip("\n") + "\n\n" + note + "\n"
    with open(insert, "w", encoding="utf-8") as handle:
        handle.write(new)
    print(f"inserted {len(entries)} story entr{'y' if len(entries) == 1 else 'ies'} into {insert}")
else:
    print(note)
PY
