#!/bin/sh
# pre-shell.sh — beforeShellExecution guardrail (POSIX sh; tested with dash).
set -eu
# kitfix-20261031-jn4 (M-1): the hooks run the system tools only. PATH comes from the IDE, which takes it from the
#   login shell and its start-up files, so an agent-written ~/.local/bin/cat or a PATH line in ~/.bashrc would
#   otherwise run inside the hook (Sakura's fake-cat repro). Set before the first command (dirname).
PATH=/usr/bin:/bin
export PATH

. "$(dirname "$0")/lib.sh"

# N-1, JN-2/JN-5: block() prints its JSON with Python, so an untrusted or non-working interpreter (missing, not
#   root-owned, a folder, /bin/true) is denied here with a literal JSON line.
[ -z "$HOOK_PYTHON_WHY" ] || hook_deny_literal "kit hook interpreter not trusted: $HOOK_PYTHON_WHY"
[ -z "$HOOK_ENV_WHY" ] || hook_deny_literal "untrusted preload in the hook environment: $HOOK_ENV_WHY"

payload="$(cat || true)"
cmd="$(hook_extract_command "$payload")"

block() {
  hook_audit_log "shell" "$cmd" "block" "$1"
  printf 'BLOCK: %s\n' "$1" >&2
  HOOK_DENY_MSG="$1" hook_py -c 'import json,os; m=os.environ.get("HOOK_DENY_MSG",""); print(json.dumps({"permission":"deny","decision":"deny","reason":m,"user_message":m,"agent_message":"BLOCKED by kit policy: "+m}))' 2>/dev/null || true
  exit 2
}

# Fail-closed input (Jiraiya, Iruka; Sasuke): no command to judge is a refusal, not an allow. Empty or blank stdin,
#   text that is not JSON, JSON that is not an object ({} [] null "ls" 42), and an object whose "command" (Cursor
#   beforeShellExecution) is missing, empty, blank or not a string all stop here. The raw stdin is no longer judged
#   as a command line: a non-JSON payload used to reach the policy as the command text and could be allowed.
case "$cmd" in
  *[![:space:]]*) ;;
  *) cmd=""; block "the shell hook got no command to judge (stdin empty, not JSON, or no \"command\" string); refusing (fail-closed)." ;;
esac

# MEM-13: the command's working directory (Cursor "cwd", Antigravity "Cwd"), so hook-policy.py can
# tell whether a write to docs/agents-v0/lessons.md happens in a story worktree.
cmd_cwd="$(printf '%s' "$payload" | hook_json_string_field cwd 2>/dev/null || true)"
[ -n "$cmd_cwd" ] || cmd_cwd="$(printf '%s' "$payload" | hook_json_string_field toolCall.args.Cwd 2>/dev/null || true)"

result="$(HOOK_CMD="$cmd" HOOK_CWD="$cmd_cwd" hook_py "$HOOK_POLICY_PY" shell 2>/dev/null)" || {
  block "shell guardrail failed to run (fail-closed)."
}
[ -n "$result" ] || block "shell guardrail returned empty result (fail-closed)."

action="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("action","block"))' 2>/dev/null || echo block)"
message="$(printf '%s' "$result" | hook_py -c 'import json,sys; print(json.load(sys.stdin).get("message",""))' 2>/dev/null || echo "guardrail parse error")"

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
    ask_out="$(hook_shell_permission_ask "$user_msg" "$agent_msg" "$cmd")" || rc=$?
    # JN-5: rc 0 or 2 with a verdict line is passed on; anything else (a crash, no output) is a deny.
    case "$rc:$ask_out" in
      0:*'"permission": "'*|2:*'"permission": "deny"'*) printf '%s\n' "$ask_out"; exit "$rc" ;;
    esac
    hook_deny_literal "ask-level command: the guardrail produced no verdict"
    ;;
esac

hook_audit_log "shell" "$cmd" "allow" ""
# JN-5: exit 0 only with the allow line printed; no verdict is a deny (agy has no failClosed).
allow_out="$(hook_shell_permission_allow)"
case "$allow_out" in *'"permission": "allow"'*) printf '%s\n' "$allow_out"; exit 0 ;; esac
hook_deny_literal "shell guardrail produced no allow verdict"
