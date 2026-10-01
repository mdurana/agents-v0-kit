#!/bin/sh
# check-approvals.sh — CI-side delivery approval check (workflow-orchestration.mdc).
# Verifies that the "Delivery approvals" record in a requirements artifact contains
# an explicit approval row for the given phase before merge. This is the
# "CI or repository controls" enforcement layer for phase approval stops.
#
# Usage: sh check-approvals.sh <requirements-artifact> <phase>
#   <requirements-artifact>  e.g. docs/requirements/my-feature.md
#   <phase>                  onboard | plan | intake | design | build | verify | release | maintain | milestone
#                            (plan: a milestone manifest's program-planning approval;
#                             onboard: docs/onboarding/report.md, the /onboard approval)
#
# Exit codes: 0 = approval recorded; 1 = missing artifact, section, or approval.
# This script checks workflow approvals only — gate evidence (tests, VAPT,
# review) is verified by the Verify phase and CI jobs, not here.

set -eu

art="${1:-}"
phase="${2:-}"

if [ -z "$art" ] || [ -z "$phase" ]; then
  printf 'usage: %s <requirements-artifact> <phase>\n' "$0" >&2
  exit 1
fi
case "$phase" in
  onboard|plan|intake|design|build|verify|release|maintain|milestone) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected onboard|plan|intake|design|build|verify|release|maintain|milestone)\n' "$phase" >&2
    exit 1
    ;;
esac

[ -f "$art" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$art" >&2; exit 1; }

# Extract the "Delivery approvals" section (heading to next heading).
section="$(awk '
  /^#+[[:space:]]*[Dd]elivery [Aa]pprovals/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$art")"

[ -n "$section" ] || { printf 'FAIL: %s has no "Delivery approvals" section\n' "$art" >&2; exit 1; }

# Find the row for the phase; it must exist and record an explicit approval
# (a real user decision — never inferred).
row="$(printf '%s' "$section" | grep -i "|[[:space:]]*${phase}[[:space:]]*|" || true)"
[ -n "$row" ] || { printf 'FAIL: no approval row for phase "%s" in %s\n' "$phase" "$art" >&2; exit 1; }

# The Decision column is the 4th table field (awk fields: 1 empty, 2 Phase,
# 3 Artifacts, 4 Approver, 5 Decision). Require a leading positive token so
# negations such as "Not approved" or "Rejected" fail.
decision="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print tolower($5)}' | head -n1)"
printf '%s' "$decision" | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)' || {
  printf 'FAIL: phase "%s" is recorded in %s but has no explicit approval (decision: "%s")\n' "$phase" "$art" "$decision" >&2
  exit 1
}

printf 'OK: phase "%s" approval recorded in %s\n' "$phase" "$art"
