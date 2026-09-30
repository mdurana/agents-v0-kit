#!/bin/sh
# check-approver-github.sh — bind a recorded phase approval to a real GitHub PR review.
#
# Usage: sh ci/check-approver-github.sh <requirements-artifact> <phase> <pr-number>
#
# Requires GH_TOKEN (and GH_REPO outside a checkout). <phase> may be one phase or a
# comma-separated list (release,verify). Passes when the PR has an APPROVED review
# from a non-bot account AND that login appears in any listed Approver cell
# (e.g. "@octocat" or "octocat").
# REQUIRE_APPROVER_MATCH=0 relaxes the column match; REQUIRE_GITHUB_PR_APPROVAL=0 skips.

set -eu

art="${1:-}"
phase="${2:-}"
pr="${3:-}"
if [ -z "$art" ] || [ -z "$phase" ] || [ -z "$pr" ]; then
  printf 'usage: %s <requirements-artifact> <phase> <pr-number>\n' "$0" >&2
  exit 1
fi

if [ "${REQUIRE_GITHUB_PR_APPROVAL:-1}" = "0" ]; then
  printf 'SKIP: REQUIRE_GITHUB_PR_APPROVAL=0\n'
  exit 0
fi

command -v gh >/dev/null 2>&1 || { printf 'FAIL: gh CLI not installed\n' >&2; exit 1; }
[ -n "${GH_TOKEN:-}" ] || { printf 'FAIL: GH_TOKEN not set — pass github.token to this step\n' >&2; exit 1; }
[ -f "$art" ] || { printf 'FAIL: artifact not found: %s\n' "$art" >&2; exit 1; }

if ! reviews="$(gh pr view "$pr" --json reviews --jq '.reviews[] | select(.state=="APPROVED") | .author.login' 2>&1)"; then
  printf 'FAIL: could not read reviews for PR #%s: %s\n' "$pr" "$reviews" >&2
  exit 1
fi
humans="$(printf '%s\n' "$reviews" | grep -v '\[bot\]$' | grep -Ev '^(github-actions|dependabot|renovate|cursor)$' | sort -u || true)"
if [ -z "$humans" ]; then
  printf 'FAIL: PR #%s has no APPROVED review from a human (phase %s, %s)\n' "$pr" "$phase" "$art" >&2
  exit 1
fi

if [ "${REQUIRE_APPROVER_MATCH:-1}" = "0" ]; then
  printf 'OK: PR #%s approved by %s (approver-column match disabled)\n' "$pr" "$(printf '%s' "$humans" | tr '\n' ' ')"
  exit 0
fi

section="$(awk '
  /^#+[[:space:]]*[Dd]elivery [Aa]pprovals/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$art")"
phases="$(printf '%s' "$phase" | tr ',' ' ')"
recorded=""
for one in $phases; do
  approver="$(printf '%s' "$section" | grep -i "|[[:space:]]*${one}[[:space:]]*|" | head -n1 | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print tolower($4)}')"
  [ -n "$approver" ] || continue
  recorded="${recorded:+$recorded; }$one=$approver"
  for login in $humans; do
    lc="$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
    if printf '%s' "$approver" | grep -Eq "(^|[^a-z0-9-])@?${lc}([^a-z0-9-]|$)"; then
      printf 'OK: %s phase %s approver %s matches GitHub approval on PR #%s\n' "$art" "$one" "$login" "$pr"
      exit 0
    fi
  done
done
[ -n "$recorded" ] || { printf 'FAIL: no Approver recorded for phase %s in %s\n' "$phase" "$art" >&2; exit 1; }

printf 'FAIL: none of the Approver cells (%s) name a human who approved PR #%s (%s)\n' \
  "$recorded" "$pr" "$(printf '%s' "$humans" | tr '\n' ' ')" >&2
exit 1
