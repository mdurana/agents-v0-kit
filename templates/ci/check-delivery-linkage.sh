#!/bin/sh
# check-delivery-linkage.sh — PRs that change application code must reference a feature artifact.
#
# Usage: sh check-delivery-linkage.sh <base-sha> <head-sha> [<pr-body-file>] [<pr-number>]
# Reads Feature-Artifact: docs/requirements/<feature>.md from the MR/PR body (markdown bold allowed)
# or infers it from changed docs.
# Phase required: intake for docs-only artifact MRs; build approval in the artifact for app code.
# A live GitLab/GitHub approval may match the Approver on an Approved release row or an Approved verify row.
# Set CHECK_MR_APPROVER=0 to skip that live match (GitLab runs it in the manual delivery-approval job).
#
# Exit 0 when no app code changed, or linkage + phase approval present; 1 otherwise.

set -eu

base="${1:-}"
head="${2:-}"
body_file="${3:-}"
pr_number="${4:-}"
if [ -z "$base" ] || [ -z "$head" ]; then
  printf 'usage: %s <base-sha> <head-sha> [<pr-body-file>] [<pr-number>]\n' "$0" >&2
  exit 1
fi

from="$(git merge-base "$base" "$head" 2>/dev/null || echo "$base")"
code_files="$(git diff --name-only "$from" "$head" -- \
  ':(exclude)docs/**' ':(exclude)*.md' ':(exclude)*.mdc' \
  ':(exclude).github/**' ':(exclude).gitlab/**' ':(exclude).gitlab-ci.yml' ':(exclude)ci/**' 2>/dev/null || true)"

verify_docs="$(git diff --name-only "$from" "$head" -- 'docs/verify/**' 2>/dev/null || true)"
build_docs="$(git diff --name-only "$from" "$head" -- 'docs/build/**' 2>/dev/null || true)"
req_docs="$(git diff --name-only "$from" "$head" -- 'docs/requirements/**/*.md' 2>/dev/null || true)"

artifact=""
if [ -n "$body_file" ] && [ -f "$body_file" ]; then
  artifact="$(grep -Ei '^[[:space:]]*\*{0,2}Feature-Artifact:\*{0,2}[[:space:]]*docs/requirements/' "$body_file" | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/^[*[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "$artifact" ]; then
  artifact="$(printf '%s\n' "$req_docs" | head -n1 || true)"
fi

here="$(cd "$(dirname "$0")" && pwd)"

# Bind a phase approval to a human MR/PR review (GitLab default; GitHub when in Actions).
check_approver_binding() {
  artifact="$1"
  phase="$2"
  review_id="${3:-}"
  review_ref="${CI_MERGE_REQUEST_IID:-$review_id}"
  [ -n "$review_ref" ] || return 0
  if [ -n "${CI_MERGE_REQUEST_IID:-}" ] || [ "${GITLAB_CI:-}" = "true" ] || [ "${GITLAB_CI:-}" = "1" ]; then
    if [ -f "$here/check-approver-gitlab.sh" ]; then
      sh "$here/check-approver-gitlab.sh" "$artifact" "$phase" "$review_ref" || exit 1
    fi
    return 0
  fi
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -f "$here/check-approver-github.sh" ] && [ -n "$review_id" ]; then
    sh "$here/check-approver-github.sh" "$artifact" "$phase" "$review_id" || exit 1
    return 0
  fi
  if [ -f "$here/check-approver-gitlab.sh" ] && { [ -n "${GLAB_TOKEN:-}" ] || [ -n "${GITLAB_TOKEN:-}" ] || [ -n "${CI_JOB_TOKEN:-}" ]; }; then
    sh "$here/check-approver-gitlab.sh" "$artifact" "$phase" "$review_ref" || exit 1
    return 0
  fi
  if [ -f "$here/check-approver-github.sh" ] && [ -n "${GH_TOKEN:-}" ] && [ -n "$review_id" ]; then
    sh "$here/check-approver-github.sh" "$artifact" "$phase" "$review_id" || exit 1
  fi
}

