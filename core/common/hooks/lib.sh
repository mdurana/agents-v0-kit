#!/bin/sh
# lib.sh — shared helpers for Cursor hook scripts (source from hooks/*.sh).
#
# Pack-specific static analysis lives in `.agents-v0/packs/<id>/hooks/pack-scan.sh`
# (shipped from `core/<pack>/hooks/pack-scan.sh`). Authoritative F4 access-control
# evidence is the Verify phase (security-reviewer + vapt-review), not after-edit hook warnings.

# Read hook JSON from stdin; print a string field (supports nested keys with dots).
# Tries common Cursor payload shapes when the top-level key is missing.
hook_json_string_field() {
  field="${1:-}"
  [ -n "$field" ] || return 0
  HOOK_JSON_FIELD="$field" python3 -c '
import json, os, sys

field = os.environ.get("HOOK_JSON_FIELD", "")
raw = sys.stdin.read()
if not raw.strip():
    sys.exit(0)

def dig(data, path):
    cur = data
    for part in path.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur if isinstance(cur, str) else None

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)

value = dig(data, field)
if value:
    print(value, end="")
    sys.exit(0)

leaf = field.split(".")[-1]
for nest in ("tool_input", "input", "payload", "args", "data"):
    inner = data.get(nest)
    if isinstance(inner, dict):
        value = inner.get(leaf)
        if isinstance(value, str):
            print(value, end="")
            sys.exit(0)
' 2>/dev/null || true
}

# Extract shell command from a beforeShellExecution (Cursor) or PreToolUse run_command (Antigravity) payload.
hook_extract_command() {
  cmd="$(printf '%s' "$1" | hook_json_string_field command)"
  if [ -n "$cmd" ]; then
    printf '%s' "$cmd"
    return 0
  fi
  cmd="$(printf '%s' "$1" | hook_json_string_field toolCall.args.CommandLine)"
  if [ -n "$cmd" ]; then
    printf '%s' "$cmd"
    return 0
  fi
  printf '%s' "$1" | hook_json_string_field CommandLine
}

# Extract edited file path from a preToolUse / PreToolUse (Cursor / Antigravity) payload.
hook_extract_file_path() {
  for field in file_path toolCall.args.Path Path path target_file filePath; do
    path="$(printf '%s' "$1" | hook_json_string_field "$field")"
    if [ -n "$path" ]; then
      printf '%s' "$path"
      return 0
    fi
  done
}

# Append-only audit log (gitignored path under .cursor/hooks/ or .agents/hooks/); subjects redacted.
hook_audit_log() {
  event="$1"
  subject="$2"
  decision="$3"
  detail="$4"
  logdir=".cursor/hooks"
  if [ "${KIT_HOOK_FLAVOR:-}" = "antigravity" ]; then
    logdir=".agents/hooks"
  fi
  logfile="$logdir/audit.jsonl"
  mkdir -p "$logdir" 2>/dev/null || return 0
  HOOK_AUDIT_EVENT="$event" HOOK_AUDIT_SUBJECT="$subject" HOOK_AUDIT_DECISION="$decision" HOOK_AUDIT_DETAIL="$detail" \
    python3 -c '
import json, os, re, time

def redact(s):
    if not s:
        return s
    s = re.sub(r"(?i)(authorization|bearer|token|password|api[_-]?key)\s*[=:]\s*[^\s\"]+", r"\1=***", s)
    s = re.sub(r"(?i)(ghp_[a-zA-Z0-9]{20,}|glpat-[a-zA-Z0-9_\-]{20,})", "***_TOKEN", s)
    s = re.sub(r"://[^/@\s]+:[^/@\s]+@", "://***:***@", s)
    return s[:500]

print(json.dumps({
  "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
  "event": os.environ.get("HOOK_AUDIT_EVENT",""),
  "subject": redact(os.environ.get("HOOK_AUDIT_SUBJECT","")),
  "decision": os.environ.get("HOOK_AUDIT_DECISION",""),
  "detail": redact(os.environ.get("HOOK_AUDIT_DETAIL","")),
}))
' >>"$logfile" 2>/dev/null || true
}

# Emit hook output so the agent sees warnings (Cursor afterFileEdit / postToolUse shapes).
hook_emit_additional_context() {
  text="$1"
  [ -n "$text" ] || return 0
  HOOK_CONTEXT_TEXT="$text" python3 -c '
import json, os
text = os.environ.get("HOOK_CONTEXT_TEXT", "")
if not text.strip():
    raise SystemExit(0)
print(json.dumps({"additional_context": text}))
' 2>/dev/null || true
}

