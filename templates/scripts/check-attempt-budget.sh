#!/bin/sh
# check-attempt-budget.sh — total failed attempts per phase (workflow-orchestration.mdc
# Phase attempt budget). The per-test limit does not bound a cascade of different failures.
#
# Usage: sh scripts/check-attempt-budget.sh <build-report.md> [<budget>]
# Counts command-result cards (table columns: Command, Exit, Attempt, Failing test, Location)
# whose Exit is not 0. The budget is the argument, else ATTEMPT_BUDGET, else the
# `Phase attempt budget` row of docs/project-profile.md, else 8.
#
# Exit 0 while an attempt remains; 1 when the budget is spent (record the phase as blocked).

set -eu

report="${1:-}"
budget="${2:-${ATTEMPT_BUDGET:-}}"
if [ -z "$report" ]; then
  printf 'usage: %s <build-report.md> [<budget>]\n' "$0" >&2
  exit 1
fi
if [ ! -f "$report" ]; then
  printf 'OK: no attempt cards yet (%s)\n' "$report"
  exit 0
fi

if [ -z "$budget" ] && [ -f docs/project-profile.md ]; then
  budget="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /Phase attempt budget/ {
      v = trim($3)
      if (v ~ /^[0-9]+$/) { print v; exit }
    }' docs/project-profile.md)"
fi
budget="${budget:-8}"
case "$budget" in
  '' | *[!0-9]*)
    printf 'FAIL: attempt budget is not a number: %s\n' "$budget" >&2
    exit 1
    ;;
esac

failed="$(awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /^[[:space:]]*\|/ {
    if (tolower(trim($2)) == "command" && tolower(trim($3)) == "exit") { in_cards = 1; next }
    if (!in_cards) next
    if ($0 ~ /---/) next
    code = trim($3)
    if (code ~ /^[0-9]+$/ && code != "0") n++
    next
  }
  { in_cards = 0 }
  END { print n + 0 }
' "$report")"

if [ "$failed" -ge "$budget" ]; then
  printf 'FAIL: attempt budget spent: %s failed attempts, budget %s (%s)\n' "$failed" "$budget" "$report" >&2
  exit 1
fi
printf 'OK: %s of %s failed attempts used (%s)\n' "$failed" "$budget" "$report"
