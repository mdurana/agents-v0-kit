#!/bin/sh
# check-coverage-ratchet.sh — fail expired or unapproved coverage_ratchet rows.
#
# Usage: sh .agents-v0/ci/check-coverage-ratchet.sh [docs/agents-v0/project-profile.md]
# Optional: LINE_COVERAGE_PCT (or legacy JACOCO_LINE_PCT) and COVERAGE_SCOPE compare a measured
# line % to the interim minimum of the matching active row. The pack's coverage gate stays
# authoritative for the org minimum; this script only enforces the recorded brownfield exception.

set -eu

profile="${1:-docs/agents-v0/project-profile.md}"
if [ ! -f "$profile" ]; then
  printf 'OK: no project profile — coverage ratchet skipped\n'
  exit 0
fi

PROFILE="$profile" python3 - <<'PY'
import datetime
import os
import re
import sys

path = os.environ["PROFILE"]
text = open(path, encoding="utf-8").read()
section = re.search(r"^### coverage_ratchet\b.*?(?=^## |\Z)", text, re.M | re.S)
if not section:
    print("OK: no coverage_ratchet section")
    raise SystemExit(0)

today = datetime.date.today()
pct = (os.environ.get("LINE_COVERAGE_PCT") or os.environ.get("JACOCO_LINE_PCT") or "").strip()
want_scope = os.environ.get("COVERAGE_SCOPE", "").strip()
fail = False
seen = False

for line in section.group(0).splitlines():
    if not line.strip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4:
        continue
    scope = cells[0]
    if not scope or scope.lower() == "scope" or set(scope) <= set("-: "):
        continue
    interim, approver, remove = cells[1], cells[2], cells[3]
    if not interim and not approver and not remove:
        continue
    seen = True
    if not approver:
        print(f"FAIL: coverage_ratchet scope {scope!r} has no approver", file=sys.stderr)
        fail = True
        continue
    try:
        end = datetime.date.fromisoformat(remove)
    except ValueError:
        print(f"FAIL: coverage_ratchet scope {scope!r} remove-by must be YYYY-MM-DD", file=sys.stderr)
        fail = True
        continue
    if end < today:
        print(f"FAIL: coverage_ratchet scope {scope!r} expired on {remove}", file=sys.stderr)
        fail = True
        continue
    if pct and (not want_scope or want_scope == scope):
        try:
            if float(pct) + 1e-9 < float(interim):
                print(
                    f"FAIL: coverage {pct} is below interim {interim} for scope {scope!r}",
                    file=sys.stderr,
                )
                fail = True
                continue
        except ValueError:
            print("FAIL: LINE_COVERAGE_PCT / JACOCO_LINE_PCT or interim minimum is not numeric", file=sys.stderr)
            fail = True
            continue
    print(f"OK: coverage_ratchet {scope} interim {interim} until {remove}")

if fail:
    raise SystemExit(1)
if not seen:
    print("OK: no active coverage_ratchet rows")
PY
