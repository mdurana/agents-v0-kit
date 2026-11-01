#!/bin/sh
# tier1.sh: run the kit's tier 1 tests (offline script tests, no agent) and time them (onboard fix, step 0).
#   sh scripts/tier1.sh [--time-limit <seconds>] [--report <file>] [-- <command...>]
# Default command: validate-kit.sh with KIT_SKIP_APP_TEMPLATE_TEST=1. The Maven and network app-template
# test is not tier 1 (design rev 6). `-- <command...>` runs that command instead (used by the harness
# self-test). --time-limit stops the run once it passes the limit and exits 124, naming the limit. With no
# --time-limit there is no limit: the number is set from the first measured run and goes in only after
# Sensei OKs it (N8A). --report writes `tier1 PASS|FAIL|TIMEOUT <kit commit> <seconds>s <time>` to <file>.
# Refuses when any AGENTS_V0_* test switch is set. Kit-only file: it is not installed into projects.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
limit=""; report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --time-limit) limit="${2:-}"; shift 2 || { echo 'tier1: --time-limit needs a number of seconds' >&2; exit 2; } ;;
    --report) report="${2:-}"; shift 2 || { echo 'tier1: --report needs a file' >&2; exit 2; } ;;
    --) shift; break ;;
    *) printf 'usage: %s [--time-limit <seconds>] [--report <file>] [-- <command...>]\n' "$0" >&2; exit 2 ;;
  esac
done
case "$limit" in ""|*[!0-9]*) [ -z "$limit" ] || { echo 'tier1: --time-limit must be a whole number of seconds' >&2; exit 2; } ;; esac
[ "$limit" != 0 ] || { echo 'tier1: --time-limit must be at least 1' >&2; exit 2; }
for v in AGENTS_V0_SKIP_BRANCH_GUARD AGENTS_V0_SKIP_COMMIT_CHECK AGENTS_V0_COMMIT_CHECK_IGNORE AGENTS_V0_NOW AGENTS_V0_TZ AGENTS_V0_TRACE_MODE AGENTS_V0_TRACE_NO_WRITE; do
  if eval "[ -n \"\${$v+x}\" ]"; then printf 'tier1: refusing to run: %s is set in the environment\n' "$v" >&2; exit 2; fi
done
[ $# -gt 0 ] || set -- env KIT_SKIP_APP_TEMPLATE_TEST=1 sh "$KIT/scripts/validate-kit.sh"
commit="$(git -C "$KIT" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
start="$(date +%s)"
# Run in its own process group so a timeout stops every child, then wait with a watchdog.
set +e
if [ -n "$limit" ]; then
  if command -v setsid >/dev/null 2>&1; then setsid "$@" & pid=$!; grp="-$pid"
  else "$@" & pid=$!; grp="$pid"; fi   # no setsid (macOS): stop the top process; its children see the pipe close
  ( sleep "$limit" & s=$!; trap 'kill "$s" 2>/dev/null; exit 0' TERM; wait "$s"
    kill -TERM "$grp" 2>/dev/null; sleep 5; kill -KILL "$grp" 2>/dev/null ) & dog=$!
  wait "$pid"; rc=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
else
  "$@"; rc=$?
fi
set -e
secs=$(( $(date +%s) - start ))
result=PASS
if [ -n "$limit" ] && [ "$secs" -ge "$limit" ] && [ "$rc" -ne 0 ]; then result=TIMEOUT; rc=124
elif [ "$rc" -ne 0 ]; then result=FAIL; fi
[ -z "$report" ] || printf 'tier1 %s %s %ss %s\n' "$result" "$commit" "$secs" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$report"
case "$result" in
  PASS) printf 'tier1: PASS in %ss (kit %s%s)\n' "$secs" "$commit" "${limit:+, limit ${limit}s}" ;;
  TIMEOUT) printf 'tier1: TIMEOUT: stopped after %ss, past the %ss tier 1 time limit (kit %s)\n' "$secs" "$limit" "$commit" >&2 ;;
  FAIL) printf 'tier1: FAIL (exit %s) after %ss (kit %s)\n' "$rc" "$secs" "$commit" >&2 ;;
esac
exit "$rc"
