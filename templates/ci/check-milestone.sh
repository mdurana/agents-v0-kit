#!/bin/sh
# check-milestone.sh — milestone go/no-go aggregation (workflow-orchestration.mdc).
# Given a milestone manifest (docs/milestones/<milestone>.md), verifies that every
# user story with a concrete feature-artifact path exists, records the phase
# approval in its canonical Delivery approvals table, and — for build/verify —
# that the recorded evidence paths exist. Rows with dynamic/placeholder paths
# (<...>) or no path are skipped: a milestone go/no-go passes only when every
# story row carries a concrete, approved artifact.
#
# Usage: sh check-milestone.sh <manifest> <phase>
#   <manifest>  e.g. docs/milestones/p2-mvp-core-features.md
#   <phase>     intake | design | build | verify | release
#   The milestone-level decision row itself is checked by
#   ci/check-approvals.sh <manifest> milestone.
#
# Exit codes: 0 = every concrete story artifact passed the phase gate; 1 = missing
# manifest, no Stories section, story artifact missing/unapproved, evidence
# missing, or no concrete story rows. Story status is prose; this script checks
# recorded evidence only.

set -eu

manifest="${1:-}"
phase="${2:-}"
if [ -z "$manifest" ] || [ -z "$phase" ]; then
  printf 'usage: %s <manifest> <phase>\n' "$0" >&2
  exit 1
fi
case "$phase" in
  intake|design|build|verify|release) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected intake|design|build|verify|release)\n' "$phase" >&2
    exit 1
    ;;
esac
[ -f "$manifest" ] || { printf 'FAIL: milestone manifest not found: %s\n' "$manifest" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"

# Stories table: | Story ID | User story | Feature artifact | Status | Dependency |
section="$(awk '
  /^#+[[:space:]]*[Ss]tories/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$manifest")"
[ -n "$section" ] || { printf 'FAIL: %s has no "Stories" section\n' "$manifest" >&2; exit 1; }

artifacts="$(printf '%s\n' "$section" | awk -F'|' '
  /---/ { next }
  /Story [Ii][Dd]/ { next }
  /^[[:space:]]*\|/ {
    a = $4
    gsub(/^[ \t]+|[ \t]+$/, "", a)
    if (a != "") print a
  }')"

missing=0
checked=0
for a in $artifacts; do
  case "$a" in
    *'<'*|*'>'*)
      printf 'FAIL: milestone story row still has placeholder artifact path: %s\n' "$a" >&2
      missing=1
      continue
      ;;
  esac
  if [ ! -f "$a" ]; then
    printf 'FAIL: milestone story artifact missing on disk: %s\n' "$a" >&2
    missing=1
    continue
  fi
  if ! sh "$here/check-approvals.sh" "$a" "$phase"; then
    missing=1
    continue
  fi
  case "$phase" in
    build|verify)
      sh "$here/check-evidence.sh" "$a" "$phase" || missing=1
      ;;
  esac
  checked=$((checked + 1))
done

if [ "$checked" -eq 0 ] && [ "$missing" -eq 0 ]; then
  printf 'FAIL: no concrete story artifact paths in %s (all rows are dynamic or empty)\n' "$manifest" >&2
  exit 1
fi
if [ "$missing" -eq 1 ]; then
  exit 1
fi
printf 'OK: %s story artifact(s) passed the "%s" gate for %s\n' "$checked" "$phase" "$manifest"