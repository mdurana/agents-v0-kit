#!/bin/sh
# guard-roadmap.sh: the steps of /v0-roadmap and roadmap's own rules (DR1 to DR8, DRA;
# kit-eval/proposals/sai-roadmap-redo-design-20261105.md). Paths and prerequisites come from
# .agents-v0/gate-rules (the `roadmap` entry); every state write goes through guard-common.sh (gc_state_set),
# never from this file. DR1 builds `check`, DR2 `validate`, DR3 `start`/`block`/`ready`, DR5 `commit`, DR6 `steps`.
#
# Run (main session, from anywhere in the repository):
#   sh .agents-v0/scripts/guard-roadmap.sh check <discovery-path>
#        verify entry prerequisites (git worktree, kit installed, onboard approved if brownfield,
#        roadmap not already approved, discovery file exists).
#   sh .agents-v0/scripts/guard-roadmap.sh validate <discovery-path> [--refresh]
#        verify 6 mandatory sections without placeholders; compare sha256 on resume (DR2).
#   sh .agents-v0/scripts/guard-roadmap.sh start <discovery-path> [--refresh]
#        begin or resume roadmap: seeds roadmap/<program>.md, sets status in_progress (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh block "<plain reason>" [--next "<next step>"]
#        record blocked state and reason (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh ready <discovery-path>
#        verifies completeness, writes phase-result.md, sets awaiting_approval (DR3).
#   sh .agents-v0/scripts/guard-roadmap.sh commit
#        verifies Sensei approval record, writes Approved row, stages roadmap files, commits, tags (DR5).
#   sh .agents-v0/scripts/guard-roadmap.sh steps
#        prints the step list for /v0-roadmap command prose (DR6).
#
# Output: `OK <step>: ...` then `Next: ...` (exit 0), or `REFUSED <step>: <reason>` (exit 1); usage errors exit 2.
set -eu

GR_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -f "$GR_HERE/guard-common.sh" ] || {
  printf 'REFUSED roadmap: %s/guard-common.sh is missing; reinstall the kit (install.sh --update)\n' "$GR_HERE"
  exit 1
}
GC_HERE="$GR_HERE"
GUARD_COMMON_LIB=1
. "$GR_HERE/guard-common.sh"

# gr_rule <step> <key>: set gr_val to the roadmap rule <key> from gate-rules, or refuse <step> (fail closed).
gr_rule() {
  gr_val="$(gc_rule roadmap "$2")" \
    || gc_refuse "$1" "gate-rules has no 'roadmap $2' rule; reinstall the kit (install.sh --update)"
}

gr_load() {
  gc_to_root "$1"
  gr_rule "$1" state; gr_state="$gr_val"
  gr_rule "$1" phase; gr_phase="$gr_val"
  gr_rule "$1" feature; gr_feature="$gr_val"
  gr_rule "$1" artifact; gr_artifact_dir="$gr_val"
}

# gr_slug <discovery-path>: derive <program> slug from discovery path (T2)
gr_slug() {
  gr_base="$(basename "$1" .md)"
  printf '%s\n' "$gr_base" | sed -E 's/[-_]discovery$//'
}

# gr_artifact <discovery-path>: compute docs/agents-v0/roadmap/<program>.md
gr_artifact() {
  gr_slug_val="$(gr_slug "$1")"
  printf 'docs/agents-v0/roadmap/%s.md\n' "$gr_slug_val"
}

# gr_is_brownfield: returns 0 if tracked application code exists (F7)
gr_is_brownfield() {
  # If git has tracked files outside kit, doc, and config directories, it is brownfield
  gr_code_files="$(git ls-files 2>/dev/null | grep -vE '^(\.agents-v0|\.cursor|docs|trash|\.git|README\.md|LICENSE|\.gitignore|\.editorconfig)' | head -n 1 || true)"
  [ -n "$gr_code_files" ]
}

gr_check() {
  [ $# -ge 1 ] && [ -n "$1" ] || gc_refuse check "no discovery path given; run /v0-roadmap <discovery-path>"
  gr_disc="$1"
  gr_load check

  gr_rule check check.requires; gr_requires="$gr_val"
  gr_rule check approved.next; gr_approved_next="$gr_val"

  for gr_req in $gr_requires; do
    case "$gr_req" in
      git-work-tree) ;; # gc_to_root already checked
      kit-installed)
        [ -f .agents-v0/scripts/guard-common.sh ] && [ -f .agents-v0/gate-rules ] \
          || gc_refuse check "the kit is not installed in this repository (.agents-v0/); run install.sh first" ;;
      onboard-if-brownfield)
        # Check onboard approval record and state (F7)
        if [ -f docs/agents-v0/onboarding/state.json ]; then
          case " $(gc_state_get docs/agents-v0/onboarding/state.json approvedPhases | tr -d '[]",') " in
            *" onboard "*) ;;
            *) gc_refuse check "onboarding is not approved; complete /v0-onboard first" ;;
          esac
        elif gr_is_brownfield; then
          gc_refuse check "existing codebase detected without onboarding approval; run /v0-onboard first"
        fi
        ;;
      not-approved)
        if [ -f "$gr_state" ]; then
          case " $(gc_state_get "$gr_state" approvedPhases | tr -d '[]",') " in
            *" $gr_phase "*) gc_refuse check "roadmap is already approved; suggest $gr_approved_next" ;;
          esac
        fi
        ;;
      *) gc_refuse check "gate-rules names an unknown prerequisite '$gr_req'; reinstall the kit" ;;
    esac
  done

  [ -f "$gr_disc" ] || gc_refuse check "discovery file '$gr_disc' does not exist; check the path"

  gc_ok check "prerequisites satisfied for $gr_disc"
  printf 'Next: Validate the discovery file with: sh .agents-v0/scripts/guard-roadmap.sh validate %s\n' "$gr_disc"
}

gr_validate() {
  gc_refuse validate "validate not yet implemented (scheduled in DR2)"
}

gr_start() {
  gc_refuse start "start not yet implemented (scheduled in DR3)"
}

gr_block() {
  gc_refuse block "block not yet implemented (scheduled in DR3)"
}

gr_ready() {
  gc_refuse ready "ready not yet implemented (scheduled in DR3)"
}

gr_commit() {
  gc_refuse commit "commit not yet implemented (scheduled in DR5)"
}

gr_steps() {
  gc_refuse steps "steps not yet implemented (scheduled in DR6)"
}

gr_usage() {
  printf 'usage: sh .agents-v0/scripts/guard-roadmap.sh check <discovery-path> | validate <discovery-path> [--refresh] | start <discovery-path> [--refresh] | block "<plain reason>" [--next "<next step>"] | ready <discovery-path> | commit | steps\n' >&2
  exit 2
}

[ $# -ge 1 ] || gr_usage
gr_cmd="$1"; shift
case "$gr_cmd" in
  check) gr_check "$@" ;;
  validate) gr_validate "$@" ;;
  start) gr_start "$@" ;;
  block) gr_block "$@" ;;
  ready) gr_ready "$@" ;;
  commit) gr_commit "$@" ;;
  steps) gr_steps "$@" ;;
  -h|--help) sed -n '2,24p' "$GR_HERE/guard-roadmap.sh" ;;
  *) gr_usage ;;
esac