# Session start context (Cursor sessionStart / Antigravity SessionStart).
hook_emit_session_context() {
  text="$1"
  [ -n "$text" ] || return 0
  HOOK_CONTEXT_TEXT="$text" HOOK_FLAVOR="${KIT_HOOK_FLAVOR:-cursor}" python3 -c '
import json, os
text = os.environ.get("HOOK_CONTEXT_TEXT", "")
flavor = os.environ.get("HOOK_FLAVOR", "cursor")
if not text.strip():
    raise SystemExit(0)
if flavor == "antigravity":
    print(json.dumps({"injectSteps": [{"systemMessage": {"systemMessage": text}}]}))
else:
    print(json.dumps({"additional_context": text}))
' 2>/dev/null || true
}

# Stop hook: surface reminder as a follow-up when supported.
hook_emit_stop_followup() {
  text="$1"
  [ -n "$text" ] || return 0
  HOOK_FOLLOWUP_TEXT="$text" HOOK_FLAVOR="${KIT_HOOK_FLAVOR:-cursor}" python3 -c '
import json, os
text = os.environ.get("HOOK_FOLLOWUP_TEXT", "")
flavor = os.environ.get("HOOK_FLAVOR", "cursor")
if not text.strip():
    raise SystemExit(0)
if flavor == "antigravity":
    print(json.dumps({"decision": "continue", "reason": text}))
else:
    print(json.dumps({"followup_message": text}))
' 2>/dev/null || true
}

# Emit the platform-specific "ask" response for a pre-shell guardrail (Cursor + Antigravity JSON).
# When AGY_ALLOW_TOOLS is set or .agents/hooks/unattended-allow exists (unattended E2E mode),
# evaluates Shell(prog:prefix*) allowlist patterns: returns 0 (allow) on match, or 2 (deny) otherwise.
hook_shell_permission_ask() {
  user_message="$1"
  agent_message="$2"
  cmd_str="${3:-}"
  HOOK_USER_MESSAGE="$user_message" HOOK_AGENT_MESSAGE="$agent_message" HOOK_CMD_STR="$cmd_str" python3 -c '
import fnmatch, json, os, shlex, sys

user = os.environ.get("HOOK_USER_MESSAGE", "")
agent = os.environ.get("HOOK_AGENT_MESSAGE", "")
cmd = os.environ.get("HOOK_CMD_STR", "").strip()
allow_spec = os.environ.get("AGY_ALLOW_TOOLS", "").strip()
if not allow_spec:
    for candidate in (".agents/hooks/unattended-allow", "../.agents/hooks/unattended-allow"):
        if os.path.isfile(candidate):
            try:
                allow_spec = open(candidate, encoding="utf-8").read().strip()
            except OSError:
                allow_spec = ""
            break

if allow_spec:
    patterns = []
    if allow_spec != "-":
        for item in allow_spec.split(","):
            item = item.strip()
            if item.startswith("Shell(") and item.endswith(")") and ":" in item:
                inner = item[6:-1]
                prog, pat = inner.split(":", 1)
                patterns.append((prog.strip(), pat.strip()))

    def matches_allow(command_text, pats):
        if not command_text or not pats:
            return False
        try:
            tokens = shlex.split(command_text)
        except ValueError:
            return False
        # Strip leading "cd <dir> &&" if present
        while len(tokens) >= 3 and tokens[0] == "cd" and tokens[2] == "&&":
            tokens = tokens[3:]
        if not tokens:
            return False
        prog = os.path.basename(tokens[0])
        rest = tokens[1:]
        if prog == "git":
            while len(rest) >= 2 and rest[0] in ("-C", "-c"):
                rest = rest[2:]
        rest_str = " ".join(rest)
        for want_prog, want_pat in pats:
            if prog == want_prog and fnmatch.fnmatch(rest_str, want_pat):
                return True
        return False

    if matches_allow(cmd, patterns):
        print(json.dumps({"permission": "allow", "decision": "allow", "reason": "Allowed by per-turn unattended allowlist"}))
        sys.exit(0)
    deny_msg = f"Unattended mode denied ask-level command (allow={allow_spec}): {user}"
    print(json.dumps({"permission": "deny", "decision": "deny", "reason": deny_msg, "user_message": deny_msg, "agent_message": "BLOCKED in unattended mode: " + user}))
    sys.exit(2)

print(json.dumps({"permission": "ask", "decision": "ask", "reason": user, "user_message": user, "agent_message": agent}))
'
}

# Emit allow for Cursor & Antigravity permission hooks (beforeShellExecution / PreToolUse).
# Exit 0 without valid JSON is treated as invalid under failClosed and blocks the tool.
hook_shell_permission_allow() {
  HOOK_ALLOW_AGENT_MESSAGE="${1:-}" python3 -c '
import json, os
agent = os.environ.get("HOOK_ALLOW_AGENT_MESSAGE", "")
out = {"permission": "allow", "decision": "allow"}
if agent.strip():
    out["agent_message"] = agent
    out["reason"] = agent
print(json.dumps(out))
' || true
}
