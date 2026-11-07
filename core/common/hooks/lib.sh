#!/bin/sh
# lib.sh — shared helpers for Cursor hook scripts (source from hooks/*.sh).
#
# Pack-specific static analysis lives in `.agents-v0/packs/<id>/hooks/pack-scan.sh`
# (shipped from `core/<pack>/hooks/pack-scan.sh`). Authoritative F4 access-control
# evidence is the Verify phase (security-reviewer + vapt-review), not after-edit hook warnings.

# N-1 (kitfix-20261031-n1, approved in design review 2026-10-31 16:36 Asia/Manila): every hook runs Python as
#   "$HOOK_PYTHON" -I -S (the hook_py helper below). HOOK_PYTHON is the absolute interpreter path that install.sh
#   checked and wrote into the file hook-python next to these scripts. It is never read from the environment: an
#   agent sets the environment of the commands it starts, and a developer's shell reads agent-writable dotfiles.
#   Without that file (the kit's own tree, a --link install, an install older than N-1) it is /usr/bin/python3.
#   -I ignores PYTHON* variables and keeps the user site, the working folder (a json.py the agent wrote into the
#   project, N-2) and the script folder off sys.path; -S skips the site module, so no sitecustomize, *.pth or
#   site-packages. The hooks use the standard library only, and hook-policy.py is loaded by its absolute path.
#   Scope (kitfix-20261031-jn4 wording): this closes Python start-up injection. It does not guard the agent user's
#   other home files: shell and session start-up files (LD_PRELOAD, PATH) are the start-up rule in hook-policy.py
#   (JN-4), plus the PATH and preload checks at the top of the hooks (M-1).
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || HOOK_DIR="$(dirname "$0")"
HOOK_PYTHON=""
if [ -f "$HOOK_DIR/hook-python" ]; then
  IFS= read -r HOOK_PYTHON < "$HOOK_DIR/hook-python" || :
