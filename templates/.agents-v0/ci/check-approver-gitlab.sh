#!/bin/sh
# check-approver-gitlab.sh — bind a recorded phase approval to a real GitLab MR approval.
#
# Usage: sh .agents-v0/ci/check-approver-gitlab.sh <requirements-artifact> <phase> <mr-iid>
#
# Auth (first match wins):
#   - GITLAB_TOKEN or GL_TOKEN via PRIVATE-TOKEN when the API URL and project id are set
#   - glab when a token is set and glab is installed (local use)
#   - CI_JOB_TOKEN as a fallback. A 403 is a configuration failure: add GITLAB_TOKEN.
#
# <phase> may be one phase or a comma-separated list (release,verify).
# Passes when the MR has an approval from a non-bot account AND that username
# appears in the Approver column of any listed phase row (e.g. "@dev" or "dev").
# REQUIRE_APPROVER_MATCH=0 relaxes the column match; REQUIRE_GITLAB_MR_APPROVAL=0 skips.

set -eu

art="${1:-}"
phase="${2:-}"
mr="${3:-}"
if [ -z "$art" ] || [ -z "$phase" ] || [ -z "$mr" ]; then
  printf 'usage: %s <requirements-artifact> <phase> <mr-iid>\n' "$0" >&2
  exit 1
fi

if [ "${REQUIRE_GITLAB_MR_APPROVAL:-1}" = "0" ]; then
  printf 'SKIP: REQUIRE_GITLAB_MR_APPROVAL=0\n'
  exit 0
fi

[ -f "$art" ] || { printf 'FAIL: artifact not found: %s\n' "$art" >&2; exit 1; }

fetch_approvers_glab() {
  command -v glab >/dev/null 2>&1 || return 1
  [ -n "${token:-}" ] || return 1
  if ! json="$(GITLAB_TOKEN="$token" glab mr view "$mr" --json approved_by 2>&1)"; then
    printf 'FAIL: glab mr view %s: %s\n' "$mr" "$json" >&2
    exit 1
  fi
  printf '%s' "$json" | print_approver_usernames
}

print_approver_usernames() {
  python3 -c '
import json, sys
data = json.load(sys.stdin)
for entry in data.get("approved_by") or []:
    user = entry.get("user") or entry
    if isinstance(user, dict) and user.get("username"):
        print(user["username"])
'
}

fetch_approvers_http() {
  header_name="$1"
  header_value="$2"
  api="$3"
  project="$4"
  url="${api}/projects/${project}/merge_requests/${mr}/approvals"
  body="$(mktemp)"
  code="$(curl -sS -o "$body" -w "%{http_code}" --header "${header_name}: ${header_value}" "$url" || true)"
  if [ "$code" = "401" ] || [ "$code" = "403" ]; then
    rm -f "$body"
    if [ "$header_name" = "JOB-TOKEN" ]; then
      printf 'FAIL: CI_JOB_TOKEN cannot read merge request approvals (HTTP %s). Add GITLAB_TOKEN (read_api, masked) with environment scope delivery-approval, approve the MR, then run the manual delivery-approval job.\n' "$code" >&2
    else
      printf 'FAIL: GitLab token cannot read merge request approvals (HTTP %s). Set GITLAB_TOKEN (read_api, masked) with environment scope delivery-approval.\n' "$code" >&2
    fi
    exit 1
  fi
  if [ "$code" != "200" ]; then
    err="$(cat "$body" 2>/dev/null || true)"
    rm -f "$body"
    printf 'FAIL: GitLab approvals API for MR !%s returned HTTP %s: %s\n' "$mr" "$code" "$err" >&2
    exit 1
  fi
  print_approver_usernames <"$body"
  rm -f "$body"
}

humans=""
token="${GITLAB_TOKEN:-${GL_TOKEN:-${GLAB_TOKEN:-}}}"
api="${CI_API_V4_URL:-}"
project="${CI_PROJECT_ID:-${GITLAB_PROJECT_ID:-}}"
if [ -n "$token" ] && [ -n "$api" ] && [ -n "$project" ]; then
  humans="$(fetch_approvers_http "PRIVATE-TOKEN" "$token" "$api" "$project")"
elif command -v glab >/dev/null 2>&1 && [ -n "$token" ]; then
  humans="$(fetch_approvers_glab)"
elif [ -n "${CI_JOB_TOKEN:-}" ] && [ -n "$api" ] && [ -n "$project" ]; then
  humans="$(fetch_approvers_http "JOB-TOKEN" "$CI_JOB_TOKEN" "$api" "$project")"
else
  printf 'FAIL: set GITLAB_TOKEN (read_api, masked, environment scope delivery-approval). CI_JOB_TOKEN is only a fallback and often cannot read approvals.\n' >&2
  exit 1
fi

humans="$(printf '%s\n' "$humans" | grep -viE '^(project_.*_bot|gitlab-ci-token|ghost|support-bot)$' | sort -u || true)"
if [ -z "$humans" ]; then
  printf 'FAIL: MR !%s has no approval from a human (phase %s, %s)\n' "$mr" "$phase" "$art" >&2
  exit 1
fi

if [ "${REQUIRE_APPROVER_MATCH:-1}" = "0" ]; then
  printf 'OK: MR !%s approved by %s (approver-column match disabled)\n' "$mr" "$(printf '%s' "$humans" | tr '\n' ' ')"
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
  approver="$(printf '%s' "$section" | grep -i "|[[:space:]]*${one}[[:space:]]*|" | tail -n1 | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print tolower($4)}')"
  [ -n "$approver" ] || continue
  recorded="${recorded:+$recorded; }$one=$approver"
  for login in $humans; do
    lc="$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
    if printf '%s' "$approver" | grep -Eq "(^|[^a-z0-9-])@?${lc}([^a-z0-9-]|$)"; then
      printf 'OK: %s phase %s approver %s matches GitLab approval on MR !%s\n' "$art" "$one" "$login" "$mr"
      exit 0
    fi
  done
done
[ -n "$recorded" ] || { printf 'FAIL: no Approver recorded for phase %s in %s\n' "$phase" "$art" >&2; exit 1; }

printf 'FAIL: none of the Approver cells (%s) name a human who approved MR !%s (%s)\n' \
  "$recorded" "$mr" "$(printf '%s' "$humans" | tr '\n' ' ')" >&2
exit 1
