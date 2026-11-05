#!/bin/sh
# guard-plan.sh: the steps of /v0-plan and plan's own rules (DP1 to DP8, DPA;
# kit-eval/proposals/sai-plan-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `plan` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DP1 builds `check`, DP2 `start`/`block`, DP3 `ready`, DP5 `commit`, DP6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-plan.sh check
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        architecture externally approved via gc_approval_ok architecture, plan not already approved).
#   sh .agents-v0/scripts/guard-plan.sh start
#        begin or resume plan: ensures milestones template exists, sets status in_progress (DP2).
#   sh .agents-v0/scripts/guard-plan.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DP2).
#   sh .agents-v0/scripts/guard-plan.sh ready
#        verifies milestone manifests completeness, concrete story sentences, surface, size 1-8,
#        no cycles, cross-context integration stories, writes plan.phase-result.md, sets awaiting_approval (DP3).
#   sh .agents-v0/scripts/guard-plan.sh commit
#        verifies Sensei approval record, appends Approved row to manifests, stages plan paths,
#        secret-scans, commits, tags (DP5).
#   sh .agents-v0/scripts/guard-plan.sh steps
#        prints the step list for /v0-plan command prose (DP6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GP_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GP_HERE/guard-common.sh" ] || {
  printf 'REFUSED plan: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GP_HERE"
  exit 1
}
GC_HERE="$GP_HERE"
GUARD_COMMON_LIB=1
. "$GP_HERE/guard-common.sh"

# gp_rule <step> <key>: set gp_val to the plan rule <key> from gate-rules, or refuse <step> (fail closed).
gp_rule() {
  gp_val="$(gc_rule plan "$2")" \
    || gc_refuse "$1" "gate-rules has no 'plan $2' rule; reinstall the kit (install.sh --update)"
}

gp_load() {
  gc_to_root "$1"
  gp_rule "$1" state; gp_state="$gp_val"
  gp_rule "$1" phase; gp_phase="$gp_val"
  gp_rule "$1" feature; gp_feature="$gp_val"
  gp_rule "$1" artifact; gp_artifact="$gp_val"
}

# gp_is_brownfield: returns 0 if tracked application code exists (FP7)
gp_is_brownfield() {
  gp_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|\.agents|docs|trash|\.git|README\.md|LICENSE|CHANGELOG\.md|\.gitignore|\.cursorignore|\.gitlab|\.gitlab-ci\.yml|\.editorconfig|AGENTS\.md)' | head -n 1 || true)"
  [ -n "$gp_code_files" ]
}

gp_check_prereqs() {
  gp_step="$1"
  gp_reqs="$2"
  gp_rule "$gp_step" approved.next; gp_approved_next="$gp_val"

  for gp_req in $gp_reqs; do
    case "$gp_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$gp_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$gp_step" "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif gp_is_brownfield; then
          gc_refuse "$gp_step" "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      architecture-approved)
        [ -f "$gp_state" ] || gc_refuse "$gp_step" "no program state ($gp_state); complete /v0-roadmap and /v0-architecture first"
        case " $(gc_state_get "$gp_state" approvedPhases | tr -d '[]",') " in
          *" architecture "*) ;;
          *) gc_refuse "$gp_step" "architecture is not in approvedPhases in $gp_state; complete /v0-architecture first" ;;
        esac
        if ! gp_arch_ok="$(gc_approval_ok architecture)"; then
          gc_refuse "$gp_step" "external architecture approval record missing or mismatched ($gp_arch_ok); complete /v0-architecture and have Sensei approve it first"
        fi
        ;;
      not-approved)
        if [ -f "$gp_state" ]; then
          case " $(gc_state_get "$gp_state" approvedPhases | tr -d '[]",') " in
            *" $gp_phase "*) gc_refuse "$gp_step" "plan is already approved; suggest $gp_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$gp_state" ]; then
          [ "$(gc_state_get "$gp_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$gp_step" "plan is awaiting Sensei's approval; wait for it, do not start again"
        fi
        ;;
      *) gc_refuse "$gp_step" "gate-rules names an unknown prerequisite '$gp_req'; reinstall the kit" ;;
    esac
  done
}

gp_check() {
  [ $# -eq 0 ] || gp_usage
  gp_load check
  gp_rule check check.requires; gp_requires="$gp_val"
  gp_check_prereqs check "$gp_requires"

  gc_ok check "prerequisites satisfied for /v0-plan"
  printf 'Next: Start plan with: sh .agents-v0/scripts/guard-plan.sh start\n'
}

gp_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-plan.sh check\n' >&2
  exit 2
}

[ $# -ge 1 ] || gp_usage
gp_cmd="$1"; shift
case "$gp_cmd" in
  check) gp_check "$@" ;;
  -h|--help) sed -n '2,24p' "$GP_HERE/guard-plan.sh" ;;
  *) gp_usage ;;
esac
