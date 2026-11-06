#!/bin/sh
# guard-scaffold.sh — single entry point and security boundary for /v0-scaffold.
# Usage:
#   sh .agents-v0/scripts/guard-scaffold.sh check
#   sh .agents-v0/scripts/guard-scaffold.sh start
#   sh .agents-v0/scripts/guard-scaffold.sh block "<reason>"
#   sh .agents-v0/scripts/guard-scaffold.sh ready
#   sh .agents-v0/scripts/guard-scaffold.sh commit
#   sh .agents-v0/scripts/guard-scaffold.sh steps
#
# Design: DS1 (/v0-scaffold guard and greenfield platform skeleton baseline).
set -eu

GC_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
GUARD_COMMON_LIB=1
. "$GC_HERE/guard-common.sh"

G="sh .agents-v0/scripts/guard-scaffold.sh"

gs_usage() {
  printf 'usage: %s check\n' "$G" >&2
  printf '       %s start\n' "$G" >&2
  printf '       %s block "<plain reason>"\n' "$G" >&2
  printf '       %s ready\n' "$G" >&2
  printf '       %s commit\n' "$G" >&2
  printf '       %s steps\n' "$G" >&2
  exit 2
}

gs_rule() {
  gs_step="$1"
  gs_key="$2"
  gs_rules="${GC_HERE}/../gate-rules"
  [ -f "$gs_rules" ] || gc_refuse "$gs_step" "missing gate-rules file ($gs_rules)"
  gs_val="$(awk -v p="scaffold" -v k="$gs_key" '$1 == p && $2 == k { for (i=3; i<=NF; i++) printf "%s%s", $i, (i<NF?" ":""); print "" }' "$gs_rules")"
  [ -n "$gs_val" ] || gc_refuse "$gs_step" "gate-rules missing key '$gs_key' for phase 'scaffold'"
}

gs_load() {
  gs_step="$1"
  gc_to_root "$gs_step"
  gs_rule "$gs_step" phase; gs_phase="$gs_val"
  gs_rule "$gs_step" feature; gs_feature="$gs_val"
  gs_rule "$gs_step" state; gs_state="$gs_val"
  gs_rule "$gs_step" artifact; gs_artifact="$gs_val"
}

gs_is_brownfield() {
  [ -f docs/agents-v0/onboarding/state.json ] && return 0
  [ -d docs/agents-v0/onboarding ] && return 0
  if [ -f docs/agents-v0/program.state.json ]; then
    case " $(gc_state_get docs/agents-v0/program.state.json approvedPhases | tr -d '[]",') " in
      *" onboard "*) return 0 ;;
    esac
  fi
  return 1
}

gs_check_prereqs() {
  gs_step="$1"
  gs_reqs="$2"
  gs_rule "$gs_step" approved.next; gs_approved_next="$gs_val"

  for gs_req in $gs_reqs; do
    case "$gs_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gs_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      greenfield-only)
        if gs_is_brownfield; then
          gc_refuse "$gs_step" "brownfield codebase detected; run /v0-onboard instead (scaffold is for greenfield projects only)"
        fi
        ;;
      plan-approved)
        [ -f "$gs_state" ] || gc_refuse "$gs_step" "no program state ($gs_state); complete /v0-roadmap, /v0-architecture, and /v0-plan first"
        case " $(gc_state_get "$gs_state" approvedPhases | tr -d '[]",') " in
          *" plan "*) ;;
          *) gc_refuse "$gs_step" "plan is not in approvedPhases in $gs_state; complete /v0-plan first" ;;
        esac
        if ! gs_plan_ok="$(gc_approval_ok plan)"; then
          gc_refuse "$gs_step" "external plan approval record missing or mismatched ($gs_plan_ok); complete /v0-plan and have Sensei approve it first"
        fi
        ;;
      integration-branch)
        gs_ib="main"
        if [ -x .agents-v0/scripts/resolve-integration-branch.sh ]; then
          gs_ib="$(sh .agents-v0/scripts/resolve-integration-branch.sh 2>/dev/null || echo main)"
        fi
        gs_cur="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
        if [ -n "$gs_cur" ] && [ "$gs_cur" != "$gs_ib" ]; then
          gc_refuse "$gs_step" "scaffold must run on the integration branch ($gs_ib); current branch is '$gs_cur'. Run git checkout $gs_ib first"
        fi
        ;;
      not-approved)
        if [ -f "$gs_state" ]; then
          case " $(gc_state_get "$gs_state" approvedPhases | tr -d '[]",') " in
            *" $gs_phase "*) gc_refuse "$gs_step" "scaffold is already approved; suggest $gs_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gs_state" ]; then
          [ "$(gc_state_get "$gs_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gs_step" "scaffold is awaiting Sensei's approval; run sh .agents-v0/scripts/guard-common.sh approve scaffold in your external terminal"
        fi
        ;;
      in-progress)
        [ -f "$gs_state" ] || gc_refuse "$gs_step" "scaffold has not been started; run $G start first"
        [ "$(gc_state_get "$gs_state" activePhase)" = "$gs_phase" ] \
          || gc_refuse "$gs_step" "activePhase is '$(gc_state_get "$gs_state" activePhase)', not '$gs_phase'; run $G start first"
        [ "$(gc_state_get "$gs_state" activeStatus)" = in_progress ] \
          || gc_refuse "$gs_step" "scaffold is not in_progress (status: $(gc_state_get "$gs_state" activeStatus)); run $G start first"
        ;;
      *) gc_refuse "$gs_step" "gate-rules names an unknown prerequisite '$gs_req'; reinstall the kit" ;;
    esac
  done
}

gs_check() {
  [ $# -eq 0 ] || gs_usage
  gs_load check
  gs_rule check check.requires; gs_requires="$gs_val"
  gs_check_prereqs check "$gs_requires"

  gc_ok check "prerequisites satisfied for /v0-scaffold"
  printf 'Next: Start scaffold with: sh .agents-v0/scripts/guard-scaffold.sh start\n'
}

cmd="${1:-}"
case "$cmd" in
  check) shift; gs_check "$@" ;;
  start|block|ready|commit|steps)
    gc_refuse "$cmd" "command '$cmd' not yet fully implemented in DS1" ;;
  *) gs_usage ;;
esac
