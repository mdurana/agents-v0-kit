#!/bin/sh
# lib.sh — shared helpers for Cursor hook scripts (source from hooks/*.sh).
#
# Java VAPT-WARN scans in this file are fast heuristics only. Authoritative F4
# access-control evidence is SonarQube / ArchUnit (when wired) and the Verify
# phase (security-reviewer + vapt-review), not after-edit hook warnings.

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

# Extract shell command from a beforeShellExecution hook payload.
hook_extract_command() {
  printf '%s' "$1" | hook_json_string_field command
}

# Extract edited file path from an afterFileEdit hook payload.
hook_extract_file_path() {
  path="$(printf '%s' "$1" | hook_json_string_field file_path)"
  if [ -n "$path" ]; then
    printf '%s' "$path"
    return 0
  fi
  printf '%s' "$1" | hook_json_string_field path
}

# Append-only audit log (gitignored path under .cursor/hooks/); subjects redacted.
hook_audit_log() {
  event="$1"
  subject="$2"
  decision="$3"
  detail="$4"
  logdir=".cursor/hooks"
  logfile="$logdir/audit.jsonl"
  mkdir -p "$logdir" 2>/dev/null || return 0
  HOOK_AUDIT_EVENT="$event" HOOK_AUDIT_SUBJECT="$subject" HOOK_AUDIT_DECISION="$decision" HOOK_AUDIT_DETAIL="$detail" \
    python3 -c '
import json, os, re, time

def redact(s):
    if not s:
        return s
    s = re.sub(r"(?i)(authorization|bearer|token|password|api[_-]?key)\s*[=:]\s*[^\s\"]+", r"\1=***", s)
    s = re.sub(r"(?i)(ghp_[a-zA-Z0-9]{20,})", "ghp_***", s)
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

# Session start context (Cursor sessionStart).
hook_emit_session_context() {
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

# Stop hook: surface reminder as a follow-up when supported.
hook_emit_stop_followup() {
  text="$1"
  [ -n "$text" ] || return 0
  HOOK_FOLLOWUP_TEXT="$text" python3 -c '
import json, os
text = os.environ.get("HOOK_FOLLOWUP_TEXT", "")
if not text.strip():
    raise SystemExit(0)
print(json.dumps({"followup_message": text}))
' 2>/dev/null || true
}

# Emit the platform-specific "ask" response for a pre-shell guardrail (Cursor permission JSON).
hook_shell_permission_ask() {
  user_message="$1"
  agent_message="$2"
  HOOK_USER_MESSAGE="$user_message" HOOK_AGENT_MESSAGE="$agent_message" python3 -c '
import json, os
user = os.environ.get("HOOK_USER_MESSAGE", "")
agent = os.environ.get("HOOK_AGENT_MESSAGE", "")
print(json.dumps({"permission": "ask", "user_message": user, "agent_message": agent}))
' || true
}

# Emit allow for Cursor permission hooks (beforeShellExecution / preToolUse).
# Exit 0 without valid JSON is treated as invalid under failClosed and blocks the tool.
hook_shell_permission_allow() {
  HOOK_ALLOW_AGENT_MESSAGE="${1:-}" python3 -c '
import json, os
agent = os.environ.get("HOOK_ALLOW_AGENT_MESSAGE", "")
out = {"permission": "allow"}
if agent.strip():
    out["agent_message"] = agent
print(json.dumps(out))
' || true
}

# Warn on Java controllers: mutating mappings without nearby or class-level @PreAuthorize.
# Skips tests and non-controller sources; heuristic only (Verify/Sonar own F4).
hook_java_warn_missing_preauthorize() {
  file="$1"
  [ -f "$file" ] || return 0
  case "$file" in
    *Test.java|*Tests.java|*/test/*|*/it/*) return 0 ;;
  esac
  HOOK_JAVA_FILE="$file" python3 -c '
import os, re, sys

path = os.environ.get("HOOK_JAVA_FILE", "")
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)

if not re.search(r"@(?:RestController|Controller)\b", text):
    sys.exit(0)

mapping_re = re.compile(r"@(Post|Put|Patch|Delete)Mapping\b")
preauth_re = re.compile(
    r"@(?:PreAuthorize|Secured|RolesAllowed|"
    r"jakarta\.annotation\.security\.RolesAllowed)\b"
)

controller_m = re.search(r"@(RestController|Controller)\b", text)

first_mapping = mapping_re.search(text)
class_preauth = False
if first_mapping and controller_m.start() < first_mapping.start():
    header = text[controller_m.start() : first_mapping.start()]
    class_preauth = bool(preauth_re.search(header))

lines = text.splitlines()
for i, line in enumerate(lines):
    if not mapping_re.search(line):
        continue
    # Annotations may sit above or below the mapping line before the method signature.
    window = "\n".join(lines[max(0, i - 25) : min(len(lines), i + 16)])
    if preauth_re.search(window):
        continue
    if class_preauth:
        continue
    lineno = i + 1
    print(
        f"VAPT-WARN: {path}:{lineno}: mutating endpoint without method/class "
        f"security annotation (vapt.mdc F4; heuristic only — confirm in Verify/Sonar).",
        file=sys.stderr,
    )
' || true
}
