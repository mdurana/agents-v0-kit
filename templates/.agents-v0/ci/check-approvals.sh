#!/bin/sh
# check-approvals.sh — CI-side delivery approval check (workflow-orchestration.mdc).
# Verifies that the "Delivery approvals" record in a requirements artifact contains
# an explicit approval row for the given phase before merge. This is the
# "CI or repository controls" enforcement layer for phase approval stops.
#
# Usage: sh check-approvals.sh <requirements-artifact> <phase>
#   <requirements-artifact>  e.g. docs/agents-v0/requirements/my-feature.md
#   <phase>                  onboard | roadmap | architecture | plan | intake | design | arc | build | verify | release | maintain | milestone
#                            (roadmap: docs/agents-v0/roadmap/<program>.md, the /v0-roadmap approval;
#                             architecture: docs/agents-v0/architecture.md, the /v0-architecture approval;
#                             plan: a milestone manifest's program-planning approval;
#                             arc: docs/agents-v0/design/system/arc-record.md, the committee approval;
#                             onboard: docs/agents-v0/onboarding/report.md, the /v0-onboard approval)
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
  onboard|roadmap|architecture|plan|intake|design|arc|build|verify|release|maintain|milestone) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected onboard|roadmap|architecture|plan|intake|design|arc|build|verify|release|maintain|milestone)\n' "$phase" >&2
    exit 1
    ;;
esac

[ -f "$art" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$art" >&2; exit 1; }

# Extract the "Delivery approvals" section (heading to next heading), stripping HTML comments.
section="$(awk '
  /^#+[[:space:]]*[Dd]elivery [Aa]pprovals/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$art" | awk '
  BEGIN { in_c = 0 }
  {
    s = $0
    out = ""
    while (length(s) > 0) {
      if (!in_c) {
        p = index(s, "<!--")
        if (p == 0) {
          out = out s
          s = ""
        } else {
          out = out substr(s, 1, p - 1)
          s = substr(s, p + 4)
          in_c = 1
        }
      } else {
        p = index(s, "-->")
        if (p == 0) {
          s = ""
        } else {
          s = substr(s, p + 3)
          in_c = 0
        }
      }
    }
    if (!in_c && out ~ /[^ \t]/) print out
  }
')"

[ -n "$section" ] || { printf 'FAIL: %s has no "Delivery approvals" section\n' "$art" >&2; exit 1; }

# Find the row for the phase; it must exist and record an explicit approval
# (a real user decision — never inferred). When a phase has several rows, the last one is the
# current decision: an earlier Approved row does not outlive a later Re-opened row.
row="$(printf '%s' "$section" | grep -i "|[[:space:]]*${phase}[[:space:]]*|" | tail -n1 || true)"
[ -n "$row" ] || { printf 'FAIL: no approval row for phase "%s" in %s\n' "$phase" "$art" >&2; exit 1; }

# Reject template placeholders in the approval row (<...>, [...], TBD, TODO, FIXME, etc.)
if printf '%s' "$row" | grep -Eq '(<[^>]+>|\[\.\.\.\]|\b(TBD|TODO|FIXME|XXX?)\b|__+|[?]{2,})'; then
  printf 'FAIL: phase "%s" in %s contains unresolved placeholders\n' "$phase" "$art" >&2
  exit 1
fi

# The Decision column is the 4th table field (awk fields: 1 empty, 2 Phase,
# 3 Artifacts, 4 Approver, 5 Decision). Require a leading positive token so
# negations such as "Not approved" or "Rejected" fail.
decision="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print tolower($5)}' | head -n1)"
printf '%s' "$decision" | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)' || {
  printf 'FAIL: phase "%s" is recorded in %s but has no explicit approval (decision: "%s")\n' "$phase" "$art" "$decision" >&2
  exit 1
}
# A conditional approval is not an approval: record Approved once the conditions are met.
if printf '%s' "$decision" | grep -Eqi '(condition|provisional|pending|subject to)'; then
  printf 'FAIL: phase "%s" in %s is a conditional approval (decision: "%s"); record Approved after the conditions are met\n' "$phase" "$art" "$decision" >&2
  exit 1
fi

printf 'OK: phase "%s" approval recorded in %s\n' "$phase" "$art"
