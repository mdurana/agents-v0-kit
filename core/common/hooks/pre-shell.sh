#!/bin/sh
# pre-shell.sh — beforeShellExecution guardrail (POSIX sh; tested with dash).
set -eu

. "$(dirname "$0")/lib.sh"

payload="$(cat || true)"
cmd="$(hook_extract_command "$payload")"
[ -n "$cmd" ] || cmd="$(printf '%s' "$payload" | tr -d '\n')"

block() {
  hook_audit_log "shell" "$cmd" "block" "$1"
  printf 'BLOCK: %s\n' "$1" >&2
  HOOK_DENY_MSG="$1" python3 -c 'import json,os; m=os.environ.get("HOOK_DENY_MSG",""); print(json.dumps({"permission":"deny","decision":"deny","reason":m,"user_message":m,"agent_message":"BLOCKED by kit policy: "+m}))' 2>/dev/null || true
  exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
  block "python3 is required for delivery kit shell guardrails (fail-closed)."
fi

# MEM-13: the command's working directory (Cursor "cwd", Antigravity "Cwd"), so hook-policy.py can
# tell whether a write to docs/agents-v0/lessons.md happens in a story worktree.
cmd_cwd="$(printf '%s' "$payload" | hook_json_string_field cwd 2>/dev/null || true)"
[ -n "$cmd_cwd" ] || cmd_cwd="$(printf '%s' "$payload" | hook_json_string_field toolCall.args.Cwd 2>/dev/null || true)"

result="$(HOOK_CMD="$cmd" HOOK_CWD="$cmd_cwd" python3 "$(dirname "$0")/hook-policy.py" shell 2>/dev/null)" || {
  block "shell guardrail failed to run (fail-closed)."
}
[ -n "$result" ] || block "shell guardrail returned empty result (fail-closed)."

action="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("action","block"))' 2>/dev/null || echo block)"
message="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))' 2>/dev/null || echo "guardrail parse error")"

case "$action" in
  block)
    block "$message"
    ;;
  ask)
    agent_msg="ASK: $message"
    user_msg="$message Approve only if you explicitly requested this operation."
    hook_audit_log "shell" "$cmd" "ask" "$message"
    printf '%s\n' "$agent_msg" >&2
    rc=0
    hook_shell_permission_ask "$user_msg" "$agent_msg" "$cmd" || rc=$?
    exit "$rc"
    ;;
esac

hook_audit_log "shell" "$cmd" "allow" ""
hook_shell_permission_allow
exit 0
