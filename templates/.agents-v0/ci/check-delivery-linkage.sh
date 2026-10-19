#!/bin/sh
# check-delivery-linkage.sh — merge requests that change application code must reference a feature artifact.
#
# Usage: sh check-delivery-linkage.sh <base-sha> <head-sha> [<mr-body-file>] [<mr-iid>]
# Reads Feature-Artifact: docs/agents-v0/requirements/<feature>.md from the MR body (markdown bold allowed)
# or infers it from changed docs.
# Phase required: intake for docs-only artifact MRs; build approval in the artifact for app code.
# A live GitLab approval may match the Approver on an Approved release row or an Approved verify row.
# Set CHECK_MR_APPROVER=0 to skip that live match (GitLab runs it in the manual delivery-approval job).
#
# A bug fix, CVE patch, dependency bump, or hotfix names "Maintain-Note: docs/agents-v0/maintain/<id>/note.md"
# instead (or adds a new note in the diff). The note's Tier decides the checks: trivial (classifier-
# eligible, abbreviated Verify), standard (full Verify, size-bounded), emergency (rollback and a
# follow-up Verify due date; the Verify row may come after the merge).
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

body_artifact=""
body_note=""
if [ -n "$body_file" ] && [ -f "$body_file" ]; then
  body_artifact="$(grep -Ei '^[[:space:]]*\*{0,2}Feature-Artifact:\*{0,2}[[:space:]]*docs/agents-v0/requirements/' "$body_file" | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/^[*[:space:]]*//;s/[[:space:]]*$//' || true)"
  body_note="$(grep -Ei '^[[:space:]]*\*{0,2}Maintain-Note:\*{0,2}[[:space:]]*docs/agents-v0/maintain/' "$body_file" | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/^[*[:space:]]*//;s/[[:space:]]*$//' || true)"
fi

from="$(git merge-base "$base" "$head" 2>/dev/null || echo "$base")"
from_sha="$(git rev-parse --verify -q "${from}^{commit}" 2>/dev/null || true)"
head_sha="$(git rev-parse --verify -q "${head}^{commit}" 2>/dev/null || true)"

