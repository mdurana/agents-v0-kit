#!/bin/sh
# pre-mcp.sh — beforeMCPExecution / PreToolUse mcp__*: per-server policy (mcp-policy.json).
set -eu

. "$(dirname "$0")/lib.sh"

payload="$(cat || true)"
tool_name="$(printf '%s' "$payload" | hook_json_string_field tool_name)"
[ -n "$tool_name" ] || tool_name="$(printf '%s' "$payload" | hook_json_string_field name)"
server="$(printf '%s' "$payload" | hook_json_string_field mcp_server_name)"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'BLOCK: python3 required for MCP guardrails\n' >&2
  exit 2
fi

# Cursor always sends mcp_server_name; its docs recommend treating a missing name as deny.
# Claude encodes the server in the tool name (mcp__<server>__<tool>), parsed by hook-policy.py.
if [ "${KIT_HOOK_FLAVOR:-cursor}" = "cursor" ] && [ -z "$server" ]; then
  hook_audit_log "mcp" "$tool_name" "block" "missing mcp_server_name"
  printf 'BLOCK: MCP call without mcp_server_name — refusing (fail-closed)\n' >&2
  exit 2
fi

result="$(HOOK_MCP_TOOL="$tool_name" HOOK_MCP_SERVER="$server" python3 "$(dirname "$0")/hook-policy.py" mcp 2>/dev/null)" || exit 2
action="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("action","block"))')"
message="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))')"
subject="${server:+$server/}$tool_name"

case "$action" in
  block)
    hook_audit_log "mcp" "$subject" "block" "$message"
    printf 'BLOCK: %s\n' "$message" >&2
    exit 2
    ;;
  ask)
    hook_audit_log "mcp" "$subject" "ask" "$message"
    hook_shell_permission_ask "$message" "ASK: $message"
    exit 0
    ;;
esac
hook_audit_log "mcp" "$subject" "allow" ""
hook_shell_permission_allow
exit 0
