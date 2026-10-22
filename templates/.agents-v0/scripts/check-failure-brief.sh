#!/bin/sh
# check-failure-brief.sh — before attempt three of the same failing test, require
# failure-brief.md (workflow-orchestration.mdc). Does not read build-output.txt.
#
# Usage:
#   sh .agents-v0/scripts/check-failure-brief.sh <feature> [<failing-test>]
#   sh .agents-v0/scripts/check-failure-brief.sh docs/agents-v0/build/<feature>/build-report.md [<failing-test>]
#
# Exit 0 when no second-red situation yet, or when the brief exists and names the test.
# Exit 1 when the report shows two failed cards for the same test and the brief is missing,
# does not mention that test / a file:line, or lacks a helper:, outputs:, return: or ask: field.

set -eu

arg="${1:-}"
test_name="${2:-}"
if [ -z "$arg" ]; then
  printf 'usage: %s <feature|build-report.md> [<failing-test>]\n' "$0" >&2
  exit 1
fi

if [ -f "$arg" ]; then
  report="$arg"
  feature="$(basename "$(dirname "$arg")")"
else
  feature="$arg"
  report="docs/agents-v0/build/${feature}/build-report.md"
fi
brief="docs/agents-v0/build/${feature}/failure-brief.md"

if [ ! -f "$report" ]; then
  printf 'OK: no build report yet (%s)\n' "$report"
  exit 0
fi

# Count failed cards per failing-test cell (column 5 when headers are Command|Exit|Attempt|Failing test|Location)
# and verify the failure brief in Python so spaces, commas, and shell characters in test names are safe.
REPORT="$report" BRIEF="$brief" TEST_FILTER="$test_name" python3 - <<'PY'
import os, re, sys

path = os.environ["REPORT"]
brief_path = os.environ["BRIEF"]
want = os.environ.get("TEST_FILTER", "").strip()
text = open(path, encoding="utf-8", errors="replace").read()
counts = {}
in_cards = False
for line in text.splitlines():
    if not line.strip().startswith("|"):
        in_cards = False
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4:
        continue
    low = [c.lower() for c in cells]
    if low[0] == "command" and low[1] == "exit":
        in_cards = True
        continue
    if not in_cards or set(line.replace("|", "").strip()) <= set("-: "):
        continue
    exit_code = cells[1]
    if not exit_code.isdigit() or exit_code == "0":
        continue
    failing = cells[3] if len(cells) > 3 else ""
    if not failing or failing in ("—", "-", "n/a", "N/A"):
        failing = "(unnamed)"
    counts[failing] = counts.get(failing, 0) + 1

need = [name for name, n in counts.items() if n >= 2 and (not want or want == name or want in name)]
if not need:
    print(f"OK: no second-red failure requiring a brief ({path})")
    raise SystemExit(0)

joined = ",".join(need)
if not os.path.isfile(brief_path):
    print(f"FAIL: {brief_path} missing after a second red for: {joined}", file=sys.stderr)
    print("Write the brief, launch debug-investigator, then attempt three. Do not read build-output.txt.", file=sys.stderr)
    raise SystemExit(1)

brief_text = open(brief_path, encoding="utf-8", errors="replace").read()
has_file_line = bool(re.search(r"[A-Za-z0-9_./-]+:[0-9]+", brief_text))
missing = []
for t in need:
    if t in brief_text:
        continue
    if t == "(unnamed)" and has_file_line:
        continue
    missing.append(t)

if missing:
    print(f"FAIL: {brief_path} does not name the failing test(s): {' '.join(missing)}", file=sys.stderr)
    raise SystemExit(1)

if not has_file_line:
    print(f"FAIL: {brief_path} must cite at least one file:line", file=sys.stderr)
    raise SystemExit(1)

# v4 brief format (v0-build.md step 5): helper:, outputs:, return:, ask: are required fields.
absent = [k for k in ("helper", "outputs", "return", "ask")
          if not re.search(rf"^\s*(?:[-*]\s*)?(?:\*\*)?{k}:(?:\*\*)?", brief_text, re.M | re.I)]
if absent:
    print(f"FAIL: {brief_path} lacks required field(s): {', '.join(a + ':' for a in absent)} (v0-build.md step 5)", file=sys.stderr)
    raise SystemExit(1)

print(f"OK: failure-brief present for second-red ({joined})")
PY
