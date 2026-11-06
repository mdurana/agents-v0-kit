#!/bin/sh
# guard-verify.sh — single entry point and security boundary for /v0-verify.
# Usage:
#   sh .agents-v0/scripts/guard-verify.sh check <feature> [--reopen]
#   sh .agents-v0/scripts/guard-verify.sh start <feature> [--reopen] [--check-db]
#   sh .agents-v0/scripts/guard-verify.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-verify.sh ready <feature>
#   sh .agents-v0/scripts/guard-verify.sh commit <feature>
#   sh .agents-v0/scripts/guard-verify.sh steps
#
# Design: DV1 (/v0-verify guard and parameterized per-story verify gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-verify.sh"

gv_usage() {
  printf 'usage: %s check <feature> [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen] [--check-db]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gv_validate_slug() {
  gv_v_step="$1"
  gv_v_slug="${2:-}"
  [ -n "$gv_v_slug" ] || gc_refuse "$gv_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gv_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gv_v_step" "feature slug '$gv_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gv_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gv_v_step" "feature slug '$gv_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gv_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gv_v_step" "story '$gv_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-verify"
      ;;
  esac
}

gv_rule() {
  gv_step="$1"
  gv_key="$2"
  gv_slug="${3:-}"
  gv_rules="${GC_HERE}/../gate-rules"
  [ -f "$gv_rules" ] || gc_refuse "$gv_step" "missing gate-rules file ($gv_rules)"
  gv_val="$(awk -v p="verify" -v k="$gv_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gv_rules")"
  [ -n "$gv_val" ] || gc_refuse "$gv_step" "gate-rules missing key '$gv_key' for phase 'verify'"
  if [ -n "$gv_slug" ]; then
    gv_val="$(printf '%s' "$gv_val" | sed "s/<feature>/$gv_slug/g")"
  fi
}

gv_load() {
  gv_step="$1"
  gv_slug="$2"
  gv_validate_slug "$gv_step" "$gv_slug"
  gc_to_root "$gv_step"
  gv_rule "$gv_step" phase "$gv_slug"; gv_phase="$gv_val"
  gv_rule "$gv_step" feature "$gv_slug"; gv_feature="$gv_val"
  gv_rule "$gv_step" state "$gv_slug"; gv_state="$gv_val"
  gv_rule "$gv_step" artifact "$gv_slug"; gv_artifact="$gv_val"
  gv_rule "$gv_step" vapt "$gv_slug"; gv_vapt="$gv_val"
  gv_rule "$gv_step" review "$gv_slug"; gv_review="$gv_val"
  gv_rule "$gv_step" output "$gv_slug"; gv_output="$gv_val"
  gv_rule "$gv_step" result "$gv_slug"; gv_result="$gv_val"
  gv_req_art="docs/agents-v0/requirements/${gv_feature}.md"
  gv_is_maintain=0
  if [ ! -f "$gv_req_art" ] && [ -f "docs/agents-v0/maintain/${gv_feature}/note.md" ]; then
    gv_is_maintain=1
    gv_req_art="docs/agents-v0/maintain/${gv_feature}/note.md"
    gv_state="docs/agents-v0/maintain/${gv_feature}/state.json"
    gv_result="docs/agents-v0/maintain/${gv_feature}/phase-result.md"
  fi
}

