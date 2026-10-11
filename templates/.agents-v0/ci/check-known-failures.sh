#!/bin/sh
# check-known-failures.sh — fail if verify log shows failures beyond documented known_failures.
#
# Usage: sh .agents-v0/ci/check-known-failures.sh [--require-failures] <verify-log-file>
# Parses Surefire/JUnit failure counts; compares to docs/agents-v0/project-profile.md known_failures table when present.
# Run it from the repository root (the profile path is relative).
#
# --require-failures  use after a verify command that exited non-zero: a log with no test failure
#                     is a compile or plugin error, not a known failure, so it fails here.
#
# Exit 0 when no failures or documented allow-list matches; 1 otherwise.

set -eu
require=0
if [ "${1:-}" = "--require-failures" ]; then
  require=1
  shift
fi
log="${1:-}"
profile="docs/agents-v0/project-profile.md"
[ -f "$log" ] || { printf 'FAIL: verify log not found: %s\n' "$log" >&2; exit 1; }

fail_line="$(grep -E 'Tests run:.*Failures: [1-9]' "$log" 2>/dev/null | tail -n1 || true)"
error_line="$(grep -E 'Tests run:.*Errors: [1-9]' "$log" 2>/dev/null | tail -n1 || true)"
if [ -z "$fail_line" ] && [ -z "$error_line" ]; then
  if [ "$require" = 1 ]; then
    printf 'FAIL: verify exited non-zero and the log shows no test failure (build or plugin error, not a known failure)\n' >&2
    exit 1
  fi
  printf 'OK: no test failures detected in log\n'
  exit 0
fi

fail_count="$(printf '%s' "$fail_line" | sed -n 's/.*Failures: \([0-9]*\).*/\1/p')"
error_count="$(printf '%s' "$error_line" | sed -n 's/.*Errors: \([0-9]*\).*/\1/p')"
fail_count="${fail_count:-0}"
error_count="${error_count:-0}"
total=$((fail_count + error_count))

if [ -f "$profile" ] && grep -q 'known_failures' "$profile"; then
  allowed="$(awk '/known_failures/{f=1} f && /^[[:space:]]*\|/{print}' "$profile" 2>/dev/null | grep -E '\|[[:space:]]*[0-9]+[[:space:]]*\|' | awk -F'|' '{gsub(/ /,"",$2); if($2+0>0) print $2+0}' | head -n1 || true)"
  if [ -n "$allowed" ] && [ "$total" -le "$allowed" ]; then
    printf 'OK: failures (%s) within documented known_failures budget (%s)\n' "$total" "$allowed"
    exit 0
  fi
  printf 'WARN: failures (%s) exceed known_failures budget (%s) — review required\n' "$total" "${allowed:-0}" >&2
  exit 1
fi

printf 'FAIL: test failures in log (failures=%s errors=%s) and no known_failures table in %s\n' "$fail_count" "$error_count" "$profile" >&2
printf '%s\n' "$fail_line" "$error_line" >&2
exit 1