# Approver is column 4 and Decision is column 5 of the canonical approvals table.
approval_field() {
  file="$1"
  phase="$2"
  col="$3"
  awk -v phase="$phase" -v col="$col" '
    /^#+[[:space:]]*[Dd]elivery [Aa]pprovals/ { in_section = 1; next }
    /^#+[[:space:]]/ { in_section = 0 }
    in_section && index($0, "|") == 1 {
      n = split($0, c, "|")
      gsub(/^[ \t]+|[ \t]+$/, "", c[2])
      if (tolower(c[2]) == tolower(phase) && (col + 0) <= n) {
        gsub(/^[ \t]+|[ \t]+$/, "", c[col])
        print c[col]
        exit
      }
    }
  ' "$file"
}

# Approved release and verify rows. A live review may name either Approver.
review_phases() {
  art="$1"
  found=""
  for phase in release verify; do
    approver="$(approval_field "$art" "$phase" 4)"
    decision="$(approval_field "$art" "$phase" 5)"
    if [ -n "$approver" ] && printf '%s' "$decision" | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)'; then
      if [ -z "$found" ]; then
        found="$phase"
      else
        found="$found,$phase"
      fi
    fi
  done
  if [ -z "$found" ]; then
    printf 'FAIL: record an Approved release or verify row naming the MR/PR reviewer. The build Approver is not compared to that review.\n' >&2
    return 1
  fi
  printf '%s\n' "$found"
}

bind_recorded_reviewer() {
  artifact="$1"
  review_id="${2:-}"
  [ "${CHECK_MR_APPROVER:-1}" != "0" ] || return 0
  review_ref="${CI_MERGE_REQUEST_IID:-$review_id}"
  [ -n "$review_ref" ] || return 0
  phases="$(review_phases "$artifact")" || exit 1
  check_approver_binding "$artifact" "$phases" "$review_id"
}

# Milestone manifests: go/no-go only when the milestone approval row changes
milestones="$(git diff --name-only "$from" "$head" -- 'docs/milestones/*.md' 2>/dev/null || true)"
for m in $milestones; do
  if git diff "$from" "$head" -- "$m" | grep -Eqi '\|[[:space:]]*milestone[[:space:]]*\|'; then
    sh "$here/check-approvals.sh" "$m" milestone || exit 1
    sh "$here/check-milestone.sh" "$m" verify || exit 1
  fi
done

if [ -z "$code_files" ]; then
  if [ -n "$req_docs" ]; then
    for f in $req_docs; do
      sh "$here/check-approvals.sh" "$f" intake || exit 1
    done
  fi
  if [ -n "$build_docs" ] && [ -n "$artifact" ] && [ -f "$artifact" ]; then
    sh "$here/check-approvals.sh" "$artifact" build || exit 1
    sh "$here/check-evidence.sh" "$artifact" build || exit 1
  fi
  if [ -n "$verify_docs" ] && [ -n "$artifact" ] && [ -f "$artifact" ]; then
    sh "$here/check-approvals.sh" "$artifact" verify || exit 1
    sh "$here/check-evidence.sh" "$artifact" verify || exit 1
    bind_recorded_reviewer "$artifact" "$pr_number"
  fi
  printf 'OK: docs-only PR — phase checks applied\n'
  exit 0
fi

if [ -z "$artifact" ] || [ ! -f "$artifact" ]; then
  printf 'FAIL: code changed but no Feature-Artifact (docs/requirements/<feature>.md) in PR body or diff\n' >&2
  exit 1
fi

sh "$here/check-approvals.sh" "$artifact" build || exit 1
bind_recorded_reviewer "$artifact" "$pr_number"
if [ -n "$build_docs" ] || [ -n "$verify_docs" ]; then
  sh "$here/check-evidence.sh" "$artifact" build || exit 1
fi
if [ -n "$verify_docs" ]; then
  sh "$here/check-approvals.sh" "$artifact" verify || exit 1
  sh "$here/check-evidence.sh" "$artifact" verify || exit 1
fi

printf 'OK: code changes linked to %s with build approval (verify when verify docs change)\n' "$artifact"
