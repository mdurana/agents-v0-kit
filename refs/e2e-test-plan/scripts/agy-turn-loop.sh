#!/usr/bin/env bash
# agy-turn-loop.sh — unattended Antigravity (agy CLI) session that answers run-plan.sh IPC turns.
# Same role the Antigravity session played on the Mac: for each $TEST_ROOT/status/pending-turn.json it runs
# one agy turn in the turn's workspace (one agy conversation per harness chat id), with shell commands routed
# through plan/scripts/agy-ws-exec.sh (kit pre-shell hook + per-turn allowlist), then completes the turn with
# plan/scripts/agy-complete-turn.sh --conversation (transcript -> stream-json, as documented in the plan scripts).
# Usage: agy-turn-loop.sh <test_root> <plan_dir> <runner_pid>
# Start it in its own tmux window AFTER run-plan.sh, with the same environment as the runner (scripts/start-tmux.sh
# does both). It ends by itself when the runner process exits.
#
# HARNESS-FIX 2026-10-29: this file used to live only in the run root of the 2026-10-28 run on Marlon's box. It is now
# part of the plan, with these changes (see HARNESS-FIXES-20261029.md):
#   - agy is found through AGY_BIN / PATH / ~/.local/bin, not the fixed path /home/box/.local/bin/agy (VM-01);
#   - the tool environment (JDK 21, Node 22, PostgreSQL 17 from tools.env) is loaded here, because every shell command
#     agy runs inherits this process's environment; on the box ~/.bashrc happened to supply JAVA_HOME (VM-02);
#   - each agy turn runs in its own process group and its pid is written to agy-driver/agy-turn.pid, so the runner can
#     stop it after a stall or cap instead of leaving it running (SF-04).
set -u
TR="$1"; PLAN="$2"; RPID="$3"
: "${TOOLS_DIR:=$HOME/.local/agents-v0-tools}"
[ -f "$TOOLS_DIR/tools.env" ] && . "$TOOLS_DIR/tools.env"
[ -z "${TOOLS_PATH:-}" ] || export PATH="$TOOLS_PATH:$PATH"
[ -z "${JAVA_HOME:-}" ] || export JAVA_HOME
AGY="${AGY_BIN:-$(command -v agy 2>/dev/null || echo "$HOME/.local/bin/agy")}"
[ -x "$AGY" ] || { echo "agy-turn-loop: agy not found (set AGY_BIN; tried $AGY)" >&2; exit 2; }
DRV="$TR/agy-driver"; BRAIN_SRC="$HOME/.gemini/antigravity-cli/brain"; BRAIN_COPY="$DRV/brain"
AGY_TURN_TIMEOUT="${AGY_TURN_TIMEOUT:-1680}"
mkdir -p "$DRV/chats" "$BRAIN_COPY"
log(){ printf '%s %s\n' "$(TZ=Asia/Manila date '+%F %T')" "$*" >> "$DRV/loop.log"; }
log "loop start runner_pid=$RPID agy=$($AGY --version 2>/dev/null) model_arg=${AGY_MODEL:-default}"
# HARNESS-FIX 2026-10-29: record the exact CLI versions at the start and end of the run (agy auto-updates).
printf 'start %s agy=%s agent=%s\n' "$(TZ=Asia/Manila date '+%F %T')" "$($AGY --version 2>/dev/null | head -1)" "$(agent --version 2>/dev/null | head -1)" >> "$DRV/cli-versions.txt"
while kill -0 "$RPID" 2>/dev/null; do
  P="$TR/status/pending-turn.json"
  if [ ! -s "$P" ]; then sleep 2; continue; fi
  REQ="$(cat "$P")"
  CHAT="$(jq -r .chat <<<"$REQ")"; WS="$(jq -r .workspace <<<"$REQ")"; MSG="$(jq -r .prompt <<<"$REQ")"
  RUN="$(jq -r .run_dir <<<"$REQ")"; K="$(jq -r .turn <<<"$REQ")"; ALLOW="$(jq -r .allow <<<"$REQ")"
  [ -f "$RUN/turn-$K.done" ] && { sleep 1; continue; }
  CONVF="$DRV/chats/$CHAT.conv"; CONV="$(cat "$CONVF" 2>/dev/null || true)"
  PROMPT="[Unattended agents-v0 e2e run. You are the coding agent in the workspace $WS (your current directory). No person is watching and nobody will answer mid-turn.
- The text after 'USER MESSAGE:' is the user's chat message to you. When it starts with a kit command such as /v0-roadmap or /v0-build, read that command's definition in .agents/commands/<command>.md and follow it exactly, together with AGENTS.md and the rules in .agents/rules (and any sub-agent or skill files they name).
- Run EVERY shell command through the kit's pre-shell guard, never directly: bash $PLAN/scripts/agy-ws-exec.sh --test-root $TR '<command>'  (it runs the command in $WS and applies the kit's hook policy with this turn's allowlist; use --ws <dir> only to run in another checkout the kit tells you to use). If it prints HOOK BLOCKED or HOOK DENIED, that is the kit guardrail's answer: do not retry the command another way.
- When the kit command reaches an approval gate, needs a decision, or is finished, stop and end your turn with your message to the user.]

