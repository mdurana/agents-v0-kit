#!/bin/sh
# guard-onboard.sh: the steps of /v0-onboard and onboard's own rules (onboard redo, Design: D2;
# kit-eval/reviews/jiraiya-onboard-redo-design-20261102.md, "The split"). Paths and prerequisites come from
# .agents-v0/gate-rules (the `onboard` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. D2 builds `start` and `block`; `ready`, `commit` and `reopen` come with D3, D4 and later.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-onboard.sh start
#        begin or resume onboarding: checks the prerequisites, copies the report template when report.md is
#        missing, and sets the onboard state to in_progress (docs/agents-v0/onboarding/state.json).
#   sh .agents-v0/scripts/guard-onboard.sh block "<plain reason>" [--next "<next step>"]
#        stop onboarding: sets the state to blocked and records the reason and the next step
#        (the gate-rules default when --next is not given).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GO_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GO_HERE/guard-common.sh" ] || {
  printf 'REFUSED onboard: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GO_HERE"
  exit 1
}
GC_HERE="$GO_HERE"
GUARD_COMMON_LIB=1
. "$GO_HERE/guard-common.sh"

# go_rule <step> <key>: set go_val to the onboard rule <key> from gate-rules, or refuse <step> (fail closed).
# Sets a variable instead of printing, so a refusal is never swallowed by a $(...) subshell.
go_rule() {
  go_val="$(gc_rule onboard "$2")" \
    || gc_refuse "$1" "gate-rules has no 'onboard $2' rule; reinstall the kit (install.sh --update)"
}

go_load() {
  gc_to_root "$1"
  go_rule "$1" state; go_state="$go_val"
  go_rule "$1" phase; go_phase="$go_val"
  go_rule "$1" feature; go_feature="$go_val"
  go_rule "$1" artifact; go_artifact="$go_val"
}

go_start() {
  [ $# -eq 0 ] || go_usage
  go_load start
  go_rule start start.requires; go_requires="$go_val"
  go_rule start approved.next; go_approved_next="$go_val"
  for go_req in $go_requires; do
    case "$go_req" in
      git-work-tree) ;;  # gc_to_root already refused outside a work tree
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse start "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      not-approved)
        case " $(gc_state_get "$go_state" approvedPhases | tr -d '[]",') " in
          *" $go_phase "*) gc_refuse start "onboarding is already approved; do not start it again. Next: $go_approved_next" ;;
        esac ;;
      not-awaiting-approval)
        [ "$(gc_state_get "$go_state" activeStatus)" != awaiting_approval ] \
          || gc_refuse start "onboarding is awaiting Sensei's approval; wait for it, do not start again" ;;
      *) gc_refuse start "gate-rules names an unknown prerequisite '$go_req'; reinstall the kit (install.sh --update)" ;;
    esac
  done
  go_rule start template; go_template="$go_val"
  if [ ! -f "$go_artifact" ] && [ -f "$go_template" ]; then
    mkdir -p "$(dirname "$go_artifact")"
    cp "$go_template" "$go_artifact"
  fi
  go_rule start start.next; go_next="$go_val"
  go_rule start start.status; go_status="$go_val"
  gc_state_set "$go_state" "$go_feature" "$go_artifact" "activePhase=$go_phase" \
    "activeStatus=$go_status" "blockedReason=" "nextStep=$go_next" || exit 1
  gc_ok start "onboard state is $(gc_state_get "$go_state" activeStatus) ($go_state)"
  printf 'Next: %s\n' "$go_next"
}

go_block() {
  [ $# -ge 1 ] && [ -n "$1" ] || go_usage
  go_reason="$1"; shift
  go_next=""
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --next ] && [ -n "$2" ] || go_usage
    go_next="$2"
  fi
  go_load block
  if [ -z "$go_next" ]; then go_rule block block.next; go_next="$go_val"; fi
  go_rule block block.status; go_status="$go_val"
  gc_state_set "$go_state" "$go_feature" "$go_artifact" "activePhase=$go_phase" \
    "activeStatus=$go_status" "blockedReason=$go_reason" "nextStep=$go_next" || exit 1
  gc_ok block "onboard state is $(gc_state_get "$go_state" activeStatus): $go_reason"
  printf 'Next: %s\n' "$go_next"
}

go_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-onboard.sh start | block "<plain reason>" [--next "<next step>"]\n' >&2
  exit 2
}

[ $# -ge 1 ] || go_usage
go_cmd="$1"; shift
case "$go_cmd" in
  start) go_start "$@" ;;
  block) go_block "$@" ;;
  -h|--help) sed -n '2,16p' "$GO_HERE/guard-onboard.sh" ;;
  *) go_usage ;;
esac
