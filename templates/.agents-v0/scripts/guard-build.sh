#!/bin/sh
# guard-build.sh — single entry point and security boundary for /v0-build.
# Usage:
#   sh .agents-v0/scripts/guard-build.sh check <feature> [--reopen]
#   sh .agents-v0/scripts/guard-build.sh start <feature> [--reopen]
#   sh .agents-v0/scripts/guard-build.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-build.sh ready <feature>
#   sh .agents-v0/scripts/guard-build.sh commit <feature>
#   sh .agents-v0/scripts/guard-build.sh steps
#
# Design: DB1 (/v0-build guard and parameterized per-story build gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-build.sh"

gb_usage() {
  printf 'usage: %s check <feature> [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gb_validate_slug() {
  gb_v_step="$1"
  gb_v_slug="${2:-}"
  [ -n "$gb_v_slug" ] || gc_refuse "$gb_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gb_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gb_v_step" "feature slug '$gb_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gb_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gb_v_step" "feature slug '$gb_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gb_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gb_v_step" "story '$gb_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-build"
      ;;
  esac
}

gb_rule() {
  gb_step="$1"
  gb_key="$2"
  gb_slug="${3:-}"
  gb_rules="${GC_HERE}/../gate-rules"
  [ -f "$gb_rules" ] || gc_refuse "$gb_step" "missing gate-rules file ($gb_rules)"
  gb_val="$(awk -v p="build" -v k="$gb_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gb_rules")"
  [ -n "$gb_val" ] || gc_refuse "$gb_step" "gate-rules missing key '$gb_key' for phase 'build'"
  if [ -n "$gb_slug" ]; then
    gb_val="$(printf '%s' "$gb_val" | sed "s/<feature>/$gb_slug/g")"
  fi
}

gb_load() {
  gb_step="$1"
  gb_slug="$2"
  gb_validate_slug "$gb_step" "$gb_slug"
  gc_to_root "$gb_step"
  gb_rule "$gb_step" phase "$gb_slug"; gb_phase="$gb_val"
  gb_rule "$gb_step" feature "$gb_slug"; gb_feature="$gb_val"
  gb_rule "$gb_step" state "$gb_slug"; gb_state="$gb_val"
  gb_rule "$gb_step" artifact "$gb_slug"; gb_artifact="$gb_val"
  gb_rule "$gb_step" report "$gb_slug"; gb_report="$gb_val"
  gb_rule "$gb_step" output "$gb_slug"; gb_output="$gb_val"
  gb_rule "$gb_step" result "$gb_slug"; gb_result="$gb_val"
  gb_req_art="docs/agents-v0/requirements/${gb_feature}.md"
}