resolve_story_base() {
  target_art="$1"
  target_note="$2"
  slug=""
  state_file=""
  if [ -n "$target_art" ]; then
    slug="$(basename "$target_art" .md)"
    state_file="docs/agents-v0/requirements/${slug}.state.json"
  elif [ -n "$target_note" ]; then
    slug="$(basename "$(dirname "$target_note")")"
    state_file="docs/agents-v0/maintain/${slug}/state.json"
  fi
  [ -n "$slug" ] || return 0
  rep_sha=""
  for rp in "docs/agents-v0/build/${slug}/build-report.md" "docs/agents-v0/verify/${slug}/test-report.md"; do
    if [ -f "$rp" ]; then
      raw_rep="$(grep -Ei '^commit:[[:space:]]*[0-9a-f]{7,40}' "$rp" 2>/dev/null | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/[[:space:]].*//' || true)"
      if [ -n "$raw_rep" ]; then
        rep_sha="$(git rev-parse --verify -q "${raw_rep}^{commit}" 2>/dev/null || true)"
        [ -n "$rep_sha" ] && break
      fi
    fi
  done
  bc_sha=""
  if [ -f "$state_file" ]; then
    raw_bc="$(grep -Eo '"baseCommit"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{7,40}"' "$state_file" 2>/dev/null | head -n1 | sed 's/.*"baseCommit"[[:space:]]*:[[:space:]]*"//;s/"//' || true)"
    if [ -n "$raw_bc" ]; then
      bc_sha="$(git rev-parse --verify -q "${raw_bc}^{commit}" 2>/dev/null || true)"
    fi
  fi
  if [ -n "$bc_sha" ]; then
    if [ "$bc_sha" = "$head_sha" ] || ! git merge-base --is-ancestor "$bc_sha" "$head_sha" 2>/dev/null; then
      bc_sha=""
    elif [ -n "$rep_sha" ] && { [ "$bc_sha" = "$rep_sha" ] || ! git merge-base --is-ancestor "$bc_sha" "$rep_sha" 2>/dev/null; }; then
      bc_sha=""
    fi
  fi
  first_c="$(git log --reverse --format=%H "$head" -- \
    ${target_art:+"$target_art"} ${target_note:+"$target_note"} \
    "docs/agents-v0/design/${slug}" "docs/agents-v0/build/${slug}" \
    "docs/agents-v0/verify/${slug}" "docs/agents-v0/maintain/${slug}" 2>/dev/null | head -n1 || true)"
  first_parent=""
  if [ -n "$first_c" ]; then
    first_parent="$(git rev-parse --verify -q "${first_c}^" 2>/dev/null || true)"
  fi
  if [ -n "$first_parent" ]; then
    if [ "$first_parent" = "$head_sha" ] || ! git merge-base --is-ancestor "$first_parent" "$head_sha" 2>/dev/null; then
      first_parent=""
    elif [ -n "$rep_sha" ] && { [ "$first_parent" = "$rep_sha" ] || ! git merge-base --is-ancestor "$first_parent" "$rep_sha" 2>/dev/null; }; then
      first_parent=""
    fi
  fi
  rep_parent=""
  if [ -n "$rep_sha" ]; then
    rep_parent="$(git rev-parse --verify -q "${rep_sha}^" 2>/dev/null || true)"
  fi
  if [ -n "$first_parent" ] && [ -n "$bc_sha" ]; then
    if git merge-base --is-ancestor "$first_parent" "$bc_sha" 2>/dev/null; then
      printf '%s\n' "$first_parent"
    else
      printf '%s\n' "$bc_sha"
    fi
  elif [ -n "$first_parent" ]; then
    printf '%s\n' "$first_parent"
  elif [ -n "$bc_sha" ]; then
    printf '%s\n' "$bc_sha"
  elif [ -n "$rep_parent" ]; then
    printf '%s\n' "$rep_parent"
  fi
}

if [ -n "$head_sha" ] && [ "$from_sha" = "$head_sha" ]; then
  resolved_from="$(resolve_story_base "$body_artifact" "$body_note")"
  if [ -n "$resolved_from" ]; then
    from="$resolved_from"
    from_sha="$resolved_from"
  fi
fi

code_files="$(git diff --name-only "$from" "$head" -- \
  ':(exclude)docs/**' ':(exclude)*.md' ':(exclude)*.mdc' \
  ':(exclude).github/**' ':(exclude).gitlab/**' ':(exclude).gitlab-ci.yml' \
  ':(exclude).agents-v0/**' ':(exclude).cursor/**' ':(exclude).agents-kit-version' 2>/dev/null || true)"

verify_docs="$(git diff --name-only "$from" "$head" -- 'docs/agents-v0/verify/**' 2>/dev/null || true)"
build_docs="$(git diff --name-only "$from" "$head" -- 'docs/agents-v0/build/**' 2>/dev/null || true)"
req_docs="$(git diff --name-only "$from" "$head" -- 'docs/agents-v0/requirements/**/*.md' 2>/dev/null || true)"

artifact="$body_artifact"
if [ -z "$artifact" ]; then
  artifact="$(printf '%s\n' "$req_docs" | head -n1 || true)"
fi

here="$(cd "$(dirname "$0")" && pwd)"

# Bind a phase approval to a human GitLab MR review.
check_approver_binding() {
  artifact="$1"
  phase="$2"
  review_id="${3:-}"
  review_ref="${CI_MERGE_REQUEST_IID:-$review_id}"
  [ -n "$review_ref" ] || return 0
  if [ -f "$here/check-approver-gitlab.sh" ]; then
    if [ -n "${CI_MERGE_REQUEST_IID:-}" ] || [ "${GITLAB_CI:-}" = "true" ] || [ "${GITLAB_CI:-}" = "1" ]; then
      sh "$here/check-approver-gitlab.sh" "$artifact" "$phase" "$review_ref" || exit 1
      return 0
    fi
    if [ -n "${GLAB_TOKEN:-}" ] || [ -n "${GITLAB_TOKEN:-}" ] || [ -n "${CI_JOB_TOKEN:-}" ]; then
      sh "$here/check-approver-gitlab.sh" "$artifact" "$phase" "$review_ref" || exit 1
    fi
  fi
}

