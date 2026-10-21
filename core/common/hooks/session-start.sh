#!/bin/sh
# session-start.sh — inject delivery context at session start (read-only).
set -eu

. "$(dirname "$0")/lib.sh"

lines=""
[ -f docs/agents-v0/project-profile.md ] && lines="${lines}Project profile: docs/agents-v0/project-profile.md
"
[ -f docs/agents-v0/repo-map.md ] && lines="${lines}Repo map: docs/agents-v0/repo-map.md
"

state_summaries=""
for f in docs/agents-v0/program.state.json docs/agents-v0/onboarding/state.json docs/agents-v0/requirements/*.state.json docs/agents-v0/maintain/*/state.json; do
  [ -f "$f" ] || continue
  last_app="$(sed -n 's/.*"lastApprovedPhase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
  active_phase="$(sed -n 's/.*"activePhase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
  active_status="$(sed -n 's/.*"activeStatus"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
  ts="$(sed -n 's/.*"updatedAt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
  state_summaries="${state_summaries}Active state: $f lastApproved=${last_app:-} activePhase=${active_phase:-} activeStatus=${active_status:-} updatedAt=${ts:-}
"
done

if [ -n "$state_summaries" ]; then
  lines="${lines}${state_summaries}"
fi
[ -f .agents-kit-version ] && lines="${lines}Kit version: $(cat .agents-kit-version)
"

[ -n "$lines" ] || exit 0

hook_emit_session_context "Delivery kit session context:
$lines
Use /v0-status to resume gated work. Follow workflow-orchestration.mdc."
exit 0
