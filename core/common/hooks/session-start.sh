#!/bin/sh
# session-start.sh — inject delivery context at session start (read-only).
set -eu
# kitfix-20261031-jn4 (M-1): the hooks run the system tools only. PATH comes from the IDE, which takes it from the
#   login shell and its start-up files, so an agent-written ~/.local/bin/cat or a PATH line in ~/.bashrc would
#   otherwise run inside the hook (Sakura's fake-cat repro). Set before the first command (dirname).
PATH=/usr/bin:/bin
export PATH

. "$(dirname "$0")/lib.sh"

lines=""
[ -f docs/agents-v0/project-profile.md ] && lines="${lines}Project profile: docs/agents-v0/project-profile.md
"
[ -f docs/agents-v0/repo-map.md ] && lines="${lines}Repo map: docs/agents-v0/repo-map.md
"

state_summaries="$(hook_py - <<'PY'
import glob, json

paths = (
    ["docs/agents-v0/program.state.json", "docs/agents-v0/onboarding/state.json"]
    + sorted(glob.glob("docs/agents-v0/requirements/*.state.json"))
    + sorted(glob.glob("docs/agents-v0/maintain/*/state.json"))
)
for p in paths:
    try:
        d = json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    last_app = d.get("lastApprovedPhase") or ""
    active_phase = d.get("activePhase") or ""
    active_status = d.get("activeStatus") or ""
    ts = d.get("updatedAt") or ""
    if last_app == "release" and not active_phase:
        continue
    print(f"Active state: {p} lastApproved={last_app} activePhase={active_phase} activeStatus={active_status} updatedAt={ts}")
PY
)"

if [ -n "$state_summaries" ]; then
  lines="${lines}${state_summaries}
"
fi
[ -f .agents-kit-version ] && lines="${lines}Kit version: $(cat .agents-kit-version)
"

[ -n "$lines" ] || exit 0

hook_emit_session_context "Delivery kit session context:
$lines
Use /v0-status to resume gated work. Follow workflow-orchestration.mdc."
exit 0
