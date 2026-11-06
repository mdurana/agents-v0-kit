#!/bin/sh
# guard-intake.sh — single entry point and security boundary for /v0-intake.
# Usage:
#   sh .agents-v0/scripts/guard-intake.sh check <feature> [--tier trivial|emergency|standard|major] [--reopen]
#   sh .agents-v0/scripts/guard-intake.sh start <feature> [--reopen]
#   sh .agents-v0/scripts/guard-intake.sh block <feature> "<reason>"
#   sh .agents-v0/scripts/guard-intake.sh ready <feature>
#   sh .agents-v0/scripts/guard-intake.sh commit <feature>
#   sh .agents-v0/scripts/guard-intake.sh steps
#
# Design: DI1 (/v0-intake guard and parameterized per-story requirements gate).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-intake.sh"

gi_usage() {
  printf 'usage: %s check <feature> [--tier trivial|emergency|standard|major] [--reopen]\n' "$G" >&2
  printf '       %s start <feature> [--reopen]\n' "$G" >&2
  printf '       %s block <feature> "<plain reason>"\n' "$G" >&2
  printf '       %s ready <feature>\n' "$G" >&2
  printf '       %s commit <feature>\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gi_validate_slug() {
  gi_v_step="$1"
  gi_v_slug="${2:-}"
  [ -n "$gi_v_slug" ] || gc_refuse "$gi_v_step" "missing <feature> slug; pass a lowercase slug (e.g. orders-api)"
  case "$gi_v_slug" in
    [a-z0-9]*) ;;
    *) gc_refuse "$gi_v_step" "feature slug '$gi_v_slug' must start with a lowercase letter or digit" ;;
  esac
  case "$gi_v_slug" in
    *[!a-z0-9-]*) gc_refuse "$gi_v_step" "feature slug '$gi_v_slug' may hold only lowercase letters, digits, and hyphens" ;;
  esac
  case "$gi_v_slug" in
    p0-a|p0-a-*)
      gc_refuse "$gi_v_step" "story '$gi_v_slug' is the greenfield platform skeleton; run /v0-scaffold on the integration branch instead of /v0-intake"
      ;;
  esac
}

gi_rule() {
  gi_step="$1"
  gi_key="$2"
  gi_slug="${3:-}"
  gi_rules="${GC_HERE}/../gate-rules"
  [ -f "$gi_rules" ] || gc_refuse "$gi_step" "missing gate-rules file ($gi_rules)"
  gi_val="$(awk -v p="intake" -v k="$gi_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gi_rules")"
  [ -n "$gi_val" ] || gc_refuse "$gi_step" "gate-rules missing key '$gi_key' for phase 'intake'"
  if [ -n "$gi_slug" ]; then
    gi_val="$(printf '%s' "$gi_val" | sed "s/<feature>/$gi_slug/g")"
  fi
}

gi_load() {
  gi_step="$1"
  gi_slug="$2"
  gi_validate_slug "$gi_step" "$gi_slug"
  gc_to_root "$gi_step"
  gi_rule "$gi_step" phase "$gi_slug"; gi_phase="$gi_val"
  gi_rule "$gi_step" feature "$gi_slug"; gi_feature="$gi_val"
  gi_rule "$gi_step" state "$gi_slug"; gi_state="$gi_val"
  gi_rule "$gi_step" artifact "$gi_slug"; gi_artifact="$gi_val"
  gi_rule "$gi_step" result "$gi_slug"; gi_result="$gi_val"
}

gi_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -f docs/agents-v0/onboarding/report.md ] && return 0
  return 1
}