# Approver is column 4 and Decision is column 5 of the canonical approvals table.
# When a phase has several rows, the last one is the current decision.
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
        found = c[col]
      }
    }
    END { if (found != "") print found }
  ' "$file"
}

# Approved release and verify rows. A live review may name either Approver.
review_phases() {
  art="$1"
  found=""
  for phase in release verify; do
    approver="$(approval_field "$art" "$phase" 4)"
    decision="$(approval_field "$art" "$phase" 5)"
    if [ -n "$approver" ] && printf '%s' "$decision" | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)' \
      && ! printf '%s' "$decision" | grep -Eqi '(condition|provisional|pending|subject to)'; then
      if [ -z "$found" ]; then
        found="$phase"
      else
        found="$found,$phase"
      fi
    fi
  done
  if [ -z "$found" ]; then
    printf 'FAIL: record an Approved release or verify row naming the MR reviewer. The build Approver is not compared to that review.\n' >&2
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
milestones="$(git diff --name-only "$from" "$head" -- 'docs/agents-v0/milestones/*.md' 2>/dev/null || true)"
for m in $milestones; do
  if git diff "$from" "$head" -- "$m" | grep -Eqi '^\+[^+].*\|[[:space:]]*plan[[:space:]]*\|'; then
    sh "$here/check-approvals.sh" "$m" plan || exit 1
  fi
  if git diff "$from" "$head" -- "$m" | grep -Eqi '\|[[:space:]]*milestone[[:space:]]*\|'; then
    sh "$here/check-approvals.sh" "$m" milestone || exit 1
    sh "$here/check-milestone.sh" "$m" verify || exit 1
  fi
done

# Onboarding report: an onboard approval row that changes needs the approval and its evidence.
if git diff "$from" "$head" -- docs/agents-v0/onboarding/report.md 2>/dev/null | grep -Eqi '^\+[^+].*\|[[:space:]]*onboard[[:space:]]*\|'; then
  sh "$here/check-approvals.sh" docs/agents-v0/onboarding/report.md onboard || exit 1
  sh "$here/check-evidence.sh" docs/agents-v0/onboarding/report.md onboard || exit 1
fi

# Maintenance note (Maintain-Note: docs/agents-v0/maintain/<id>/note.md): a bug fix, CVE patch, dependency
# bump, or hotfix has its own approvals and evidence instead of borrowing a feature artifact.
note=""
if [ -n "$body_file" ] && [ -f "$body_file" ]; then
  note="$(grep -Ei '^[[:space:]]*\*{0,2}Maintain-Note:\*{0,2}[[:space:]]*docs/agents-v0/maintain/' "$body_file" | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/^[*[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -z "$note" ]; then
  note="$(git diff --name-only --diff-filter=A "$from" "$head" -- 'docs/agents-v0/maintain/*/note.md' 2>/dev/null | head -n1 || true)"
fi

# note_field <file> <Field>: the value after "Field:", trimmed and lower-cased.
note_field() {
  grep -Ei "^[[:space:]]*$2:[[:space:]]*" "$1" | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/[[:space:]]*$//' | tr 'A-Z' 'a-z'
}

# note_section_text <file> <heading regex>: the section's lines without comments or blanks.
note_section_text() {
  awk '/^##[[:space:]]+'"$2"'/ { f = 1; next } /^#/ { f = 0 } f' "$1" | grep -Ev '<!--|-->|^[[:space:]]*$' || true
}

note_fail() {
  printf 'FAIL: maintenance note %s: %s\n' "$1" "$2" >&2
  exit 1
}