gb_check_prereqs() {
  gb_step="$1"
  gb_reqs="$2"
  gb_reopen="${3:-0}"
  gb_rule "$gb_step" approved.next "$gb_feature"; gb_approved_next="$gb_val"

  for gb_req in $gb_reqs; do
    case "$gb_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gb_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        gb_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gb_skip_bg=1
        # <<< kit-test-override
        if [ "$gb_skip_bg" != 1 ]; then
          gb_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$gb_cur" != "feature/$gb_feature" ]; then
            gb_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gb_feature}" '
              /^worktree / { path = substr($0, 10) }
              $0 == want { print path; exit }
            ')"
            if [ -n "$gb_wt" ]; then
              gc_refuse "$gb_step" "build for '$gb_feature' must run in worktree '$gb_wt' on branch 'feature/$gb_feature' (current branch: '${gb_cur:-detached}'). Open that folder and run /v0-build $gb_feature there"
            else
              gc_refuse "$gb_step" "no 'feature/$gb_feature' branch or worktree exists (current branch: '${gb_cur:-detached}'); complete /v0-intake $gb_feature (approve + guard-intake.sh commit $gb_feature) first"
            fi
          fi
        fi
        ;;
      pack-configured)
        if [ -f "docs/agents-v0/project-profile.md" ] && [ -d ".agents-v0/packs" ]; then
          gb_pack="$(awk -F'|' '
            function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
            tolower($0) ~ /\|[ \t]*pack[ \t]*\|/ {
              v = trim($3)
              gsub(/<!--.*-->/, "", v)
              v = trim(v)
              if (v != "" && v !~ /^</) { print v; exit }
            }
          ' docs/agents-v0/project-profile.md)"
          if [ -n "$gb_pack" ] && [ ! -f ".agents-v0/packs/$gb_pack/pack.json" ]; then
            gc_refuse "$gb_step" "project-profile.md names Pack '$gb_pack', but '.agents-v0/packs/$gb_pack/pack.json' is missing"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gb_state" ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              gc_refuse "$gb_step" "story '$gb_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              ;;
          esac
        fi
        ;;
      design-approved)
        [ -f "$gb_req_art" ] \
          || gc_refuse "$gb_step" "requirements artifact '$gb_req_art' is missing; complete /v0-intake $gb_feature and /v0-design $gb_feature first"
        [ -f "$gb_state" ] \
          || gc_refuse "$gb_step" "requirements state '$gb_state' is missing; complete /v0-intake $gb_feature and /v0-design $gb_feature first"
        gb_cn=0
        if [ -f "$gb_result" ] && grep -Fq "phase: design" "$gb_result" && grep -Fq "status: contract_none" "$gb_result"; then
          gb_cn=1
        fi
        if [ "$gb_cn" != 1 ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" design "*) ;;
            *) gc_refuse "$gb_step" "design is not in approvedPhases in '$gb_state' (and not Contract: None); complete /v0-design $gb_feature first" ;;
          esac
          gb_dgm="$(gc_state_get "$gb_state" designGuardManaged 2>/dev/null || true)"
          if [ "$gb_dgm" = "True" ] || [ "$gb_dgm" = "true" ]; then
            if ! gb_des_ok="$(gc_approval_ok design "$gb_feature")"; then
              gc_refuse "$gb_step" "external design approval record missing or mismatched ($gb_des_ok); complete /v0-design $gb_feature first"
            fi
          fi
        fi
        # Verify design gate is committed (unless skipped in kit test override)
        gb_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gb_skip_cc=1
        # <<< kit-test-override
        if [ "$gb_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ] && [ "$gb_reopen" != 1 ]; then
          gb_prev_act="$(gc_state_get "$gb_state" activePhase 2>/dev/null || true)"
          if [ -z "$gb_prev_act" ]; then
            if ! gb_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$gb_req_art" 2>&1)"; then
              gc_refuse "$gb_step" "design gate is not committed on feature/$gb_feature: $gb_cc_out"
            fi
          fi
        fi
        ;;
      dependencies-verified)
        if [ -f "$GC_HERE/check-story-dependencies.sh" ]; then
          if ! gb_dep_out="$(sh "$GC_HERE/check-story-dependencies.sh" "$gb_req_art" 2>&1)"; then
            gc_refuse "$gb_step" "story dependency check failed: $gb_dep_out"
          fi
        fi
        ;;
      not-approved)
        if [ "$gb_reopen" != 1 ] && [ -f "$gb_state" ]; then
          case " $(gc_state_get "$gb_state" approvedPhases | tr -d '[]",') " in
            *" $gb_phase "*)
              gc_refuse "$gb_step" "build is already approved for '$gb_feature'; suggest $gb_approved_next (or pass --reopen to reopen build)"
              ;;
          esac
        fi
        if [ "$gb_reopen" = 1 ] && [ -f "$gb_state" ]; then
          gb_rc="$(gc_state_get "$gb_state" reopenCount 2>/dev/null || echo 0)"
          case "$gb_rc" in ''|*[!0-9]*) gb_rc=0 ;; esac
          if [ "$gb_rc" -ge 3 ]; then
            gc_refuse "$gb_step" "reopen bounce cap exceeded for '$gb_feature' (reopenCount=$gb_rc >= 3); escalate to Sensei before reopening again"
          fi
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gb_state" ]; then
          [ "$(gc_state_get "$gb_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gb_step" "build for '$gb_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve build $gb_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gb_state" ] || gc_refuse "$gb_step" "build for '$gb_feature' has not been started; run $G start $gb_feature first"
        [ "$(gc_state_get "$gb_state" activePhase)" = "$gb_phase" ] \
          || gc_refuse "$gb_step" "activePhase for '$gb_feature' is '$(gc_state_get "$gb_state" activePhase)', not '$gb_phase'; run $G start $gb_feature first"
        [ "$(gc_state_get "$gb_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gb_step" "build for '$gb_feature' is not in_progress (status: $(gc_state_get "$gb_state" activeStatus)); run $G start $gb_feature first"
        ;;
      *) gc_refuse "$gb_step" "gate-rules names an unknown prerequisite '$gb_req'; reinstall the kit" ;;
    esac
  done
}

gb_check() {
  gb_c_slug=""
  gb_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gb_c_reopen=1
        shift
        ;;
      -*)
        gb_usage
        ;;
      *)
        [ -z "$gb_c_slug" ] || gb_usage
        gb_c_slug="$1"
        shift
        ;;
    esac
  done

  gb_load check "$gb_c_slug"
  gb_rule check check.requires "$gb_feature"; gb_requires="$gb_val"
  gb_check_prereqs check "$gb_requires" "$gb_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-build $gb_feature"
  if [ "$gb_c_reopen" = 1 ]; then
    printf 'Next: Start reopened build with: %s start %s --reopen\n' "$G" "$gb_feature"
  else
    printf 'Next: Start build with: %s start %s\n' "$G" "$gb_feature"
  fi
}

cmd="${1:-}"
[ -n "$cmd" ] || gb_usage
shift || true

case "$cmd" in
  check) gb_check "$@" ;;
  *) gb_usage ;;
esac