gi_check_prereqs() {
  gi_step="$1"
  gi_reqs="$2"
  gi_reopen="${3:-0}"
  gi_rule "$gi_step" approved.next "$gi_feature"; gi_approved_next="$gi_val"

  for gi_req in $gi_reqs; do
    case "$gi_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gi_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      integration-branch)
        gi_ib="main"
        if [ -x .agents-v0/scripts/resolve-integration-branch.sh ]; then
          gi_ib="$(sh .agents-v0/scripts/resolve-integration-branch.sh 2>/dev/null || echo main)"
          gi_ib="${gi_ib#origin/}"
        fi
        gi_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        if [ -n "$gi_cur" ] && [ "$gi_ib" != "HEAD" ] && [ "$gi_cur" != "$gi_ib" ]; then
          gc_refuse "$gi_step" "intake must start on the integration branch ($gi_ib); current branch is '$gi_cur'. Run git checkout $gi_ib first"
        fi
        ;;
      onboard-if-brownfield)
        if gi_is_brownfield; then
          [ -f docs/agents-v0/onboarding/state.json ] \
            || gc_refuse "$gi_step" "brownfield onboarding state missing (docs/agents-v0/onboarding/state.json); complete /v0-onboard first"
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$gi_step" "brownfield onboarding is not approved in docs/agents-v0/onboarding/state.json; complete /v0-onboard first" ;;
          esac
          if ! gi_onb_ok="$(gc_approval_ok onboard)"; then
            gc_refuse "$gi_step" "external onboard approval record missing or mismatched ($gi_onb_ok); complete /v0-onboard first"
          fi
        fi
        ;;
      plan-if-program)
        if [ -f docs/agents-v0/program.state.json ] || [ -f docs/agents-v0/milestones/plan.md ]; then
          [ -f docs/agents-v0/program.state.json ] \
            || gc_refuse "$gi_step" "program.state.json is missing; complete /v0-plan first"
          case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
            *" plan "*) ;;
            *) gc_refuse "$gi_step" "plan is not in approvedPhases in docs/agents-v0/program.state.json; complete /v0-plan first" ;;
          esac
          if ! gi_plan_ok="$(gc_approval_ok plan)"; then
            gc_refuse "$gi_step" "external plan approval record missing or mismatched ($gi_plan_ok); complete /v0-plan and have Sensei approve it first"
          fi
        fi
        ;;
      scaffold-if-greenfield)
        if ! gi_is_brownfield && [ -f docs/agents-v0/milestones/p0-platform-skeleton.md ]; then
          [ -f docs/agents-v0/program.state.json ] \
            || gc_refuse "$gi_step" "greenfield project has p0-platform-skeleton.md but no program.state.json; complete /v0-scaffold first"
          case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
            *" scaffold "*) ;;
            *) gc_refuse "$gi_step" "scaffold is not in approvedPhases in docs/agents-v0/program.state.json; complete /v0-scaffold on the integration branch before story intake" ;;
          esac
          if ! gi_scaf_ok="$(gc_approval_ok scaffold)"; then
            gc_refuse "$gi_step" "external scaffold approval record missing or mismatched ($gi_scaf_ok); complete /v0-scaffold first"
          fi
        fi
        ;;
      not-released)
        if [ -f "$gi_state" ]; then
          case " $(gc_state_get "$gi_state" approvedPhases | tr -d '[]",') " in
            *" release "*)
              gc_refuse "$gi_step" "story '$gi_feature' is already released; start /v0-maintain for a fix or small change, or /v0-intake with a new feature slug"
              ;;
          esac
        fi
        ;;
      not-approved)
        if [ "$gi_reopen" != 1 ] && [ -f "$gi_state" ]; then
          case " $(gc_state_get "$gi_state" approvedPhases | tr -d '[]",') " in
            *" $gi_phase "*)
              gc_refuse "$gi_step" "intake is already approved for '$gi_feature'; suggest $gi_approved_next (or pass --reopen to reopen intake)"
              ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gi_state" ]; then
          [ "$(gc_state_get "$gi_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gi_step" "intake for '$gi_feature' is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve intake $gi_feature in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gi_state" ] || gc_refuse "$gi_step" "intake for '$gi_feature' has not been started; run $G start $gi_feature first"
        [ "$(gc_state_get "$gi_state" activePhase)" = "$gi_phase" ] \
          || gc_refuse "$gi_step" "activePhase for '$gi_feature' is '$(gc_state_get "$gi_state" activePhase)', not '$gi_phase'; run $G start $gi_feature first"
        [ "$(gc_state_get "$gi_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gi_step" "intake for '$gi_feature' is not in_progress (status: $(gc_state_get "$gi_state" activeStatus)); run $G start $gi_feature first"
        ;;
      *) gc_refuse "$gi_step" "gate-rules names an unknown prerequisite '$gi_req'; reinstall the kit" ;;
    esac
  done
}

gi_check() {
  gi_c_slug=""
  gi_c_tier="standard"
  gi_c_reopen=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier)
        [ $# -ge 2 ] || gi_usage
        gi_c_tier="$2"
        shift 2
        ;;
      --reopen)
        gi_c_reopen=1
        shift
        ;;
      -*)
        gi_usage
        ;;
      *)
        [ -z "$gi_c_slug" ] || gi_usage
        gi_c_slug="$1"
        shift
        ;;
    esac
  done

  # Change-tier classification gate before touching any requirements or state files (FI6)
  case "$gi_c_tier" in
    trivial)
      gc_refuse check "change tier is 'trivial' — route to /v0-triage; do not create docs/agents-v0/requirements/$gi_c_slug.md or its state file"
      ;;
    emergency)
      gc_refuse check "change tier is 'emergency' — route to /v0-maintain; do not create docs/agents-v0/requirements/$gi_c_slug.md or its state file"
      ;;
    standard|major) ;;
    *)
      gc_refuse check "unknown --tier '$gi_c_tier' (expected trivial, emergency, standard, or major)"
      ;;
  esac

  gi_load check "$gi_c_slug"
  gi_rule check check.requires "$gi_feature"; gi_requires="$gi_val"
  gi_check_prereqs check "$gi_requires" "$gi_c_reopen"

  gc_ok check "prerequisites satisfied for /v0-intake $gi_feature (tier: $gi_c_tier)"
  if [ "$gi_c_reopen" = 1 ]; then
    printf 'Next: Start reopened intake with: %s start %s --reopen\n' "$G" "$gi_feature"
  else
    printf 'Next: Start intake with: %s start %s\n' "$G" "$gi_feature"
  fi
}

gi_start() {
  gc_refuse start "not yet implemented (DI2)"
}

gi_block() {
  gc_refuse block "not yet implemented (DI2)"
}

gi_ready() {
  gc_refuse ready "not yet implemented (DI3)"
}

gi_commit() {
  gc_refuse commit "not yet implemented (DI5)"
}

gi_steps() {
  gc_refuse steps "not yet implemented (DI6)"
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gi_check "$@" ;;
  start) shift; gi_start "$@" ;;
  block) shift; gi_block "$@" ;;
  ready) shift; gi_ready "$@" ;;
  commit) shift; gi_commit "$@" ;;
  steps) shift; gi_steps "$@" ;;
  *) gi_usage ;;
esac