USER MESSAGE:
$MSG"
  ARGS=(--dangerously-skip-permissions --output-format stream-json)
  [ -n "${AGY_MODEL:-}" ] && ARGS+=(--model "$AGY_MODEL")
  [ -n "$CONV" ] && ARGS+=(--conversation "$CONV")
  log "turn start run=${RUN##*/} k=$K chat=$CHAT conv=${CONV:-new} ws=$WS allow=$ALLOW msg=$(head -c 120 <<<"$MSG" | tr '\n' ' ')"
  printf '%s\n' "$PROMPT" > "$RUN/turn-$K.agy.prompt"
  # own process group (setsid) so the runner can stop the whole agy turn via agy-turn.pid (HARNESS-FIX 2026-10-29)
  ( cd "$WS" && exec env AGY_ALLOW_TOOLS="$ALLOW" TZ="${AGENT_TZ:-UTC}" setsid timeout -k 30 "$AGY_TURN_TIMEOUT" "$AGY" "${ARGS[@]}" -p "$PROMPT" ) > "$RUN/turn-$K.agy.jsonl" 2> "$RUN/turn-$K.agy.stderr" < /dev/null &
  APID=$!; echo "$APID" > "$DRV/agy-turn.pid"
  wait "$APID"; rc=$?; rm -f "$DRV/agy-turn.pid"
  NEWCONV="$(jq -r 'select(.event=="init") | .conversation_id' "$RUN/turn-$K.agy.jsonl" 2>/dev/null | head -1)"
  [ -z "$CONV" ] && [ -n "$NEWCONV" ] && { CONV="$NEWCONV"; echo "$CONV" > "$CONVF"; }
  STATUS="$(jq -r 'select(.event=="result") | .result.status' "$RUN/turn-$K.agy.jsonl" 2>/dev/null | tail -1)"
  log "turn end run=${RUN##*/} k=$K rc=$rc status=${STATUS:-none} conv=${CONV:-none}"
  # still the same pending request? (the runner may have timed the turn out meanwhile)
  if [ ! -s "$P" ] || [ "$(jq -r '.run_dir+"#"+(.turn|tostring)' "$P" 2>/dev/null)" != "$RUN#$K" ]; then log "pending request gone; not completing"; continue; fi
  T="$BRAIN_SRC/$CONV/.system_generated/logs/transcript.jsonl"
  if [ -n "$CONV" ] && [ -f "$T" ]; then
    # copy of the transcript with run_command CommandLine decoded (agy stores it JSON-quoted), so the harness's
    # command checks see the plain command text
    mkdir -p "$BRAIN_COPY/$CONV/.system_generated/logs"
    python3 - "$T" "$BRAIN_COPY/$CONV/.system_generated/logs/transcript.jsonl" <<'PY'
import json,sys
out=open(sys.argv[2],"w",encoding="utf-8")
for l in open(sys.argv[1],encoding="utf-8",errors="replace"):
    s=l.strip()
    if not s: continue
    try: o=json.loads(s)
    except Exception: out.write(s+"\n"); continue
    for tc in o.get("tool_calls") or []:
        a=tc.get("args") or {}
        for key in ("CommandLine",):
            v=a.get(key)
            if isinstance(v,str):
                try:
                    d=json.loads(v)
                    if isinstance(d,str): a[key]=d
                except Exception: pass
    out.write(json.dumps(o)+"\n")
PY
    [ "$rc" = 0 ] && [ "$STATUS" != SUCCESS ] && [ -n "$STATUS" ] && rc=1
    bash "$PLAN/scripts/agy-complete-turn.sh" --test-root "$TR" --conversation "$CONV" --brain-dir "$BRAIN_COPY" --rc "$rc" >> "$DRV/loop.log" 2>&1
  else
    TXT="$(jq -r 'select(.event=="result") | .result.response // empty' "$RUN/turn-$K.agy.jsonl" 2>/dev/null | tail -1)"
    [ "$rc" = 0 ] && rc=1
    log "no transcript for conv=${CONV:-none}; completing with response text rc=$rc"
    bash "$PLAN/scripts/agy-complete-turn.sh" --test-root "$TR" --text "$TXT" --rc "$rc" >> "$DRV/loop.log" 2>&1
  fi
done
printf 'end %s agy=%s agent=%s\n' "$(TZ=Asia/Manila date '+%F %T')" "$($AGY --version 2>/dev/null | head -1)" "$(agent --version 2>/dev/null | head -1)" >> "$DRV/cli-versions.txt"
log "loop end (runner exited)"
