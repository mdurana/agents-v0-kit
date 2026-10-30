#!/usr/bin/env python3
"""Build the small, sanitized P2-P persistent-quota fixtures from the raw run-20261029-1629 evidence
(archive path run-20261029-1629/trash/p2p-quota-fail-20261030-1815/evidence/S4-p2-p-...-design-<n>/).
Usage: sanitize.py <raw evidence dir> <out dir> <n>. Keeps only what classify()/agy_api_error_kind read:
the agy result event (status, error text verbatim), the step_update skeleton around the error, the agy stderr
error lines, the transcript's user message (kit command only) and final result. Drops conversation and error ids,
host paths, tool parameters, the tool list and the unattended-run preamble."""
import json, re, sys
src, dst, n = sys.argv[1], sys.argv[2], sys.argv[3]
CID = "00000000-0000-0000-0000-00000000000" + n
def jl(p):
    return [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
def w(p, rows):
    with open(p, "w", encoding="utf-8") as f:
        for r in rows: f.write(json.dumps(r, separators=(",", ":")) + "\n")
agy = jl(f"{src}/turn-1.agy.jsonl")
err_steps = [o["step_update"]["step_index"] for o in agy if o.get("event") == "step_update" and o["step_update"].get("step_type") == "error_message"]
last_err = max(err_steps)
out = []
for o in agy:
    e = o.get("event")
    if e == "init":
        out.append({"event": "init", "conversation_id": CID, "init": {"model": o["init"].get("model"), "cwd": "/home/tester/work/portal-p2-p", "tools": [], "permission_mode": o["init"].get("permission_mode")}})
    elif e == "step_update":
        su = o["step_update"]; si = su.get("step_index")
        if si == 0 or si >= last_err - 2:
            r = {"conversation_id": CID, "step_index": si, "state": su.get("state"), "step_type": su.get("step_type")}
            if su.get("tool_name"): r["tool_name"] = su["tool_name"]
            out.append({"event": "step_update", "step_update": r})
    elif e == "result":
        r = dict(o["result"]); r["conversation_id"] = CID
        out.append({"event": "result", "result": r})
w(f"{dst}/turn-1.agy.jsonl", out)
st = open(f"{src}/turn-1.agy.stderr", encoding="utf-8").read()
st = re.sub(r'"error_id":"[^"]*"', '"error_id":"redacted"', st)
open(f"{dst}/turn-1.agy.stderr", "w", encoding="utf-8").write(st)
open(f"{dst}/turn-1.stderr", "w").write(open(f"{src}/turn-1.stderr").read())
tr = jl(f"{src}/turn-1.jsonl"); t = []
for o in tr:
    if o.get("type") == "USER_INPUT":
        cmd = re.search(r"USER MESSAGE:\n(.*?)\n", o["content"]).group(1)
        t.append({"step_index": 0, "source": o.get("source"), "type": "USER_INPUT", "status": o.get("status"), "created_at": o.get("created_at"),
                  "content": "<USER_REQUEST>\n[unattended e2e preamble removed]\n\nUSER MESSAGE:\n" + cmd + "\n</USER_REQUEST>"})
pr = [o for o in tr if o.get("type") == "PLANNER_RESPONSE"]
if pr: t.append({"type": "PLANNER_RESPONSE", "step_index": pr[-1].get("step_index"), "status": pr[-1].get("status"), "content": None})
t += [{"type": "result", "result": o.get("result")} for o in tr if o.get("type") == "result"]
w(f"{dst}/turn-1.jsonl", t)
