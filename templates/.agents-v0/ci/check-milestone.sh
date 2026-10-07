#!/bin/sh
# check-milestone.sh — milestone go/no-go aggregation (workflow-orchestration.mdc).
# Given a milestone manifest (docs/agents-v0/milestones/<milestone>.md), verifies that every
# user story with a concrete feature-artifact path exists, records the phase
# approval in its canonical Delivery approvals table, and — for build/verify —
# that the recorded evidence paths exist. Rows with dynamic/placeholder paths
# (<...>) or no path are skipped: a milestone go/no-go passes only when every
# story row carries a concrete, approved artifact.
#
# A P4 manifest that names docs/agents-v0/design/system/slo-evidence.md accepts a waiver by default;
# SLO_ALLOW_WAIVERS=0 requires every row to be measured.
# Story order is checked too: a build-approved story fails when a story named in its
# Dependency column has no verify approval (MILESTONE_ORDER=0 disables that check).
#
# Usage: sh check-milestone.sh <manifest> <phase>
#   <manifest>  e.g. docs/agents-v0/milestones/p2-mvp-core-features.md
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

roadmap="$(sed -n 's/^[[:space:]]*Roadmap:[[:space:]]*//p' "$manifest" | head -n 1 | sed 's/[[:space:]]*$//')"
if [ -n "$roadmap" ]; then
  sh "$here/check-approvals.sh" "$roadmap" roadmap || exit 1
fi
arch="$(sed -n 's/^[[:space:]]*Architecture:[[:space:]]*//p' "$manifest" | head -n 1 | sed 's/[[:space:]]*$//')"
if [ -n "$arch" ]; then
  sh "$here/check-approvals.sh" "$arch" architecture || exit 1
  sh "$here/check-architecture-pack.sh" --approved "$arch" || exit 1
fi

# Stories table: | Story ID | User story | Feature artifact | Status | Dependency |
# Surface and Size may follow Dependency. They are not read here.
# A "Roadmap:" line names a file that must carry an Approved roadmap row.
# An "Architecture:" line names a file that must carry an Approved architecture row and a
# complete pack (check-architecture-pack.sh --approved).
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

# Story order: a story with a build approval needs a verify approval on every story
# it names in the Dependency column. A dependency that is a manifest path (*.md)
# instead needs an Approved milestone row on that file. Other tokens that are not
# story IDs of this manifest (milestone names such as P1, or a dash) are prose and
# are skipped.
# MILESTONE_ORDER=0 turns the check off.
has_approval() {
  sh "$here/check-approvals.sh" "$1" "$2" >/dev/null 2>&1
}

check_story_order() {
  [ "${MILESTONE_ORDER:-1}" != "0" ] || return 0
  rows="$(printf '%s\n' "$section" | awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /---/ { next }
    /Story [Ii][Dd]/ { next }
    /^[[:space:]]*\|/ {
      id = trim($2); art = trim($4); dep = trim($6)
      if (id != "") printf "%s^%s^%s\n", id, art, dep
    }')"
  ids="$(printf '%s\n' "$rows" | awk -F'^' '{ print $1 }')"
  order_fail=0
  while IFS='^' read -r sid sart sdep; do
    [ -n "$sid" ] || continue
    case "$sart" in ''|*'<'*|*'>'*) continue ;; esac
    [ -f "$sart" ] || continue
    has_approval "$sart" build || continue
    for dep in $(printf '%s' "$sdep" | tr ',;' '  '); do
      case "$dep" in
        *.md)
          if [ ! -f "$dep" ] || ! has_approval "$dep" milestone; then
            printf 'FAIL: story %s is build-approved but dependency manifest %s has no approved milestone row\n' "$sid" "$dep" >&2
            order_fail=1
          fi
          continue
          ;;
      esac
      printf '%s\n' "$ids" | grep -Fxq "$dep" || continue
      dart="$(printf '%s\n' "$rows" | awk -F'^' -v d="$dep" '$1 == d { print $2; exit }')"
      case "$dart" in ''|*'<'*|*'>'*)
        printf 'FAIL: story %s is build-approved but its dependency %s has no concrete artifact\n' "$sid" "$dep" >&2
        order_fail=1
        continue
        ;;
      esac
      if [ ! -f "$dart" ] || ! has_approval "$dart" verify; then
        printf 'FAIL: story %s is build-approved but its dependency %s has no verify approval (%s)\n' "$sid" "$dep" "$dart" >&2
        order_fail=1
      fi
    done
  done <<EOF
$rows
EOF
  return "$order_fail"
}

if ! check_story_order; then
  missing=1
fi

