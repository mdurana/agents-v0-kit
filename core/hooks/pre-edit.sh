#!/bin/sh
# pre-edit.sh — block writes to protected kit/CI paths (preToolUse / PreToolUse Edit|Write).
set -eu

. "$(dirname "$0")/lib.sh"

payload="$(cat || true)"
path="$(hook_extract_file_path "$payload")"
[ -n "$path" ] || path="$(printf '%s' "$payload" | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
for k in ("file_path","path","filePath"):
    if isinstance(d.get(k),str):
        print(d[k]); raise SystemExit(0)
ti=d.get("tool_input") or d.get("input") or {}
if isinstance(ti,dict):
    for k in ("file_path","path","filePath"):
        if isinstance(ti.get(k),str):
            print(ti[k]); raise SystemExit(0)
' 2>/dev/null || true)"

[ -n "$path" ] || exit 0

if ! command -v python3 >/dev/null 2>&1; then
  printf 'BLOCK: python3 required for path guardrails\n' >&2
  exit 2
fi

result="$(HOOK_PATH="$path" python3 "$(dirname "$0")/hook-policy.py" path 2>/dev/null)" || exit 2
[ -n "$result" ] || exit 2

action="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("action","allow"))')"
message="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))')"

if [ "$action" = "block" ]; then
  hook_audit_log "path" "$path" "block" "$message"
  printf 'BLOCK: %s\n' "$message" >&2
  HOOK_DENY_MSG="$message" python3 -c '
import json, os
msg = os.environ.get("HOOK_DENY_MSG", "")
flavor = os.environ.get("KIT_HOOK_FLAVOR", "cursor")
if flavor == "claude":
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": msg}}))
else:
    print(json.dumps({"permission": "deny", "user_message": msg}))
'
  exit 2
fi

if [ "$action" = "ask" ]; then
  # Cursor accepts "ask" for preToolUse but does not enforce it, so allow there and
  # rely on after-edit.sh context + CI approver binding; Claude Code prompts the user.
  if [ "${KIT_HOOK_FLAVOR:-cursor}" = "claude" ]; then
    hook_audit_log "path" "$path" "ask" "$message"
    agent_msg="ASK: $message"
    user_msg="$message Approve only if a human authorized this change."
    printf '%s\n' "$agent_msg" >&2
    hook_shell_permission_ask "$user_msg" "$agent_msg"
    exit 0
  fi
  hook_audit_log "path" "$path" "allow-flagged" "$message"
fi

hook_shell_permission_allow
exit 0
