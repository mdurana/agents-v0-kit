#!/bin/sh
# session-start.sh — inject delivery context at session start (read-only).
set -eu

. "$(dirname "$0")/lib.sh"

lines=""
[ -f docs/project-profile.md ] && lines="${lines}Project profile: docs/project-profile.md
"
[ -f docs/repo-map.md ] && lines="${lines}Repo map: docs/repo-map.md
"
state=""
newest_ts=""
if [ -d docs/requirements ]; then
  for f in docs/requirements/*.state.json; do
    [ -f "$f" ] || continue
    ts="$(sed -n 's/.*"updatedAt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1)"
    if [ -z "$state" ]; then
      state="$f"
      newest_ts="$ts"
      continue
    fi
    latest="$(printf '%s\n%s\n' "$newest_ts" "$ts" | sort | tail -n 1)"
    if [ "$latest" = "$ts" ] && [ "$ts" != "$newest_ts" ]; then
      state="$f"
      newest_ts="$ts"
    fi
  done
fi
if [ -n "$state" ]; then
  active_phase="$(sed -n 's/.*"activePhase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state" | head -n 1)"
  active_status="$(sed -n 's/.*"activeStatus"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state" | head -n 1)"
  lines="${lines}Active state: $state activePhase=${active_phase:-} activeStatus=${active_status:-} updatedAt=${newest_ts:-}
"
fi
[ -f .agents-kit-version ] && lines="${lines}Kit version: $(cat .agents-kit-version)
"

[ -n "$lines" ] || exit 0

hook_emit_session_context "Delivery kit session context:
$lines
Use /status to resume gated work. Follow workflow-orchestration.mdc."
exit 0
