#!/bin/sh
# guard-onboard.sh: the steps of /v0-onboard and onboard's own rules (onboard redo, Design: D2;
# kit-eval/reviews/jiraiya-onboard-redo-design-20261102.md, "The split"). Paths and prerequisites come from
# .agents-v0/gate-rules (the `onboard` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. D2 builds `start` and `block`, D3 `ready`, D4 `commit`, D5 `steps`; `reopen` comes later.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-onboard.sh start
#        begin or resume onboarding: checks the prerequisites, copies the report template when report.md is
#        missing, and sets the onboard state to in_progress (docs/agents-v0/onboarding/state.json).
#   sh .agents-v0/scripts/guard-onboard.sh block "<plain reason>" [--next "<next step>"]
#        stop onboarding: sets the state to blocked and records the reason and the next step
#        (the gate-rules default when --next is not given).
#   sh .agents-v0/scripts/guard-onboard.sh ready
#        (Design: D3; main session only, after discovery) runs the baseline audit with --record, which writes
#        docs/agents-v0/discovery/baseline-audit.txt (a red baseline is recorded, not refused), runs the
#        onboarding docs check, then sets the onboard state to awaiting_approval for Sensei's approve step.
#   sh .agents-v0/scripts/guard-onboard.sh commit
#        (Design: D4; main session only, after Sensei ran approve in his own terminal) needs onboard approved in
#        the state AND his approval record, then makes the one gate commit of the onboard paths (secret-scanned)
#        and tags it onboard-v<n> (guard-common.sh gc_commit_tag).
#   sh .agents-v0/scripts/guard-onboard.sh steps
#        (Design: D5) prints the /v0-onboard step list; the command prose carries it as a generated block.
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

go_ready() {
  [ $# -eq 0 ] || go_usage
  go_load ready
  go_rule ready ready.requires; go_requires="$go_val"
  for go_req in $go_requires; do
    case "$go_req" in
      in-progress)
        go_cur="$(gc_state_get "$go_state" activeStatus)"
        [ "$go_cur" = in_progress ] \
          || gc_refuse ready "onboarding is not in progress (state: ${go_cur:-none}); run start first" ;;
      *) gc_refuse ready "gate-rules names an unknown prerequisite '$go_req'; reinstall the kit (install.sh --update)" ;;
    esac
  done
  go_rule ready ready.baseline; go_baseline="$go_val"
  [ -f .agents-v0/scripts/audit-brownfield-baseline.sh ] \
    || gc_refuse ready ".agents-v0/scripts/audit-brownfield-baseline.sh is missing; reinstall the kit (install.sh --update)"
  # The audit's own exit (0 passed, 1 failed, 2 no build) is in the record; only a missing record refuses.
  go_rc=0
  sh .agents-v0/scripts/audit-brownfield-baseline.sh --record || go_rc=$?
  { [ "$go_rc" -le 2 ] && [ -f "$go_baseline" ]; } \
    || gc_refuse ready "the baseline audit did not write $go_baseline (exit $go_rc); fix it, then run ready again"
  go_result="$(sed -n 's/^result: //p' "$go_baseline" | head -n 1)"
  sh .agents-v0/scripts/check-onboarding-docs.sh \
    || gc_refuse ready "the onboarding docs check failed; fix the docs it names, then run ready again"
  go_rule ready ready.next; go_next="$go_val"
  go_rule ready ready.status; go_status="$go_val"
  gc_state_set "$go_state" "$go_feature" "$go_artifact" "activePhase=$go_phase" \
    "activeStatus=$go_status" "blockedReason=" "nextStep=$go_next" || exit 1
  gc_ok ready "onboard state is $(gc_state_get "$go_state" activeStatus) (baseline ${go_result:-unknown}, $go_baseline)"
  printf 'Next: %s\n' "$go_next"
}

go_commit() {
  [ $# -eq 0 ] || go_usage
  go_load commit
  # Both checks: the state says approved AND Sensei's record matches (approve writes the record before the state).
  case " $(gc_state_get "$go_state" approvedPhases | tr -d '[]",') " in
    *" $go_phase "*) ;;
    *) gc_refuse commit "onboarding is not approved in $go_state; Sensei runs approve in his own terminal first" ;;
  esac
  go_ok_out="$(gc_approval_ok onboard)" || {
    printf '%s\n' "$go_ok_out"
    gc_refuse commit "no approval record from Sensei matches this onboarding; Sensei runs approve in his own terminal"
  }
  printf '%s\n' "$go_ok_out"
  gc_commit_tag onboard
  go_rule commit approved.next
  printf 'Next: %s\n' "$go_val"
}

# go_steps (Design: D5): print the /v0-onboard step list. scripts/generate-onboard-steps.sh copies this output, byte for
# byte, into the generated block of core/common/commands/v0-onboard.md. No git, no state: it only prints.
go_steps() {
  [ $# -eq 0 ] || go_usage
  go_rule steps ready.next; go_ready_next="$go_val"
  go_rule steps approved.next; go_approved_next="$go_val"
  G='sh .agents-v0/scripts/guard-onboard.sh'
  cat <<EOF_STEPS
1. Run \`$G start\`. It begins or resumes onboarding and sets the state to \`in_progress\`. When it prints \`REFUSED\`, show its message and stop.
2. Run the inventories: \`sh .agents-v0/scripts/generate-repo-map.sh\`, \`sh .agents-v0/scripts/collect-dependency-graphs.sh\` and \`sh .agents-v0/scripts/discover-codebase.sh\`. When the profile \`Pack\` cell is empty or a placeholder, run \`sh .agents-v0/scripts/activate-stack-pack.sh --detect\`: exit 2 keeps the existing pack (no \`--force\` unless the user confirms a replacement), exit 3 asks the user for the pack id.
3. List the discovered modules. Ask the user which are in scope and which flows (up to three) need sequence diagrams. Do not guess.
4. Launch the \`codebase-documenter\` subagent (skill: \`onboard-discovery\`) with the scope answers. It reads code and writes the onboarding docs; it runs no commands. For each \`docs/agents-v0/onboarding/<module>.helper-brief.md\` it writes, launch one \`explore-researcher\` from this session and pass its result back.
5. On a blocker, run \`$G block "<plain reason>"\` and stop.
6. When the documenter reports the docs done, run \`$G ready\`. It records the baseline audit, runs the onboarding docs check and sets the state to \`awaiting_approval\`. When it prints \`REFUSED\`, have the documenter fix what it names, then run \`ready\` again.
7. Stop. Present the onboarding report, its open questions and the triage list. Next: $go_ready_next. Never run approve yourself.
8. After the user says approve ran, run \`$G commit\`. It checks the approval, secret-scans and makes the one onboard commit with its \`onboard-v<n>\` tag. Then suggest: $go_approved_next.
EOF_STEPS
}

go_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-onboard.sh start | block "<plain reason>" [--next "<next step>"] | ready | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || go_usage
go_cmd="$1"; shift
case "$go_cmd" in
  start) go_start "$@" ;;
  block) go_block "$@" ;;
  ready) go_ready "$@" ;;
  commit) go_commit "$@" ;;
  steps) go_steps "$@" ;;
  -h|--help) sed -n '2,26p' "$GO_HERE/guard-onboard.sh" ;;
  *) go_usage ;;
esac
