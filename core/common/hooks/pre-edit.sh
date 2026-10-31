#!/bin/sh
# pre-edit.sh — block writes to protected kit/CI paths (preToolUse / PreToolUse Edit|Write).
set -eu

. "$(dirname "$0")/lib.sh"

# N-1: checked before the payload is read, so a missing interpreter (no path read) is not an allow.
if [ ! -x "$HOOK_PYTHON" ]; then
  printf 'BLOCK: the hook interpreter %s is missing (path guardrails fail closed)\n' "$HOOK_PYTHON" >&2
  printf '{"permission": "deny", "decision": "deny", "reason": "kit hook interpreter missing (fail-closed)"}\n'
  exit 2
fi

payload="$(cat || true)"
path="$(hook_extract_file_path "$payload")"
[ -n "$path" ] || path="$(printf '%s' "$payload" | hook_py -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
for k in ("file_path","path","filePath","target_file"):
    if isinstance(d.get(k),str):
        print(d[k]); raise SystemExit(0)
ti=d.get("tool_input") or d.get("input") or {}
if isinstance(ti,dict):
    for k in ("file_path","path","filePath","target_file"):
        if isinstance(ti.get(k),str):
            print(ti[k]); raise SystemExit(0)
' 2>/dev/null || true)"

[ -n "$path" ] || exit 0

result="$(HOOK_PATH="$path" hook_py "$HOOK_POLICY_PY" path 2>/dev/null)" || exit 2
[ -n "$result" ] || exit 2

action="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("action","allow"))')"
message="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("message",""))')"

if [ "$action" = "block" ]; then
  hook_audit_log "path" "$path" "block" "$message"
  printf 'BLOCK: %s\n' "$message" >&2
  HOOK_DENY_MSG="$message" hook_py -c '
import json, os
msg = os.environ.get("HOOK_DENY_MSG", "")
print(json.dumps({"permission": "deny", "decision": "deny", "reason": msg, "user_message": msg}))
'
  exit 2
fi

# MEM-13: lessons.md / lessons-archive.md in a story checkout (feature/*, maintain/*) come back as
# "block" above and are denied for both flavors. In the integration checkout they stay "ask", which is
# recorded below and allowed, so the release-manager's file-edit append works without a prompt.
if [ "$action" = "ask" ]; then
  # Cursor accepts "ask" for preToolUse but does not enforce it; rely on after-edit context + CI.
  hook_audit_log "path" "$path" "allow-flagged" "$message"
fi

hook_shell_permission_allow
exit 0