fi
case "$HOOK_PYTHON" in
  /*) ;;
  *) HOOK_PYTHON=/usr/bin/python3 ;;
esac
HOOK_POLICY_PY="$HOOK_DIR/hook-policy.py"
PYTHONNOUSERSITE=1
export PYTHONNOUSERSITE
# JN-7 (Jiraiya's N-1 review): -I -S does not stop a module loaded by path (hook-policy.py in
#   hook_shell_permission_ask) from reading a planted __pycache__/hook-policy.cpython-*.pyc next to the hooks.
#   -X pycache_prefix points every bytecode lookup at a folder that cannot exist (/dev/null is not a folder, for
#   root too), so the source is always compiled, and -B never writes a cache (PYTHONDONTWRITEBYTECODE is ignored
#   under -I). Python 3.7 and older ignore pycache_prefix; the check below accepts them without it.
HOOK_PYCACHE_PREFIX=/dev/null/agents-v0
# JN-12 (Jiraiya): the interpreter always runs with PATH=/usr/bin:/bin (as the hooks themselves do since M-1), so even
#   a pin that is a "#!/usr/bin/env python3" script could not reach a python3 the agent put on the IDE's PATH.
HOOK_SAFE_PATH=/usr/bin:/bin
_hook_py_run() { PATH="$HOOK_SAFE_PATH" "$HOOK_PYTHON" -I -S -B -X pycache_prefix="$HOOK_PYCACHE_PREFIX" "$@"; }
hook_py() { [ -z "$HOOK_PYTHON_WHY" ] || return 126; _hook_py_run "$@"; }
# JN-2 / JN-5 / JN-8 (Jiraiya's N-1 review): hook_python_problem prints why HOOK_PYTHON must not be trusted, nothing
#   when it may. The pin can arrive through git (a pulled or merged hook-python) or be rewritten (H-5), so it is
#   checked at every hook run, not only by install.sh:
#   - it is an executable file that does not start with #! (JN-12), and it (followed through a symlink) and its
#     folder are owned by root and not writable by group or others (one ls, one awk);
#   - it is a working Python that runs as hook_py runs it: a fixed snippet must print the marker with isolated=1,
#     no_site=1, dont_write_bytecode=1 and the pycache prefix. /bin/true, /usr/bin/env or a folder print nothing,
#     and dropping -I, -S, -B or -X from hook_py changes the line, so the hooks fail closed (JN-8 at run time).
#   It runs once, when this file is sourced (HOOK_PYTHON_WHY, never read from the environment). pre-shell.sh and
#   pre-edit.sh deny with a literal JSON line when it is set, and hook_py refuses to run an untrusted pin (rc 126).
hook_python_problem() {
  if [ ! -f "$HOOK_PYTHON" ] || [ ! -x "$HOOK_PYTHON" ]; then
    printf '%s is missing or not an executable file' "$HOOK_PYTHON"; return 0
  fi
  # JN-12 (Jiraiya): a root-owned script (for example /usr/bin/routel, "#! /usr/bin/env python3") passes the owner
  #   check but hands the work to another program; only an interpreter binary is accepted.
  if [ "$(head -c 2 "$HOOK_PYTHON" 2>/dev/null)" = '#!' ]; then  # jn12-shebang-check
    printf '%s is a #! script, not an interpreter binary' "$HOOK_PYTHON"; return 0
  fi
  if ! ls -ldnL "$HOOK_PYTHON" "$(dirname "$HOOK_PYTHON")" 2>/dev/null | awk '
      NF < 3 || $3 != "0" || substr($1, 6, 1) == "w" || substr($1, 9, 1) == "w" { bad = 1 }
      END { exit (bad || NR != 2) }'; then
    printf '%s or its folder is not owned by root, or is writable by group or others' "$HOOK_PYTHON"; return 0
  fi
  hp_marker="$(_hook_py_run -c 'import sys
f = sys.flags
p = getattr(sys, "pycache_prefix", None) if sys.version_info >= (3, 8) else "pre-3.8"
print("agents-v0-hook-python %d %d %d %s" % (f.isolated, f.no_site, f.dont_write_bytecode, p))' </dev/null 2>/dev/null)" || hp_marker=""
  case "$hp_marker" in
    "agents-v0-hook-python 1 1 1 $HOOK_PYCACHE_PREFIX"|"agents-v0-hook-python 1 1 1 pre-3.8") ;;
    *) printf '%s is not a working Python run with -I -S -B (marker: %s)' "$HOOK_PYTHON" "${hp_marker:-none}" ;;
  esac
}
HOOK_PYTHON_WHY=""
HOOK_PYTHON_WHY="$(hook_python_problem)"
# kitfix-20261031-jn4 (Jiraiya JN-4): the dynamic loader honours LD_PRELOAD / LD_AUDIT (macOS: DYLD_INSERT_LIBRARIES)
#   for this sh and the pinned interpreter before the first line of a hook runs, so -I -S and the pin cannot help; a
#   library there can rewrite any verdict. The fence is the start-up file rule in hook-policy.py (the variable has to
#   be written where the IDE or agy picks it up). This check is a second line: every library named there must be an
#   absolute path whose file and folder are owned by root and not writable by group or others (a system library
#   such as gtk3-nocsd passes); anything else makes pre-shell and pre-edit deny. A library that unsets its own
#   variable before this line runs is not seen. LD_LIBRARY_PATH is not checked (developer setups use it).
hook_env_problem() {
  for he_var in LD_PRELOAD LD_AUDIT DYLD_INSERT_LIBRARIES; do
    eval "he_val=\${$he_var:-}"
    [ -n "$he_val" ] || continue
    for he_lib in $(printf '%s' "$he_val" | tr ': ' '\n\n'); do
      case "$he_lib" in
        /*) ;;
        *) printf '%s names %s, not an absolute path' "$he_var" "$he_lib"; return 0 ;;
      esac
      if ! ls -ldnL "$he_lib" "$(dirname "$he_lib")" 2>/dev/null | awk '
          NF < 3 || $3 != "0" || substr($1, 6, 1) == "w" || substr($1, 9, 1) == "w" { bad = 1 }
          END { exit (bad || NR != 2) }'; then
        printf '%s names %s, which is missing, not owned by root, or writable by group or others' "$he_var" "$he_lib"
        return 0
      fi
    done
  done
}
HOOK_ENV_WHY=""
HOOK_ENV_WHY="$(hook_env_problem)"
# hook_deny_literal <reason>: a deny verdict that needs no Python; exits 2. The reason may hold the pin's text (from
#   git), so quotes, backslashes and control characters are dropped before it goes into the JSON line.
hook_deny_literal() {
  hd_r="$(printf '%s' "$1" | tr -d '"\\\000-\037')"
  printf 'BLOCK: %s (fail-closed)\n' "$hd_r" >&2
  printf '{"permission": "deny", "decision": "deny", "reason": "%s (fail-closed)"}\n' "$hd_r"
  exit 2
}

# Read hook JSON from stdin; print a string field (supports nested keys with dots).
# Tries common Cursor payload shapes when the top-level key is missing.
hook_json_string_field() {
  field="${1:-}"
  [ -n "$field" ] || return 0
  HOOK_JSON_FIELD="$field" hook_py -c '
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
    hook_py -c '
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
  HOOK_CONTEXT_TEXT="$text" hook_py -c '
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
  HOOK_CONTEXT_TEXT="$text" HOOK_FLAVOR="${KIT_HOOK_FLAVOR:-cursor}" hook_py -c '
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
  HOOK_FOLLOWUP_TEXT="$text" HOOK_FLAVOR="${KIT_HOOK_FLAVOR:-cursor}" hook_py -c '
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
  HOOK_USER_MESSAGE="$user_message" HOOK_AGENT_MESSAGE="$agent_message" HOOK_CMD_STR="$cmd_str" \
    HOOK_POLICY_PY="$HOOK_POLICY_PY" hook_py -c '
import fnmatch, importlib.util, json, os, re, shlex, sys

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

    # kitfix-20261031-no-amend: an allowlist entry such as Shell(git:commit*) never allows a commit that rewrites
    #   history. "--amend" (or an abbreviation git accepts: --am, --ame, --amen) anywhere in the command is denied,
    #   also after "&&" or inside a quoted "sh -c" string. Gate commits are never amended (make a new commit).
    AMEND = re.compile(r"(?:^|[\s\"\x27;&|(])--am(?:e(?:nd?)?)?(?=$|[\s\"\x27;&|)=])")
    if "git" in cmd and "commit" in cmd and AMEND.search(cmd):
        deny_msg = "Unattended mode denied git commit --amend: gate commits are never amended (make a new commit)."
        print(json.dumps({"permission": "deny", "decision": "deny", "reason": deny_msg, "user_message": deny_msg, "agent_message": "BLOCKED in unattended mode: " + deny_msg}))
        sys.exit(2)
    # kitfix-20261031-guard-override: a compound command is allowed only when EVERY segment that needs approval
    #   matches the allowlist. Before, only the first program was matched, so "git commit -m x && git reset --soft
    #   HEAD~1" passed Shell(git:commit*) while the gate command "git add -A && git commit -F ..." was denied.
    #   Segments are split and judged by hook-policy.py (sh -c bodies and $(...) included); allow-level segments
    #   (git add, cd, ...) pass, ask-level ones must match, a block-level one denies. When the ask came only from a
    #   whole-command rule (a download piped into an interpreter), no segment matches and it is denied.
    #   If hook-policy.py cannot be loaded the command is denied (fail closed).
    def every_ask_segment_allowed(command_text, pats):
        if not command_text or not pats:
            return False
        try:
            sys.dont_write_bytecode = True   # never leave __pycache__ in the project
            spec = importlib.util.spec_from_file_location("kit_hook_policy", os.environ.get("HOOK_POLICY_PY", ""))
            hp = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(hp)
            segs = hp.split_segments(command_text)
        except Exception:
            return False
        asks = 0
        for seg in segs:
            if hp._cd_target(seg):
                continue
            action, _msg = hp.classify_segment(seg)
            if action == "block":
                return False
            if action == "ask":
                asks += 1
                if not matches_allow(hp._strip_env_prefix(seg.strip()), pats):
                    return False
        return asks > 0

    if every_ask_segment_allowed(cmd, patterns):
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
  HOOK_ALLOW_AGENT_MESSAGE="${1:-}" hook_py -c '
import json, os
agent = os.environ.get("HOOK_ALLOW_AGENT_MESSAGE", "")
out = {"permission": "allow", "decision": "allow"}
if agent.strip():
    out["agent_message"] = agent
    out["reason"] = agent
print(json.dumps(out))
' || true
}
