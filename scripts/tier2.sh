#!/bin/sh
# tier2.sh: run the kit's tier 2 tests, the slower offline script suites moved out of tier 1 (no agent).
#   sh scripts/tier2.sh [--report <file>]
# Tier 1 limit C (Sensei, 2026-11-02 08:44 Manila): "Tier 1 limit C stands: keep 600s, keep the hook-policy,
# state guard and agy hook cases in tier 1, move the rest of test-hooks.sh to tier 2". T2_SUITES is the one
# list of tier 2 suites; validate-kit.sh checks that every suite on it exists and that it does not run them
# itself. Each suite runs with sh, in order; every suite runs even after a failure, and each failing suite is
# named (tier2: FAIL: <suite> (exit N)). Exit 0 only when all pass, else 1. No time limit. --report writes:
#   tier2 PASS|FAIL <full kit commit> clean|dirty <seconds>s <time>
# Refuses when any AGENTS_V0_* test switch is set. Kit-only file: it is not installed into projects.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-vars.sh"
T2_SUITES="scripts/test-hooks.sh"
t1_guard_env 2>/dev/null || { t1_guard_env 2>&1 | sed 's/^tier1:/tier2:/' >&2; exit 2; }
report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --report) [ $# -ge 2 ] || { echo 'tier2: --report needs a file' >&2; exit 2; }; report="$2"; shift 2 ;;
    *) printf 'usage: %s [--report <file>]\n' "$0" >&2; exit 2 ;;
  esac
done
commit="$(git -C "$KIT" rev-parse HEAD 2>/dev/null || echo unknown)"
tree=clean; [ -z "$(git -C "$KIT" status --porcelain 2>/dev/null)" ] || tree=dirty
start="$(date +%s)"; failed=""
for s in $T2_SUITES; do
  printf 'tier2: running %s\n' "$s"
  set +e; ( cd "$KIT" && sh "$s" ); rc=$?; set -e
  if [ "$rc" -ne 0 ]; then printf 'tier2: FAIL: %s (exit %s)\n' "$s" "$rc" >&2; failed="$failed $s"; fi
done
secs=$(( $(date +%s) - start ))
result=PASS; [ -z "$failed" ] || result=FAIL
[ -z "$report" ] || printf 'tier2 %s %s %s %ss %s\n' "$result" "$commit" "$tree" "$secs" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$report"
short="$(printf '%.8s' "$commit")"
if [ "$result" = PASS ]; then printf 'tier2: PASS in %ss (kit %s, %s tree; %s)\n' "$secs" "$short" "$tree" "$T2_SUITES"; exit 0; fi
printf 'tier2: FAIL after %ss (kit %s): failed:%s\n' "$secs" "$short" "$failed" >&2
exit 1
