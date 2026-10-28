#!/usr/bin/env bash
# agy-ipc-turn.sh — Antigravity IPC turn bridge for run-plan.sh (AGENT_TURN_CMD).
# Invoked by run_turn in lib.sh with:
#   $1 = CHAT      (logical chat session ID)
#   $2 = WS        (target workspace path)
#   $3 = MODEL     (model name)
#   $4 = MSG       (prompt text for this turn)
#   $5 = ALLOW     (per-turn allowlist or '-')
#   $6 = RUN       (evidence directory for the current run, e.g. $TEST_ROOT/evidence/S3-roadmap-1)
#   $7 = TURN      (turn index k, 1..MAX_TURNS)
#
# Writes a turn request to $RUN/turn-$TURN.req.json and $TEST_ROOT/status/pending-turn.json,
# then waits until agy-complete-turn.sh writes $RUN/turn-$TURN.resp.jsonl and $RUN/turn-$TURN.done.
set -eu

CHAT="$1"
WS="$2"
MODEL="$3"
MSG="$4"
ALLOW="$5"
RUN="$6"
TURN="$7"
TEST_ROOT="${TEST_ROOT:-$(cd "$RUN/../.." && pwd)}"
STATUS_DIR="$TEST_ROOT/status"
mkdir -p "$STATUS_DIR" "$RUN"

REQ="$RUN/turn-$TURN.req.json"
RESP="$RUN/turn-$TURN.resp.jsonl"
DONE="$RUN/turn-$TURN.done"
rm -f "$RESP" "$DONE"

AUDIT_FILE="$WS/.agents/hooks/audit.jsonl"
if [ -f "$AUDIT_FILE" ]; then
  wc -l < "$AUDIT_FILE" | tr -d ' ' > "$RUN/turn-$TURN.audit_start"
else
  echo 0 > "$RUN/turn-$TURN.audit_start"
fi

python3 - "$CHAT" "$WS" "$MODEL" "$MSG" "$ALLOW" "$RUN" "$TURN" "$REQ" "$STATUS_DIR/pending-turn.json" <<'PY'
import json, sys, time
chat, ws, model, msg, allow, run_dir, turn, req_path, pending_path = sys.argv[1:10]
payload = {
    "chat": chat,
    "workspace": ws,
    "model": model,
    "prompt": msg,
    "allow": allow,
    "run_dir": run_dir,
    "turn": int(turn),
    "requested_at": int(time.time()),
}
text = json.dumps(payload, indent=2) + "\n"
with open(req_path, "w", encoding="utf-8") as f:
    f.write(text)
with open(pending_path, "w", encoding="utf-8") as f:
    f.write(text)
PY

while [ ! -f "$DONE" ]; do
  sleep 0.5
done

[ -f "$RESP" ] && cat "$RESP"
rc="$(tr -d ' \n\r' < "$DONE" 2>/dev/null || echo 0)"
rm -f "$STATUS_DIR/pending-turn.json"
exit "${rc:-0}"
