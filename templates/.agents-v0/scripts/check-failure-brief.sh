#!/bin/sh
# check-failure-brief.sh — before attempt three of the same failing test, require
# failure-brief.md (workflow-orchestration.mdc). Does not read build-output.txt.
#
# Usage:
#   sh .agents-v0/scripts/check-failure-brief.sh <feature> [<failing-test>]
#   sh .agents-v0/scripts/check-failure-brief.sh docs/agents-v0/build/<feature>/build-report.md [<failing-test>]
#
# Exit 0 when no second-red situation yet, or when the brief exists and names the test.
# Exit 1 when the report shows two failed cards for the same test and the brief is missing
# or does not mention that test / a file:line.

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

# Count failed cards per failing-test cell (column 5 when headers are Command|Exit|Attempt|Failing test|Location).
eval "$(REPORT="$report" TEST_FILTER="$test_name" python3 - <<'PY'
import os, re, sys
path = os.environ["REPORT"]
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
need = []
for name, n in counts.items():
    if n >= 2 and (not want or want == name or want in name):
        need.append(name)
print("NEED_COUNT=%d" % len(need))
print("NEED_TESTS=%s" % ",".join(need))
PY
)"

if [ "${NEED_COUNT:-0}" -eq 0 ]; then
  printf 'OK: no second-red failure requiring a brief (%s)\n' "$report"
  exit 0
fi

if [ ! -f "$brief" ]; then
  printf 'FAIL: %s missing after a second red for: %s\n' "$brief" "$NEED_TESTS" >&2
  printf 'Write the brief, launch debug-investigator, then attempt three. Do not read build-output.txt.\n' >&2
  exit 1
fi

brief_text="$(cat "$brief")"
missing=""
old_ifs=$IFS
IFS=,
for t in $NEED_TESTS; do
  IFS=$old_ifs
  case "$brief_text" in
    *"$t"*) ;;
    *)
      # Allow unnamed when brief has file:line evidence
      if [ "$t" = "(unnamed)" ] && printf '%s' "$brief_text" | grep -Eq '[A-Za-z0-9_./-]+:[0-9]+'; then
        :
      else
        missing="${missing} ${t}"
      fi
      ;;
  esac
done
IFS=$old_ifs

if [ -n "$missing" ]; then
  printf 'FAIL: %s does not name the failing test(s):%s\n' "$brief" "$missing" >&2
  exit 1
fi

if ! printf '%s' "$brief_text" | grep -Eq '[A-Za-z0-9_./-]+:[0-9]+'; then
  printf 'FAIL: %s must cite at least one file:line\n' "$brief" >&2
  exit 1
fi

printf 'OK: failure-brief present for second-red (%s)\n' "$NEED_TESTS"