check_maintain_note() {
  n="$1"
  review_id="${2:-}"
  [ -f "$n" ] || note_fail "$n" "file not found"
  tier="$(note_field "$n" "Tier")"
  case "$tier" in
    trivial | standard | emergency) ;;
    *) note_fail "$n" "Tier must be trivial, standard, or emergency (got \"$tier\")" ;;
  esac
  sh "$here/check-approvals.sh" "$n" maintain || exit 1
  case "$tier" in
    trivial | emergency)
      confirmed="$(note_field "$n" "Tier confirmed by")"
      case "$confirmed" in
        '' | '<'*) note_fail "$n" "Tier $tier needs \"Tier confirmed by: <name> on <date>\" (a person agrees to the tier)" ;;
      esac
      ;;
  esac
  phases="verify"
  case "$tier" in
    trivial)
      sh "$here/classify-change.sh" "$from" "$head" --require-trivial >/dev/null || exit 1
      sh "$here/check-approvals.sh" "$n" verify || exit 1
      sh "$here/check-evidence.sh" "$n" verify || exit 1
      ;;
    standard)
      sh "$here/classify-change.sh" "$from" "$head" --max-lines "${MAINTAIN_MAX_LINES:-800}" >/dev/null || exit 1
      sh "$here/check-approvals.sh" "$n" verify || exit 1
      sh "$here/check-evidence.sh" "$n" verify || exit 1
      ;;
    emergency)
      due="$(note_field "$n" "Follow-up verify due")"
      printf '%s' "$due" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || note_fail "$n" "Tier emergency needs \"Follow-up verify due: YYYY-MM-DD\""
      [ -n "$(note_section_text "$n" '[Rr]ollback')" ] || note_fail "$n" "Tier emergency needs a Rollback section"
      sh "$here/classify-change.sh" "$from" "$head" --max-lines "${MAINTAIN_EMERGENCY_MAX_LINES:-300}" >/dev/null || exit 1
      phases="maintain"
      ;;
  esac
  [ "${CHECK_MR_APPROVER:-1}" != "0" ] || return 0
  check_approver_binding "$n" "$phases" "$review_id"
}

if [ -n "$note" ]; then
  if [ -n "$req_docs" ] || { [ -n "$artifact" ] && [ -n "$body_file" ] && grep -Eqi '^[[:space:]]*\*{0,2}Feature-Artifact:' "$body_file" 2>/dev/null; }; then
    note_fail "$note" "a maintenance change does not also carry a feature artifact; use one or the other"
  fi
  check_maintain_note "$note" "$pr_number"
  printf 'OK: maintenance change governed by %s (Tier %s)\n' "$note" "$(note_field "$note" "Tier")"
  exit 0
fi

# The design the user approved is still the design (design.lock), and the Build plan is real: every
# AC has a row, every done row names an existing test with a red card first (check-build-plan.sh).
# REQUIRE_DESIGN_LOCK=0 and REQUIRE_BUILD_PLAN=0 turn those off.
feature_design_and_plan() {
  slug="$(basename "$1" .md)"
  if [ -d "docs/agents-v0/design/$slug" ] && [ "${REQUIRE_DESIGN_LOCK:-1}" != "0" ]; then
    sh "$here/check-design.sh" "$slug" --verify-lock || exit 1
  fi
  if [ -f "docs/agents-v0/requirements/${slug}.state.json" ]; then
    sh "$here/check-feature-state.sh" "$1" || exit 1
  fi
  if [ "${REQUIRE_BUILD_PLAN:-1}" != "0" ]; then
    sh "$here/check-build-plan.sh" "$slug" --complete || exit 1
  fi
  sh "$here/check-arc.sh" "$1" || exit 1
}

