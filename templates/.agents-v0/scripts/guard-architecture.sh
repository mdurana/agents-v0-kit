#!/bin/sh
# guard-architecture.sh: the steps of /v0-architecture and architecture's own rules (DA1 to DA8, DAA;
# kit-eval/proposals/sai-architecture-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `architecture` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DA1 builds `check`, DA2 `start`/`block`, DA3 `ready`, DA5 `commit`, DA6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-architecture.sh check
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        roadmap externally approved via gc_approval_ok roadmap, architecture not already approved).
#   sh .agents-v0/scripts/guard-architecture.sh start
#        begin or resume architecture: ensures architecture templates exist, sets status in_progress (DA2).
#   sh .agents-v0/scripts/guard-architecture.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DA2).
#   sh .agents-v0/scripts/guard-architecture.sh ready
#        verifies architecture pack completeness, Pattern ADR with Pack: <id>, and zero Open findings
#        in architecture-review.md, writes architecture.phase-result.md, sets awaiting_approval (DA3).
#   sh .agents-v0/scripts/guard-architecture.sh commit
#        verifies Sensei approval record, promotes ADR to Accepted, writes Approved row, runs
#        activate-stack-pack.sh, stages architecture paths, secret-scans, commits, tags (DA5).
#   sh .agents-v0/scripts/guard-architecture.sh steps
#        prints the step list for /v0-architecture command prose (DA6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GA_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GA_HERE/guard-common.sh" ] || {
  printf 'REFUSED architecture: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GA_HERE"
  exit 1
}
GC_HERE="$GA_HERE"
GUARD_COMMON_LIB=1
. "$GA_HERE/guard-common.sh"

# ga_rule <step> <key>: set ga_val to the architecture rule <key> from gate-rules, or refuse <step> (fail closed).
ga_rule() {
  ga_val="$(gc_rule architecture "$2")" \
    || gc_refuse "$1" "gate-rules has no 'architecture $2' rule; reinstall the kit (install.sh --update)"
}

ga_load() {
  gc_to_root "$1"
  ga_rule "$1" state; ga_state="$ga_val"
  ga_rule "$1" phase; ga_phase="$ga_val"
  ga_rule "$1" feature; ga_feature="$ga_val"
  ga_rule "$1" artifact; ga_artifact="$ga_val"
}

# ga_is_brownfield: returns 0 if tracked application code exists (FA7)
ga_is_brownfield() {
  ga_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|\.agents|docs|trash|\.git|README\.md|LICENSE|CHANGELOG\.md|\.gitignore|\.cursorignore|\.gitlab|\.gitlab-ci\.yml|\.editorconfig|AGENTS\.md)' | head -n 1 || true)"
  [ -n "$ga_code_files" ]
}

ga_check_prereqs() {
  ga_step="$1"
  ga_reqs="$2"
  ga_rule "$ga_step" approved.next; ga_approved_next="$ga_val"

  for ga_req in $ga_reqs; do
    case "$ga_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse "$ga_step" "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse "$ga_step" "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif ga_is_brownfield; then
          gc_refuse "$ga_step" "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      roadmap-approved)
        [ -f "$ga_state" ] || gc_refuse "$ga_step" "no program state ($ga_state); complete /v0-roadmap first"
        case " $(gc_state_get "$ga_state" approvedPhases | tr -d '[]",') " in
          *" roadmap "*) ;;
          *) gc_refuse "$ga_step" "roadmap is not in approvedPhases in $ga_state; complete /v0-roadmap first" ;;
        esac
        if ! ga_rm_ok="$(gc_approval_ok roadmap)"; then
          gc_refuse "$ga_step" "external roadmap approval record missing or mismatched ($ga_rm_ok); complete /v0-roadmap and have Sensei approve it first"
        fi
        ;;
      not-approved)
        if [ -f "$ga_state" ]; then
          case " $(gc_state_get "$ga_state" approvedPhases | tr -d '[]",') " in
            *" $ga_phase "*) gc_refuse "$ga_step" "architecture is already approved; suggest $ga_approved_next" ;;
          esac
        fi
        ;;
      not-awaiting-approval)
        if [ -f "$ga_state" ]; then
          [ "$(gc_state_get "$ga_state" activeStatus)" != awaiting_approval ] \
            || gc_refuse "$ga_step" "architecture is awaiting Sensei's approval; wait for it, do not start again"
        fi
        ;;
      *) gc_refuse "$ga_step" "gate-rules names an unknown prerequisite '$ga_req'; reinstall the kit" ;;
    esac
  done
}

ga_check() {
  [ $# -eq 0 ] || ga_usage
  ga_load check
  ga_rule check check.requires; ga_requires="$ga_val"
  ga_check_prereqs check "$ga_requires"

  gc_ok check "prerequisites satisfied for /v0-architecture"
  printf 'Next: Start architecture with: sh .agents-v0/scripts/guard-architecture.sh start\n'
}

ga_start() {
  [ $# -eq 0 ] || ga_usage
  ga_load start
  ga_rule start start.requires; ga_requires="$ga_val"
  ga_check_prereqs start "$ga_requires"

  mkdir -p docs/agents-v0/adr docs/agents-v0/design/system/components docs/agents-v0/diagrams/sequences
  if [ ! -f "$ga_artifact" ]; then
    printf '# Architecture\n\n## C4 Context\n\n## C4 Container\n\n## Data flow\n\n## Data models\n\n### Conceptual\n\n### Logical\n\n### Physical\n\n## State machine\n\n## Failure domains and degradation\n\n## MVP and future state\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n' > "$ga_artifact"
  fi
  if [ ! -f docs/agents-v0/network.md ]; then
    printf '# Network & Topology\n\n## Target topology\n' > docs/agents-v0/network.md
  fi

  ga_rule start start.next; ga_next="$ga_val"
  ga_rule start start.status; ga_status="$ga_val"

  gc_state_set "$ga_state" "$ga_feature" "$ga_artifact" "activePhase=$ga_phase" \
    "activeStatus=$ga_status" "blockedReason=" "nextStep=$ga_next" || exit 1
  gc_ok start "architecture state is $(gc_state_get "$ga_state" activeStatus) ($ga_state)"
  printf 'Next: %s\n' "$ga_next"
}

ga_block() {
  [ $# -ge 1 ] && [ -n "$1" ] || ga_usage
  ga_reason="$1"; shift
  ga_next=""
  if [ $# -gt 0 ]; then
    [ $# -eq 2 ] && [ "$1" = --next ] && [ -n "$2" ] || ga_usage
    ga_next="$2"
  fi
  ga_load block
  if [ -z "$ga_next" ]; then ga_rule block block.next; ga_next="$ga_val"; fi
  ga_rule block block.status; ga_status="$ga_val"
  gc_state_set "$ga_state" "$ga_feature" "$ga_artifact" "activePhase=$ga_phase" \
    "activeStatus=$ga_status" "blockedReason=$ga_reason" "nextStep=$ga_next" || exit 1
  gc_ok block "architecture state is $(gc_state_get "$ga_state" activeStatus): $ga_reason"
  printf 'Next: %s\n' "$ga_next"
}

ga_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-architecture.sh check | start | block "<plain reason>" [--next "<next step>"] | ready | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || ga_usage
ga_cmd="$1"; shift
case "$ga_cmd" in
  check) ga_check "$@" ;;
  start) ga_start "$@" ;;
  block) ga_block "$@" ;;
  -h|--help) sed -n '2,24p' "$GA_HERE/guard-architecture.sh" ;;
  *) ga_usage ;;
esac
