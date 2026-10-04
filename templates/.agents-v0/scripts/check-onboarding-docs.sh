#!/bin/sh
# check-onboarding-docs.sh — the onboarding documents cite real code (onboard-discovery).
#
# Usage: sh .agents-v0/scripts/check-onboarding-docs.sh [<path>...]
# With no argument it checks docs/agents-v0/onboarding/ (the report must exist), docs/agents-v0/architecture.md,
# docs/agents-v0/network.md, docs/agents-v0/design/system/context-map.md, docs/agents-v0/diagrams/, and
# docs/agents-v0/adr/0000-inherited-decisions.md, whichever exist.
#
# A citation is a backticked `path/to/File.ext:LINE` or `path/to/File.ext:START-END`.
# Fails when:
#   - a cited file does not exist, or a cited line is past the end of the file;
#   - a TEMPLATE: marker is still in a document (a sample row was never replaced);
#   - a document under docs/agents-v0/onboarding/ (not _*.template.md) has no `commit: <sha>` line;
#   - docs/agents-v0/onboarding/report.md is missing in the default run;
#   - UNVERIFIED markers exceed MAX_UNVERIFIED (unset: counted and reported only).
# An UNVERIFIED marker is an honest unknown; it should also appear in the report's open questions.

set -eu

command -v python3 >/dev/null 2>&1 || { printf 'FAIL: python3 is required\n' >&2; exit 1; }

if [ "$#" -eq 0 ]; then
  [ -f docs/agents-v0/onboarding/report.md ] || { printf 'FAIL: docs/agents-v0/onboarding/report.md is missing (copy docs/agents-v0/onboarding/_report.template.md)\n' >&2; exit 1; }
  set -- docs/agents-v0/onboarding docs/agents-v0/architecture.md docs/agents-v0/network.md docs/agents-v0/design/system/context-map.md docs/agents-v0/diagrams docs/agents-v0/adr/0000-inherited-decisions.md
  present=""
  for path in "$@"; do
    if [ -e "$path" ]; then
      present="$present $path"
    fi
  done
  # shellcheck disable=SC2086
  set -- $present
else
  for path in "$@"; do
    if [ ! -e "$path" ]; then
      printf 'FAIL: %s is missing\n' "$path" >&2
      exit 1
    fi
  done
fi

CHECK_PATHS="$(printf '%s\n' "$@")" python3 - <<'PY'
import os
import re
import sys

EXT = ("java|kt|ts|tsx|js|jsx|svelte|py|go|xml|yml|yaml|json|properties|sql|gradle|kts|md|sh|html|css|toml|tf|conf")
CITE = re.compile(r"`([A-Za-z0-9_./@+\-]+\.(?:%s)):(\d+)(?:-(\d+))?`" % EXT)
failures, unverified, checked, cites = [], 0, 0, 0
line_counts = {}


def line_count(path):
    if path not in line_counts:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                line_counts[path] = sum(1 for _ in handle)
        except OSError:
            line_counts[path] = None
    return line_counts[path]


docs = []
for raw in os.environ["CHECK_PATHS"].splitlines():
    if not raw:
        continue
    if os.path.isdir(raw):
        for dirpath, _dirs, names in os.walk(raw):
            for name in sorted(names):
                if name.endswith(".md") and not (name.startswith("_") and name.endswith(".template.md")):
                    docs.append(os.path.join(dirpath, name))
    elif os.path.isfile(raw):
        docs.append(raw)

for doc in sorted(set(docs)):
    checked += 1
    with open(doc, encoding="utf-8", errors="replace") as handle:
        body = handle.read()
    if "TEMPLATE:" in body:
        failures.append(f"{doc}: a TEMPLATE: marker is still present (replace or delete the sample row)")
    unverified += len(re.findall(r"\bUNVERIFIED\b", body))
    if doc.replace(os.sep, "/").startswith("docs/agents-v0/onboarding/") and not re.search(r"^commit:\s*[0-9a-f]{7,40}\b", body, re.M):
        failures.append(f"{doc}: no `commit: <sha>` line (the commit this document describes)")
    for m in CITE.finditer(body):
        cites += 1
        path, start = m.group(1), int(m.group(2))
        end = int(m.group(3)) if m.group(3) else start
        count = line_count(path)
        if count is None:
            failures.append(f"{doc}: cited file does not exist: {path}")
        elif start < 1 or end < start or end > count:
            failures.append(f"{doc}: {path}:{m.group(2)}{('-' + m.group(3)) if m.group(3) else ''} is outside the file ({count} lines)")

limit = os.environ.get("MAX_UNVERIFIED")
if limit and limit.isdigit() and unverified > int(limit):
    failures.append(f"{unverified} UNVERIFIED markers exceed MAX_UNVERIFIED={limit}")

print(f"checked {checked} document(s), {cites} citation(s), {unverified} UNVERIFIED marker(s)")
if failures:
    for item in failures:
        print(f"FAIL: {item}", file=sys.stderr)
    raise SystemExit(1)
print("OK: onboarding documents cite real code")
PY