require_committed_artifact() {
  f="$1"
  if [ "${VERIFY_STALE:-1}" != "0" ] && [ -n "$head_sha" ] && git cat-file -e "${head}^{commit}" 2>/dev/null; then
    if ! git cat-file -e "${head}:${f}" 2>/dev/null; then
      printf 'FAIL: %s is not committed in %s (untracked on disk) — commit the artifact before running the gate\n' "$f" "$head" >&2
      exit 1
    fi
    if ! git diff --quiet "$head" -- "$f" 2>/dev/null; then
      printf 'FAIL: %s has uncommitted changes on disk — commit the approval row before running the gate\n' "$f" >&2
      exit 1
    fi
  fi
}

artifact_needs_verify() {
  art="$1"
  [ -n "$verify_docs" ] && return 0
  [ "${REQUIRE_VERIFY:-0}" = "1" ] && return 0
  [ -n "${CI_MERGE_REQUEST_IID:-}" ] && return 0
  if [ -n "$art" ] && [ -f "$art" ]; then
    [ -n "$(approval_field "$art" verify 5)" ] && return 0
    [ -n "$(approval_field "$art" release 5)" ] && return 0
  fi
  return 1
}

artifact_needs_build() {
  art="$1"
  [ -n "$build_docs" ] && return 0
  artifact_needs_verify "$art" && return 0
  if [ -n "$art" ] && [ -f "$art" ]; then
    [ -n "$(approval_field "$art" build 5)" ] && return 0
  fi
  return 1
}

if [ -z "$code_files" ]; then
  if [ -n "$req_docs" ]; then
    for f in $req_docs; do
      require_committed_artifact "$f"
      sh "$here/check-approvals.sh" "$f" intake || exit 1
    done
  fi
  if [ -n "$artifact" ] && [ -f "$artifact" ]; then
    require_committed_artifact "$artifact"
    if artifact_needs_build "$artifact"; then
      sh "$here/check-approvals.sh" "$artifact" build || exit 1
      sh "$here/check-evidence.sh" "$artifact" build || exit 1
      feature_design_and_plan "$artifact"
    fi
    if artifact_needs_verify "$artifact"; then
      sh "$here/check-approvals.sh" "$artifact" verify || exit 1
      sh "$here/check-evidence.sh" "$artifact" verify || exit 1
      bind_recorded_reviewer "$artifact" "$pr_number"
    fi
  fi
  printf 'OK: docs-only PR — phase checks applied\n'
  exit 0
fi

if [ -z "$artifact" ] || [ ! -f "$artifact" ]; then
  printf 'FAIL: code changed but no Feature-Artifact (docs/agents-v0/requirements/<feature>.md) in PR body or diff\n' >&2
  exit 1
fi

require_committed_artifact "$artifact"

# A feature artifact is evidence for this change only when this change carries evidence. Borrowing an
# old feature's approvals for a bug fix or upgrade is what Maintain-Note is for.
if [ -z "$build_docs" ] && [ -z "$verify_docs" ] && [ "${ALLOW_ARTIFACT_WITHOUT_EVIDENCE:-0}" != "1" ]; then
  printf 'FAIL: code changed but this change carries no docs/build or docs/verify evidence for %s. A fix or upgrade uses "Maintain-Note: docs/agents-v0/maintain/<id>/note.md" instead (ALLOW_ARTIFACT_WITHOUT_EVIDENCE=1 skips this check).\n' "$artifact" >&2
  exit 1
fi

sh "$here/check-approvals.sh" "$artifact" build || exit 1
bind_recorded_reviewer "$artifact" "$pr_number"
if [ -n "$build_docs" ] || [ -n "$verify_docs" ] || [ "${REQUIRE_VERIFY:-0}" = "1" ]; then
  sh "$here/check-evidence.sh" "$artifact" build || exit 1
  feature_design_and_plan "$artifact"
fi
if artifact_needs_verify "$artifact"; then
  sh "$here/check-approvals.sh" "$artifact" verify || exit 1
  sh "$here/check-evidence.sh" "$artifact" verify || exit 1
fi

printf 'OK: code changes linked to %s with build approval (verify when verify docs change)\n' "$artifact"
