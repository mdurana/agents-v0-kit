#!/bin/sh
# pre-edit.sh — block writes to protected kit/CI paths (preToolUse / PreToolUse Edit|Write).
set -eu

. "$(dirname "$0")/lib.sh"

# N-1, JN-2/JN-5: checked before the payload is read, so an untrusted or non-working interpreter (missing, not
#   root-owned, a folder, /bin/true: no path read) is not an allow.
[ -z "$HOOK_PYTHON_WHY" ] || hook_deny_literal "kit hook interpreter not trusted: $HOOK_PYTHON_WHY"

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

# JN-5: an empty payload has nothing to judge; a payload with no path we can read is denied, not allowed.
if [ -z "$path" ]; then
  [ -n "$(printf '%s' "$payload" | tr -d ' \t\r\n')" ] || exit 0
  hook_deny_literal "edit payload has no file path the guardrail can read"
fi

result="$(HOOK_PATH="$path" hook_py "$HOOK_POLICY_PY" path 2>/dev/null)" || hook_deny_literal "path guardrail failed to run"
[ -n "$result" ] || hook_deny_literal "path guardrail returned no verdict"

action="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("action","block"))' 2>/dev/null)" || action=block
message="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("message",""))' 2>/dev/null)" || message=""
case "$action" in
  allow|ask) ;;
  *) action=block; [ -n "$message" ] || message="path guardrail returned no verdict (fail-closed)" ;;
esac

if [ "$action" = "block" ]; then
  hook_audit_log "path" "$path" "block" "$message"
  printf 'BLOCK: %s\n' "$message" >&2
  HOOK_DENY_MSG="$message" hook_py -c '
import json, os
msg = os.environ.get("HOOK_DENY_MSG", "")
print(json.dumps({"permission": "deny", "decision": "deny", "reason": msg, "user_message": msg}))
' || hook_deny_literal "$message"
  exit 2
fi

# MEM-13: lessons.md / lessons-archive.md in a story checkout (feature/*, maintain/*) come back as
# "block" above and are denied for both flavors. In the integration checkout they stay "ask", which is
# recorded below and allowed, so the release-manager's file-edit append works without a prompt.
if [ "$action" = "ask" ]; then
  # Cursor accepts "ask" for preToolUse but does not enforce it; rely on after-edit context + CI.
  hook_audit_log "path" "$path" "allow-flagged" "$message"
fi

# JN-5: exit 0 only with the allow line printed; no verdict is a deny (agy has no failClosed).
allow_out="$(hook_shell_permission_allow)"
case "$allow_out" in *'"permission": "allow"'*) printf '%s\n' "$allow_out"; exit 0 ;; esac
hook_deny_literal "path guardrail produced no allow verdict"
