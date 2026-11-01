#!/bin/sh
# tier1.sh: run the kit's tier 1 tests (offline script tests, no agent) and time them (onboard fix, step 0).
#   sh scripts/tier1.sh [--time-limit <seconds>] [--report <file>] [-- <command...>]
# Default command: validate-kit.sh with KIT_SKIP_APP_TEMPLATE_TEST=1. The Maven and network app-template
# test is not tier 1 (design rev 6). `-- <command...>` runs that command instead (used by the harness
# self-test). --time-limit stops the run once it passes the limit and exits 124, naming the limit. With no
# --time-limit there is no limit: the number is set from the first measured run and goes in only after
# Sensei OKs it (N8A). --report writes one line to <file>:
#   tier1 PASS|FAIL|TIMEOUT <full kit commit> clean|dirty <seconds>s <time>
# Ctrl-C, TERM or HUP stops the whole run (exit 130, 143, 129). Refuses when any AGENTS_V0_* test switch
# is set. Kit-only file: it is not installed into projects.
# Known gap: without setsid (macOS) only the top process is stopped; fix before wiring into --update.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT/scripts/lib/tier1-vars.sh"
t1_guard_env || exit 2
limit=""; report=""
while [ $# -gt 0 ]; do
  case "$1" in
    --time-limit) [ $# -ge 2 ] || { echo 'tier1: --time-limit needs a number of seconds' >&2; exit 2; }; limit="$2"; shift 2 ;;
    --report) [ $# -ge 2 ] || { echo 'tier1: --report needs a file' >&2; exit 2; }; report="$2"; shift 2 ;;
    --) shift; break ;;
    *) printf 'usage: %s [--time-limit <seconds>] [--report <file>] [-- <command...>]\n' "$0" >&2; exit 2 ;;
  esac
done
if [ -n "$limit" ]; then
  case "$limit" in *[!0-9]*) echo 'tier1: --time-limit must be a whole number of seconds' >&2; exit 2 ;; esac
  [ "$limit" -ge 1 ] || { echo 'tier1: --time-limit must be at least 1' >&2; exit 2; }
fi
[ $# -gt 0 ] || set -- env KIT_SKIP_APP_TEMPLATE_TEST=1 sh "$KIT/scripts/validate-kit.sh"
commit="$(git -C "$KIT" rev-parse HEAD 2>/dev/null || echo unknown)"
tree=clean; [ -z "$(git -C "$KIT" status --porcelain 2>/dev/null)" ] || tree=dirty
flag="$(mktemp "${TMPDIR:-/tmp}/kit-tier1-timeout.XXXXXX")"   # empty; the watchdog writes "timeout" into it

pid=""; dog=""; grp=""
stop_all() { # stop_all <exit code>: stop the run's process group and the watchdog, then exit
  [ -z "$dog" ] || kill "$dog" 2>/dev/null || true
  [ -z "$grp" ] || { kill -TERM "$grp" 2>/dev/null || true; sleep 1; kill -KILL "$grp" 2>/dev/null || true; }
  rm -f "$flag"; exit "$1"
}
trap 'stop_all 130' INT
trap 'stop_all 143' TERM
trap 'stop_all 129' HUP

start="$(date +%s)"
if command -v setsid >/dev/null 2>&1; then setsid "$@" & pid=$!; grp="-$pid"
else "$@" & pid=$!; grp="$pid"; fi
if [ -n "$limit" ]; then
  ( sleep "$limit" & s=$!; trap 'kill "$s" 2>/dev/null; exit 0' TERM; wait "$s"
    echo timeout > "$flag"; kill -TERM "$grp" 2>/dev/null; sleep 5; kill -KILL "$grp" 2>/dev/null ) & dog=$!
fi
set +e; wait "$pid"; rc=$?; set -e
end="$(date +%s)"
[ -z "$dog" ] || { kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null; } || true
grp=""; dog=""
secs=$((end - start))
result=PASS
if [ -s "$flag" ]; then result=TIMEOUT; rc=124; secs="$limit"
elif [ "$rc" -ne 0 ]; then result=FAIL; fi
rm -f "$flag"
[ -z "$report" ] || printf 'tier1 %s %s %s %ss %s\n' "$result" "$commit" "$tree" "$secs" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$report"
short="$(printf '%.8s' "$commit")"
case "$result" in
  PASS) printf 'tier1: PASS in %ss (kit %s, %s tree%s)\n' "$secs" "$short" "$tree" "${limit:+, limit ${limit}s}" ;;
  TIMEOUT) printf 'tier1: TIMEOUT: stopped at the %ss tier 1 time limit (kit %s)\n' "$limit" "$short" >&2 ;;
  FAIL) printf 'tier1: FAIL (exit %s) after %ss (kit %s)\n' "$rc" "$secs" "$short" >&2 ;;
esac
exit "$rc"