check_slo_evidence() {
  grep -Fq 'docs/agents-v0/design/system/slo-evidence.md' "$manifest" || return 0
  case "$phase" in
    verify|release) ;;
    *) return 0 ;;
  esac
  ev="docs/agents-v0/design/system/slo-evidence.md"
  if [ ! -f "$ev" ]; then
    printf 'FAIL: SLO evidence file missing: %s (slo-evidence skill)\n' "$ev" >&2
    return 1
  fi
  slo_fail=0
  # awk prints one result line per evidence row:
  # ok, bad-kind, bad-fields, bad-path, missing-file. Measured files are
  # checked in the shell so the test does not depend on awk's system().
  parsed="$(awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[[:space:]]*\|/ {
      if ($0 ~ /---/) next
      surface = trim($2)
      if (surface == "" || surface == "Surface") next
      kind = tolower(trim($3))
      cmd = trim($4)
      out = trim($5)
      date = trim($6)
      n++
      if (kind != "measured" && kind != "waiver") {
        printf "bad-kind\t%s\t%s\n", surface, kind
        next
      }
      if (cmd == "" || out == "" || date !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
        printf "bad-fields\t%s\n", surface
        next
      }
      if (kind == "measured" && (out ~ /(^|\/)\.\.(\/|$)/ || out ~ /^\//)) {
        printf "bad-path\t%s\t%s\n", surface, out
        next
      }
      printf "%s\t%s\t%s\n", kind, surface, out
    }
    END { if (n == 0) print "empty" }
  ' "$ev")"
  case "$parsed" in
    empty|"")
      printf 'FAIL: %s has no SLO evidence rows\n' "$ev" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$parsed" | while IFS= read -r line; do
    kind="${line%%	*}"
    rest="${line#*	}"
    surface="${rest%%	*}"
    out="${rest#*	}"
    case "$kind" in
      bad-kind)
        printf 'FAIL: SLO row "%s" kind must be measured or waiver (got "%s")\n' "$surface" "$out" >&2
        echo fail >>"$slo_mark"
        ;;
      bad-fields)
        printf 'FAIL: SLO row "%s" needs a command or reason, an output or approver, and a YYYY-MM-DD date\n' "$surface" >&2
        echo fail >>"$slo_mark"
        ;;
      bad-path)
        printf 'FAIL: SLO output path must be a repo-relative file without "..": %s\n' "$out" >&2
        echo fail >>"$slo_mark"
        ;;
      measured)
        if [ ! -f "$out" ]; then
          printf 'FAIL: SLO output file missing for "%s": %s\n' "$surface" "$out" >&2
          echo fail >>"$slo_mark"
        fi
        ;;
      waiver)
        if [ "${SLO_ALLOW_WAIVERS:-1}" = "0" ]; then
          printf 'FAIL: SLO row "%s" is a waiver and SLO_ALLOW_WAIVERS=0 requires a measurement\n' "$surface" >&2
          echo fail >>"$slo_mark"
        fi
        ;;
    esac
  done
  nfr="docs/agents-v0/design/system/nfr-slo.md"
  if [ -f "$nfr" ]; then
    awk -F'|' '
      function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
      /^[[:space:]]*\|/ {
        if ($0 ~ /---/) next
        name = trim($2)
        if (name == "" || name == "Surface" || name == "Tier") next
        rest = ""
        for (i = 3; i <= NF; i++) rest = rest $i
        gsub(/[ \t|]/, "", rest)
        if (rest != "") print name
      }
    ' "$nfr" | while IFS= read -r name; do
      [ -n "$name" ] || continue
      if ! printf '%s\n' "$parsed" | awk -F'	' -v n="$name" '$2 == n { found = 1 } END { exit !found }'; then
        printf 'FAIL: filled NFR/SLO row "%s" has no row in %s\n' "$name" "$ev" >&2
        echo fail >>"$slo_mark"
      fi
    done
  fi
  if [ -f "$slo_mark" ]; then
    rm -f "$slo_mark"
    slo_fail=1
  fi
  return "$slo_fail"
}

slo_mark="$(mktemp)"
rm -f "$slo_mark"
if ! check_slo_evidence; then
  missing=1
fi
rm -f "$slo_mark"

if [ "$checked" -eq 0 ] && [ "$missing" -eq 0 ]; then
  printf 'FAIL: no concrete story artifact paths in %s (all rows are dynamic or empty)\n' "$manifest" >&2
  exit 1
fi
if [ "$missing" -eq 1 ]; then
  exit 1
fi
printf 'OK: %s story artifact(s) passed the "%s" gate for %s\n' "$checked" "$phase" "$manifest"