gv_check_prereqs() {
  gv_step="$1"
  gv_reqs="$2"
  gv_reopen="${3:-0}"
  gv_rule "$gv_step" approved.next "$gv_feature"; gv_approved_next="$gv_val"

  for gv_req in $gv_reqs; do
    case "$gv_req" in
      git-work-tree) ;;
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gv_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      feature-branch)
        gv_skip_bg=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_BRANCH_GUARD:-0}" != 1 ] || gv_skip_bg=1
        # <<< kit-test-override
        if [ "$gv_skip_bg" != 1 ]; then
          gv_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
          if [ "$gv_is_maintain" = 1 ]; then
            gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || true)"
            gv_rel_ok=0
            case " $(gc_state_get "$gv_state" approvedPhases 2>/dev/null | tr -d '[]",') " in *" release "*) gv_rel_ok=1 ;; esac
            if [ "$gv_tier" != "trivial" ] && ! { [ "$gv_tier" = "emergency" ] && [ "$gv_rel_ok" = 1 ]; }; then
              if [ "$gv_cur" != "maintain/$gv_feature" ]; then
                gc_refuse "$gv_step" "verify for maintenance note '$gv_feature' must run on branch 'maintain/$gv_feature' (current branch: '${gv_cur:-detached}')"
              fi
            fi
          else
            if [ "$gv_cur" != "feature/$gv_feature" ]; then
              gv_wt="$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/feature/${gv_feature}" '
                /^worktree / { path = substr($0, 10) }
                $0 == want { print path; exit }
              ')"
              if [ -n "$gv_wt" ]; then
                gc_refuse "$gv_step" "verify for '$gv_feature' must run in worktree '$gv_wt' on branch 'feature/$gv_feature' (current branch: '${gv_cur:-detached}'). Open that folder and run /v0-verify $gv_feature there"
              else
                gc_refuse "$gv_step" "no 'feature/$gv_feature' branch or worktree exists (current branch: '${gv_cur:-detached}'); complete /v0-intake $gv_feature (approve + guard-intake.sh commit $gv_feature) first"
              fi
            fi
          fi
        fi
        ;;
      pack-configured)
        if [ -f "docs/agents-v0/project-profile.md" ] && [ -d ".agents-v0/packs" ]; then
          gv_pack="$(awk -F'|' '
            function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
            tolower($0) ~ /\|[ \t]*pack[ \t]*\|/ {
              v = trim($3)
              gsub(/<!--.*-->/, "", v)
              v = trim(v)
              if (v != "" && v !~ /^</) { print v; exit }
            }
          ' docs/agents-v0/project-profile.md)"
          if [ -n "$gv_pack" ] && [ ! -f ".agents-v0/packs/$gv_pack/pack.json" ]; then
            gc_refuse "$gv_step" "project-profile.md names Pack '$gv_pack', but '.agents-v0/packs/$gv_pack/pack.json' is missing"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gv_state" ]; then
          gv_tier="$(gc_state_get "$gv_state" tier 2>/dev/null || true)"
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              if [ "$gv_is_maintain" = 1 ] && [ "$gv_tier" = "emergency" ]; then
                case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
                  *" verify "*) gc_refuse "$gv_step" "emergency maintenance note '$gv_feature' already has release and verify approved; start a new maintenance id" ;;
                esac
              else
                gc_refuse "$gv_step" "story '$gv_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              fi
              ;;
          esac
        fi
        ;;
      build-approved)
        [ -f "$gv_req_art" ] \
          || gc_refuse "$gv_step" "primary artifact '$gv_req_art' is missing; complete /v0-intake, /v0-design, and /v0-build $gv_feature first"
        [ -f "$gv_state" ] \
          || gc_refuse "$gv_step" "state file '$gv_state' is missing; complete /v0-intake, /v0-design, and /v0-build $gv_feature first"
        if [ "$gv_is_maintain" = 1 ]; then
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" maintain "*) ;;
            *) gc_refuse "$gv_step" "maintain is not in approvedPhases in '$gv_state'; complete /v0-maintain $gv_feature first" ;;
          esac
        else
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" build "*) ;;
            *) gc_refuse "$gv_step" "build is not in approvedPhases in '$gv_state'; complete /v0-build $gv_feature first" ;;
          esac
          gv_bgm="$(gc_state_get "$gv_state" buildGuardManaged 2>/dev/null || true)"
          if [ "$gv_bgm" = "True" ] || [ "$gv_bgm" = "true" ]; then
            if ! gv_bld_ok="$(gc_approval_ok build "$gv_feature")"; then
              gc_refuse "$gv_step" "external build approval record missing or mismatched ($gv_bld_ok); complete /v0-build $gv_feature first"
            fi
          fi
        fi
        gv_skip_cc=0
        # >>> kit-test-override (kitfix-20261031-installed-no-overrides: install.sh removes this block; kit test copies only)
        [ "${AGENTS_V0_SKIP_COMMIT_CHECK:-0}" != 1 ] || gv_skip_cc=1
        # <<< kit-test-override
        if [ "$gv_skip_cc" != 1 ] && [ -f "$GC_HERE/check-gate-commit.sh" ] && [ "$gv_reopen" != 1 ]; then
          gv_prev_act="$(gc_state_get "$gv_state" activePhase 2>/dev/null || true)"
          if [ -z "$gv_prev_act" ]; then
            if ! gv_cc_out="$(sh "$GC_HERE/check-gate-commit.sh" "$gv_req_art" 2>&1)"; then
              gc_refuse "$gv_step" "build gate is not committed on feature/$gv_feature: $gv_cc_out"
            fi
          fi
        fi
        ;;
      not-approved)
        if [ "$gv_reopen" != 1 ] && [ -f "$gv_state" ]; then
          case " $(gc_state_get "$gv_state" approvedPhases | tr -d '[]",') " in
            *" $gv_phase "*)
              gc_refuse "$gv_step" "verify is already approved for '$gv_feature'; suggest $gv_approved_next (or pass --reopen to reopen verify)"
              ;;
          esac
        fi
        if [ "$gv_reopen" = 1 ] && [ -f "$gv_state" ]; then
          gv_rc="$(gc_state_get "$gv_state" reopenCount 2>/dev/null || echo 0)"
          case "$gv_rc" in ''|*[!0-9]*) gv_rc=0 ;; esac
          if [ "$gv_rc" -ge 3 ]; then
            gc_refuse "$gv_step" "reopen bounce cap exceeded for '$gv_feature' (reopenCount=$gv_rc >= 3); escalate to Sensei before reopening again"
          fi
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gv_state" ]; then
          [ "$(gc_state_get "$gv_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gv_step" "verify for '$gv_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve verify $gv_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gv_state" ] || gc_refuse "$gv_step" "verify for '$gv_feature' has not been started; run $G start $gv_feature first"
        [ "$(gc_state_get "$gv_state" activePhase)" = "$gv_phase" ] \
          || gc_refuse "$gv_step" "activePhase for '$gv_feature' is '$(gc_state_get "$gv_state" activePhase)', not '$gv_phase'; run $G start $gv_feature first"
        [ "$(gc_state_get "$gv_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gv_step" "verify for '$gv_feature' is not in_progress (status: $(gc_state_get "$gv_state" activeStatus)); run $G start $gv_feature first"
        ;;
      *) gc_refuse "$gv_step" "gate-rules names an unknown prerequisite '$gv_req'; reinstall the kit" ;;
    esac
  done
}

gv_check() {
  gv_c_slug=""
  gv_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --reopen)
        gv_c_reopen=1
        shift
        ;;
      -*)
        gv_usage
        ;;
      *)
        [ -z "$gv_c_slug" ] || gv_usage
        gv_c_slug="$1"
        shift
        ;;
    esac
  done

  gv_load check "$gv_c_slug"
  gv_rule check check.requires "$gv_feature"; gv_requires="$gv_val"
  gv_check_prereqs check "$gv_requires" "$gv_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-verify $gv_feature"
  if [ "$gv_c_reopen" = 1 ]; then
    printf 'Next: Start reopened verify with: %s start %s --reopen\n' "$G" "$gv_feature"
  else
    printf 'Next: Start verify with: %s start %s\n' "$G" "$gv_feature"
  fi
}

cmd="${1:-}"
[ -n "$cmd" ] || gv_usage
shift || true

case "$cmd" in
  check) gv_check "$@" ;;
  *) gv_usage ;;
esac
