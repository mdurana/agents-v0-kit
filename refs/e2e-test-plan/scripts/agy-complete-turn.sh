#!/usr/bin/env bash
# agy-complete-turn.sh — Complete a pending Antigravity IPC turn from a subagent transcript or direct response.
# Usage:
#   bash scripts/agy-complete-turn.sh --test-root <dir> --conversation <subagent-conv-id> [--brain-dir <dir>]
#   bash scripts/agy-complete-turn.sh --test-root <dir> --text "<final text>" [--cmd "<shell cmd>"]
set -eu

TR=""
CONV=""
BRAIN_DIR="${HOME}/.gemini/antigravity/brain"
DIRECT_TEXT=""
DIRECT_CMD=""
RC=0

while [ $# -gt 0 ]; do
  case "$1" in
    --test-root) TR="$2"; shift 2 ;;
    --conversation) CONV="$2"; shift 2 ;;
    --brain-dir) BRAIN_DIR="$2"; shift 2 ;;
    --text) DIRECT_TEXT="$2"; shift 2 ;;
    --cmd) DIRECT_CMD="$2"; shift 2 ;;
    --rc) RC="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

PENDING="$TR/status/pending-turn.json"
[ -f "$PENDING" ] || { echo "error: no pending turn at $PENDING" >&2; exit 1; }

python3 -I -S - "$PENDING" "$CONV" "$BRAIN_DIR" "$DIRECT_TEXT" "$DIRECT_CMD" "$RC" <<'PY'
import json, os, sys

pending_path, conv_id, brain_dir, direct_text, direct_cmd, rc_str = sys.argv[1:7]
req = json.load(open(pending_path, encoding="utf-8"))
run_dir = req["run_dir"]
turn = req["turn"]
ws = req["workspace"]
chat = req["chat"]

resp_path = os.path.join(run_dir, f"turn-{turn}.resp.jsonl")
done_path = os.path.join(run_dir, f"turn-{turn}.done")
offset_file = os.path.join(run_dir, f".chat-{chat}.offset")

start_line = 0
if os.path.isfile(offset_file):
    try:
        start_line = int(open(offset_file, encoding="utf-8").read().strip() or "0")
    except ValueError:
        start_line = 0

out_lines = []
final_text = direct_text

if conv_id:
    tpath = os.path.join(brain_dir, conv_id, ".system_generated", "logs", "transcript.jsonl")
    if not os.path.isfile(tpath):
        sys.exit(f"error: transcript not found: {tpath}")
    raw_lines = open(tpath, encoding="utf-8", errors="replace").readlines()
    new_lines = raw_lines[start_line:]
    with open(offset_file, "w", encoding="utf-8") as f:
        f.write(str(len(raw_lines)))
    for line in new_lines:
        line_s = line.strip()
        if not line_s:
            continue
        out_lines.append(line_s)
        try:
            obj = json.loads(line_s)
        except Exception:
            continue
        if obj.get("type") == "PLANNER_RESPONSE":
            if obj.get("content"):
                final_text = obj["content"]
            for tc in obj.get("tool_calls") or []:
                if tc.get("name") == "run_command":
                    args = tc.get("args") or {}
                    cmd_str = args.get("CommandLine") or ""
                    if cmd_str:
                        out_lines.append(json.dumps({
                            "type": "tool_call",
                            "subtype": "started",
                            "tool_call": {"shellToolCall": {"args": {"command": cmd_str}}}
                        }))

# Also include any commands logged by .agents/hooks/audit.jsonl during this turn
audit_start_file = os.path.join(run_dir, f"turn-{turn}.audit_start")
audit_file = os.path.join(ws, ".agents", "hooks", "audit.jsonl")
turn_cmds = []
if os.path.isfile(audit_file):
    a_start = 0
    if os.path.isfile(audit_start_file):
        try:
            a_start = int(open(audit_start_file, encoding="utf-8").read().strip() or "0")
        except ValueError:
            a_start = 0
    a_lines = open(audit_file, encoding="utf-8", errors="replace").readlines()
    for aline in a_lines[a_start:]:
        try:
            aobj = json.loads(aline)
        except Exception:
            continue
        cmd_s = aobj.get("subject") or aobj.get("detail") or ""
        if aobj.get("event") in ("shell", "pre-shell", "beforeShellExecution") and cmd_s:
            turn_cmds.append(cmd_s)
            out_lines.append(json.dumps({
                "type": "tool_call",
                "subtype": "started",
                "tool_call": {"shellToolCall": {"args": {"command": cmd_s}}}
            }))

if direct_cmd:
    turn_cmds.append(direct_cmd)
    out_lines.append(json.dumps({
        "type": "tool_call",
        "subtype": "started",
        "tool_call": {"shellToolCall": {"args": {"command": direct_cmd}}}
    }))

if not conv_id:
    out_lines.insert(0, json.dumps({
        "type": "PLANNER_RESPONSE",
        "content": final_text or "",
        "tool_calls": [{"name": "run_command", "args": {"CommandLine": c}} for c in turn_cmds]
    }))

out_lines.append(json.dumps({
    "type": "result",
    "result": final_text or ""
}))

with open(resp_path, "w", encoding="utf-8") as f:
    for l in out_lines:
        f.write(l + "\n")

try:
    os.remove(pending_path)
except OSError:
    pass

with open(done_path, "w", encoding="utf-8") as f:
    f.write(str(rc_str) + "\n")
PY
