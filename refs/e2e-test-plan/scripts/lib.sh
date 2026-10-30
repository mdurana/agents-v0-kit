#!/usr/bin/env bash
# lib.sh — harness functions, sourced by run-plan.sh. Bash >= 4, Linux.
# Chain: run-plan.sh -> drive_story/drive_run -> run_turn -> [JAIL_CMD] -> agent CLI (print mode, stream-json).
# Strictly sequential: exactly one agent process exists at any time; the caller blocks until it ends.
# The only background process is that single agent turn, which run_turn waits for in a foreground poll loop
# (the loop is what writes heartbeats and detects stalls). Nothing else ever runs concurrently.
set -u
PAT_SHELL_FORBIDDEN='(^|[;&|[:space:]])(sudo|doas|pkexec|su -c|apt(-get)? |dnf |yum |apk add|brew install)|DOCKER_HOST=tcp|:237[56]|git push|--no-verify|reset --hard|git (-C [^ ]+ )?checkout -b'

ts()   { TZ=Asia/Manila date '+%F %T'; }
now()  { date +%s; }
sha256_cmd() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
sha256_check() { if command -v sha256sum >/dev/null 2>&1; then sha256sum -c --quiet -; else shasum -a 256 -c --status -; fi; }
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }
run_isolated() { # <timeout_sec> <cmd...> — runs in a new process group with timeout (Linux + macOS portable)
  local cap="$1"; shift
  if command -v setsid >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    exec setsid timeout -k 30 "$cap" "$@"
  else
    exec python3 -c '
import os, signal, subprocess, sys
cap = float(sys.argv[1])
cmd = sys.argv[2:]
os.setsid()
p = subprocess.Popen(cmd)
try:
    sys.exit(p.wait(timeout=cap))
except subprocess.TimeoutExpired:
    try:
        os.killpg(os.getpgid(p.pid), signal.SIGTERM)
    except Exception:
        pass
    try:
        p.wait(timeout=30)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(p.pid), signal.SIGKILL)
        except Exception:
            pass
    sys.exit(124)
' "$cap" "$@"
  fi
}
# resolve_driver() is defined in env.sh (sourced before this file) so prereqs.sh and the run share one rule.
create_agent_chat() { # <workspace>
  local ws="$1" drv; drv="$(resolve_driver)"
  if [ "$drv" = cursor ] && [ -x "${AGENT_BIN:-}" ]; then
    (cd "$ws" && "$AGENT_BIN" create-chat)
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}
LAST_POST=0
post() { local line; line="$(ts) Asia/Manila $1 ${*:2}"; mkdir -p "$(dirname "$STATUS_LOG")"
         printf '%s\n' "$line" | tee -a "$STATUS_LOG"; [ -z "${STATUS_HOOK:-}" ] || printf '%s\n' "$line" | sh -c "$STATUS_HOOK" >/dev/null 2>&1 || true
         LAST_POST=$(now); }
current(){ printf '%s\n' "$*" > "$TEST_ROOT/status/current"; }
hb_tick(){ [ $(( $(now) - LAST_POST )) -lt "$HEARTBEAT_SEC" ] || post HEARTBEAT "$(cat "$TEST_ROOT/status/current" 2>/dev/null) disk=$(df -h "$TEST_ROOT" | awk 'NR==2{print $4}')"; }
halt() { printf '%s %s\n' "$(ts)" "$*" > "$TEST_ROOT/HALT"; post HALT "$*"; }

# ---------- results ----------
# chk <step> <scenario> <check-id> <description> -- <command...>   (exit 0 = PASS)
chk() { local st="$1" sc="$2" id="$3" d="$4"; shift 5; local r=FAIL
        if ( set +u; "$@" ) >>"$RES/check-output.log" 2>&1; then r=PASS; fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(ts)" "$st" "$sc" "$id" "$r" "$d" >> "$RES/checks.tsv"; [ "$r" = PASS ]; }
result(){ printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(ts)" "${4:-}" "${KIT_LABEL:-?}" >> "$RES/results.tsv"; post RESULT "$1 $2 $3 kit=${KIT_LABEL:-?} ${4:-}"; }
# runner state that later steps need (story ids, calibration, kit) — saved with every snapshot and step boundary
STATE_VARS="P0A_SLUG N1 N1_SLUG N2 N2_SLUG N3 N3_SLUG CONFIG_MODE ASK_MODE KIT_SHA KIT_LABEL"
save_state(){ local v; : > "$1"; for v in $STATE_VARS; do [ -n "${!v:-}" ] && printf '%s=%q\n' "$v" "${!v}" >> "$1"; done; return 0; }
load_state(){ [ -f "$1" ] || return 1; local v; while IFS= read -r v; do case "$v" in [A-Z0-9_]*=*) eval "export $v";; esac; done < "$1"; }

# ---------- fixtures ----------
approval_for(){ awk -F'\t' -v g="$1" '!/^#/ && $1==g {print $2 "\t" $3; exit}' "$PLAN_DIR/fixtures/approvals.tsv"; }
answer_for(){ # <context> <final-message-file>
  python3 - "$PLAN_DIR/fixtures/scripted-answers.tsv" "$1" "$2" <<'PY'
import re,sys
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1],encoding="utf-8") if l.strip() and not l.startswith("#")]
msg=open(sys.argv[3],encoding="utf-8",errors="replace").read()
for c,rx,ans in (r for r in rows if len(r)>=3):
    if c in (sys.argv[2],"*") and re.search(rx,msg,re.I|re.S):
        print(ans); sys.exit(0)
sys.exit(1)
PY
}

# ---------- state ----------
worktrees(){ git -C "$MAIN" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}'; }
wt_for_branch(){ git -C "$MAIN" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$1" '/^worktree /{w=substr($0,10)} $0=="branch " b {print w}'; }
state_sem(){ jq -cS '{lastApprovedPhase,approvedPhases,activePhase,activeStatus,blockedReason,verifyPassed,reopenCount,tier}' "$1" 2>/dev/null || echo '"<invalid>"'; }
state_dump(){ # every state file in every worktree: <abs path> TAB <semantic json>
  local w f; for w in $(worktrees); do
    for f in "$w"/docs/agents-v0/program.state.json "$w"/docs/agents-v0/onboarding/state.json "$w"/docs/agents-v0/requirements/*.state.json "$w"/docs/agents-v0/maintain/*/state.json; do
      [ -f "$f" ] && printf '%s\t%s\n' "$f" "$(state_sem "$f")"; done; done | LC_ALL=C sort; }
story_state(){ # <slug>: the authoritative state file (integration checkout once released, else the feature worktree)
  local m="$MAIN/docs/agents-v0/requirements/$1.state.json" w; w="$(wt_for_branch "feature/$1")"
  if [ -f "$m" ] && jq -e '(.approvedPhases//[])|index("release")' "$m" >/dev/null 2>&1; then echo "$m"
  elif [ -n "$w" ] && [ -f "$w/docs/agents-v0/requirements/$1.state.json" ]; then echo "$w/docs/agents-v0/requirements/$1.state.json"
  else echo "$m"; fi; }
maint_state(){ local w; w="$(wt_for_branch "maintain/$1")"
  if [ -f "$MAIN/docs/agents-v0/maintain/$1/state.json" ] && jq -e '(.approvedPhases//[])|index("release")' "$MAIN/docs/agents-v0/maintain/$1/state.json" >/dev/null 2>&1; then echo "$MAIN/docs/agents-v0/maintain/$1/state.json"
  elif [ -n "$w" ]; then echo "$w/docs/agents-v0/maintain/$1/state.json"; else echo "$MAIN/docs/agents-v0/maintain/$1/state.json"; fi; }
has_appr(){ [ -f "$1" ] && jq -e --arg p "$2" '(.approvedPhases//[])|index($p)!=null' "$1" >/dev/null; }
active_is(){ [ "$(jq -r '(.activePhase//"")+"/"+(.activeStatus//"")' "$1" 2>/dev/null)" = "$2" ]; }
pf(){ echo "$MAIN/docs/agents-v0/program.state.json"; }

# ---------- snapshots (whole $WORK: main checkout + kit-made worktrees, same absolute paths) ----------
snap(){ mkdir -p "$SNAP"; tar -C "$TEST_ROOT" --exclude=node_modules --exclude=target --exclude=dist -czf "$SNAP/$1.tgz" work &&
        (cd "$SNAP" && sha256_cmd "$1.tgz" >> SHA256SUMS) && printf '%s\n' "${KIT_LABEL:-?}" > "$SNAP/$1.kit" &&
        save_state "$SNAP/$1.state.env" && post SNAPSHOT "$1 kit=${KIT_LABEL:-?}"; }
restore(){ (cd "$SNAP" && grep " $1.tgz\$" SHA256SUMS | tail -1 | sha256_check) || { post RESTORE-FAIL "$1 checksum"; return 1; }
           [ -e "$WORK" ] && mv "$WORK" "$TEST_ROOT/trash/work.$(date +%s%N)"   # never delete: set aside
           mkdir -p "$TEST_ROOT/trash"; tar -C "$TEST_ROOT" -xzf "$SNAP/$1.tgz" && post RESTORE "$1" || return 1
           # a snapshot taken under an older kit gets the current kit through the kit's own update path
           [ "$(cat "$SNAP/$1.kit" 2>/dev/null)" = "${KIT_LABEL:-?}" ] || kit_update_workspace "restore of $1"; }
# kit_update_workspace <why>: install.sh --update [--quick] [--allow-in-flight] into the main checkout and every kit-made worktree,
# then one harness commit per checkout. Verified flags: install.sh --update [--quick] [--allow-in-flight] <target-repo>.
kit_update_workspace(){ local w fl rc=0
  for w in $(worktrees); do
    fl=(--update); [ "${KIT_UPDATE_QUICK:-1}" = 1 ] && fl+=(--quick)
    if cat "$w"/docs/agents-v0/requirements/*.state.json "$w"/docs/agents-v0/maintain/*/state.json "$w"/docs/agents-v0/onboarding/state.json "$w"/docs/agents-v0/program.state.json 2>/dev/null |
       jq -rs 'map(.activePhase//"")|map(select(.!=""))|length' | grep -qv '^0$'; then fl+=(--allow-in-flight); fi
    printf '%s kit update (%s) %s %s\n' "$(ts)" "$1" "${fl[*]}" "$w" >> "$RES/kit-update.log"
    if ! sh "$KIT/scripts/install.sh" "${fl[@]}" "$w" >> "$RES/kit-update.log" 2>&1; then post KIT-UPDATE-FAIL "$w"; rc=1; continue; fi
    if [ -n "$(git -C "$w" status --porcelain)" ]; then git -C "$w" add -A && git -C "$w" commit -q -m "Update agents-v0 kit to ${KIT_LABEL} [harness commit]"; fi
    grep -q "${KIT_SHA:0:12}" "$w/.agents-kit-version" 2>/dev/null || { post KIT-UPDATE-FAIL "$w/.agents-kit-version does not name ${KIT_SHA:0:12}"; rc=1; }
  done
  [ "$rc" = 0 ] && post KIT-UPDATE "workspace now on kit ${KIT_LABEL} ($1)"; return "$rc"; }

# ---------- agent turn ----------
CONFIG_MODE="${CONFIG_MODE:-perturn}"   # perturn = CURSOR_CONFIG_DIR per turn (allowlists possible); global = user config
mkcfg(){ # <dir> <allow csv or ->
  mkdir -p "$1"
  cp "$HOME/.cursor/cli-config.json" "$1/cli-config.json" 2>/dev/null || true
  if [ ! -s "$1/cli-config.json" ]; then
    printf '{"version":1,"editor":{"vimMode":false},"permissions":{"allow":[],"deny":[]}}\n' > "$1/cli-config.json"
  fi
  [ "$2" = - ] || python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));a=d.setdefault("permissions",{}).setdefault("allow",[]);[a.append(x) for x in sys.argv[2].split(",") if x and x not in a];json.dump(d,open(p,"w"),indent=2)' "$1/cli-config.json" "$2"; }
# HARNESS-FIX 2026-10-30 (P2-P, approved by Sensei 19:14 Asia/Manila; findings HF-F1 and HF-F3): agy quota / 429.
#   With the agy driver the agy errors are only in the agy side files next to the runner's turn files
#   (turn-<k>.agy.jsonl result.error, turn-<k>.agy.stderr) and in the transcript (ERROR_MESSAGE entries of
#   turn-<k>.jsonl), never in turn-<k>.stderr, so classify missed them. Two failures in this run:
#   - P2-P design 17:54-17:56: "RESOURCE_EXHAUSTED (code 429): Individual quota reached ... Resets in 53h19m58s"
#     (persistent) was classed AGENT-ERROR, not USAGE (test-plan.md USAGE row: write HALT, stop the run).
#   - P2-P build 18:42-19:07: one "RESOURCE_EXHAUSTED (code 429) ... quota will reset after 0s" at 18:48, agy carried on
#     for 19 minutes and reached the build gate, but its result status stayed ERROR, agy-turn-loop.sh passed rc=1, and
#     the turn was classed AGENT-ERROR (then STUCK awaiting_approval(build)).
# HARNESS-FIX 2026-10-30 (P2-P, approved by Sensei 20:41 Asia/Manila; finding HF-F4): transient agy 5xx, same gap as
#   HF-F3. P2-P local-release 20:15-20:19 wrote the approval request (release awaiting_approval) and a final answer
#   after one "API error (attempt 1): UNAVAILABLE (code 503): The service is currently unavailable." (transcript
#   step 1, as the string "1"), but agy's result status stayed ERROR -> rc=1 -> AGENT-ERROR -> STUCK. Transient server
#   errors (503 UNAVAILABLE, 500 INTERNAL, 502, 504 DEADLINE_EXCEEDED, overloaded) are now handled like a transient 429;
#   step_index is read as int or digit string; agy stderr lines that are not error lines ("root agent idle; waiting
#   ... for 2 background task(s)") are ignored. Helper renamed agy_quota_kind -> agy_api_error_kind.
#   agy_api_error_kind <agy jsonl> <agy stderr> <turn jsonl> prints one word:
#     persistent  a real usage limit ("Individual quota reached", "Resets in <N>h", usage limit ...) -> USAGE (HALT)
#     recovered   every error of the turn is a transient 429/RESOURCE_EXHAUSTED or transient 5xx, agy went on after the
#                 last one (a later agent response in the transcript and later agy steps) and the turn ended with a
#                 non-empty answer -> NORMAL, like a turn that recovered from a dropped stream
#     transient   only transient errors but no recovery seen -> INFRA (gate-aware rule or fresh retry with backoff)
#     none        anything else (no agy files, no such error, or other errors mixed in) -> the rules as before
agy_api_error_kind(){
  [ -s "$1" ] || [ -s "$2" ] || { echo none; return 0; }
  python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null || echo none
import json, re, sys
aj, ae, tj = sys.argv[1:4]
# HARNESS-FIX 2026-10-31 (kitfix-20261031, review of run 20261029-1629): a reset given in minutes, "try again in N
#   min/hours" and daily/monthly limits are lasting limits too (USAGE, HALT on the first turn). "quota will reset after
#   0s" stays transient (the P2-P build turn recovered from it).
PERS = re.compile(r'individual quota reached|resets? in \d+\s*(h|d|m(in(ute)?s?)?)\b|try again (in|after) \d+\s*(min|minute|hour|h\b)'
                  r'|(daily|weekly|monthly) (quota|limit)|quota (reached|exceeded)|usage limit|out of (credits|requests)|upgrade your subscription', re.I)
TRANS = re.compile(r'RESOURCE_EXHAUSTED|code 429|\b429\b|exhausted your capacity|rate.?limit'
                   r'|\bUNAVAILABLE\b|\bINTERNAL \(code 500\)|DEADLINE_EXCEEDED|\bcode 50[0234]\b|overloaded'
                   r'|\b50[0234] (service unavailable|internal server error|bad gateway|gateway time-?out)', re.I)
ERRLINE = re.compile(r'error|exception|fail|fatal|panic|denied|unauthori|quota|limit|exhausted|unavailable|overloaded'
                     r'|deadline|timed? ?out|\bcode \d{3}\b', re.I)
def si(o):
    v = o.get("step_index"); return int(v) if isinstance(v, int) or (isinstance(v, str) and v.isdigit()) else None
def jl(p):
    out = []
    try:
        for l in open(p, encoding="utf-8", errors="replace"):
            try: out.append(json.loads(l))
            except Exception: pass
    except OSError: pass
    return out
agy = jl(aj); tr = jl(tj); errs = []
res = [o for o in agy if o.get("event") == "result"]
if res and isinstance(res[-1].get("result"), dict) and res[-1]["result"].get("error"):
    errs.append(str(res[-1]["result"]["error"]))
try:
    blob = "\n".join(l for l in open(ae, encoding="utf-8", errors="replace").read().splitlines() if ERRLINE.search(l))
    if blob.strip(): errs.append(blob)
except OSError: pass
emsg = [o for o in tr if o.get("type") == "ERROR_MESSAGE"]
errs += [str(o.get("error") or o.get("content") or "") for o in emsg]
if not errs: print("none"); sys.exit(0)
if any(PERS.search(e) for e in errs): print("persistent"); sys.exit(0)
if not all(TRANS.search(e) for e in errs): print("none"); sys.exit(0)
idx = [si(o) for o in emsg if si(o) is not None]
last = max(idx) if idx else None
final = [o for o in tr if o.get("type") == "result"]
ftxt = final[-1].get("result") if final else ""
later_resp = last is not None and any(o.get("type") == "PLANNER_RESPONSE" and (si(o) or -1) > last for o in tr)
later_agy = last is not None and any((si(o.get("step_update") or {}) or -1) > last for o in agy if o.get("event") == "step_update")
print("recovered" if later_resp and later_agy and isinstance(ftxt, str) and ftxt.strip() else "transient")
PY
}
classify(){ # <rc> <stderr> <jsonl> <stalled>
  local aq; aq="$(agy_api_error_kind "${3%.jsonl}.agy.jsonl" "${2%.stderr}.agy.stderr" "$3")"   # HARNESS-FIX 2026-10-30, above
  if grep -qiE 'usage limit|quota|rate.?limit|out of (credits|requests)' "$2"; then echo USAGE
  elif [ "$aq" = persistent ]; then echo USAGE
  elif grep -qiE 'not logged in|unauthori[sz]ed|authentication (failed|required)|\b401\b|\b403\b' "$2"; then echo AUTH
  elif [ "$4" = 1 ]; then echo STALL
  elif [ "$1" = 124 ] || [ "$1" = 137 ]; then echo CAP
  # HARNESS-FIX 2026-10-30 (step 4, P2-A): an agent turn can end with rc=0 and a final "result" event whose text is
  #   empty, right after a tool call (P2-A intake turn 2: the stream stopped just after "--approve intake", before the
  #   kit's branch-authorisation question and feature-worktree.sh). It was classed NORMAL, the intake run ended
  #   NORMAL-END with no feature/<feature> worktree, and design/build/release then ran on main (H2 FAIL). An empty
  #   final result is a truncated turn, not an answer: it is now INFRA, so the gate-aware rule or a fresh retry from
  #   the pre-run copy applies (same as a dropped stream). Only that exact case changes; any non-empty result is NORMAL.
  elif [ "$1" = 0 ] && [ "$(jq -rs '[.[]|select(.type=="result")]|if length==0 then "x" else (last|.result // "x"|tostring) end' "$3" 2>/dev/null)" = "" ]; then echo INFRA
  elif [ "$1" = 0 ] && jq -e 'select(.type=="result" or .type=="PLANNER_RESPONSE")' "$3" >/dev/null 2>&1; then echo NORMAL
  elif [ "$aq" = recovered ]; then echo NORMAL      # HARNESS-FIX 2026-10-30: recovered transient agy 429/5xx (P2-P build, release)
  elif [ "$aq" = transient ]; then echo INFRA       # HARNESS-FIX 2026-10-30: transient agy 429/5xx, no recovery seen
  elif grep -qiE 'Connection stalled|no progress|ECONNRESET|network error|503|502' "$2"; then echo INFRA
  # HARNESS-FIX 2026-10-29 (step 4): an agy turn whose model stream dropped ends with rc!=0 and the error only in the
  #   stream (turn-<k>.jsonl), not in stderr, so it used to be AGENT-ERROR (the run ended, no retry). Last run, P1-A
  #   build tries 1, 3, 4, 5: "The stream was interrupted. Please continue the task you were working on." and
  #   "API error ... streamGenerateContent: EOF". A failed turn with that text is now INFRA (retried with backoff).
  #   A turn that recovered from a drop (rc=0 with a result) is still NORMAL, because that rule comes first.
  elif grep -qiE 'stream was interrupted|streamGenerateContent[^"]*EOF|API error[^"]*EOF|unexpected EOF' "$3" "$2" 2>/dev/null; then echo INFRA
  else echo AGENT-ERROR; fi; }
run_turn(){ # <k> <message> <allow csv or -> ; uses RUN WS CHAT RUN_DEADLINE ; sets TURN_CLASS
  local k="$1" msg="$2" allow="$3" rem cap pid rc sz last=0 lastch st=0 mark drv
  rem=$(( RUN_DEADLINE - $(now) )); cap=$TURN_CAP; [ "$rem" -lt "$cap" ] && cap=$rem; [ "$cap" -gt 60 ] || { TURN_CLASS=CAP; return; }
  printf '%s\n' "$msg" > "$RUN/turn-$k.prompt"; printf '%s\n' "$allow" > "$RUN/turn-$k.allow"
  local envv=(HOME="$HOME" USER="${USER:-tester}" LANG=C.UTF-8 TZ="${AGENT_TZ:-Asia/Manila}" TERM=xterm
    PATH="${TOOLS_PATH:-}:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin" JAVA_HOME="${JAVA_HOME:-}" PG_HOME="${PG_HOME:-}"
    TESTCONTAINERS_RYUK_DISABLED=true MAVEN_OPTS=-Xmx1536m TEST_ROOT="$TEST_ROOT" PLAN_DIR="$PLAN_DIR")
  [ -z "${CURSOR_API_KEY:-}" ] || envv+=(CURSOR_API_KEY="$CURSOR_API_KEY")
  if [ "$CONFIG_MODE" = perturn ]; then
    mkcfg "$RUN/cfg-$k" "$allow"
    envv+=(CURSOR_CONFIG_DIR="$RUN/cfg-$k" AGY_ALLOW_TOOLS="$allow")
    [ -d "$WS/.agents/hooks" ] && printf '%s\n' "$allow" > "$WS/.agents/hooks/unattended-allow"
  fi
  drv="$(resolve_driver)"
  local argv
  if [ "$drv" = antigravity ] && [ -n "${AGENT_TURN_CMD:-}" ]; then
    argv=(sh -c "$AGENT_TURN_CMD \"\$@\"" -- "$CHAT" "$WS" "$AGENT_MODEL" "$msg" "$allow" "$RUN" "$k")
  elif [ "$drv" = antigravity ] && [ -x "${AGY_BIN:-}" ]; then
    argv=("$AGY_BIN" chat --mode agent "$msg")
  else
    argv=("$AGENT_BIN" --resume "$CHAT" --trust --workspace "$WS" --model "$AGENT_MODEL" -p --output-format stream-json "$msg")
  fi
  # shellcheck disable=SC2206
  [ -z "$JAIL_CMD" ] || argv=($JAIL_CMD "$RUN" "$WS" "${argv[@]}")
  state_dump > "$RUN/state-before-$k.tsv"; git -C "$WS" rev-parse HEAD > "$RUN/head-before-$k" 2>/dev/null || :
  local audit_a_before=0 audit_c_before=0
  [ -f "$WS/.agents/hooks/audit.jsonl" ] && audit_a_before=$(wc -l < "$WS/.agents/hooks/audit.jsonl" | tr -d ' ')
  [ -f "$WS/.cursor/hooks/audit.jsonl" ] && audit_c_before=$(wc -l < "$WS/.cursor/hooks/audit.jsonl" | tr -d ' ')
  post TURN-START "run=${RUN##*/} turn=$k ws=$WS drv=$drv"; current "${RUN##*/} turn $k"
  mark="$RUN/.mark-$k"; touch "$mark"; lastch=$(now)
  ( cd "$WS" && env -i "${envv[@]}" bash -c 'source "'"$PLAN_DIR"'/scripts/lib.sh"; run_isolated "$@"' _ "$cap" "${argv[@]}" ) > "$RUN/turn-$k.jsonl" 2> "$RUN/turn-$k.stderr" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SEC"
    sz=$(file_size "$RUN/turn-$k.jsonl")
    if [ "$sz" != "$last" ] || [ -n "$(find "$WORK" -newer "$mark" -type f -print -quit 2>/dev/null)" ]; then last=$sz; lastch=$(now); touch "$mark"; fi
    if [ $(( $(now) - lastch )) -ge "$STALL_SEC" ]; then st=1; post STALL "run=${RUN##*/} turn=$k no output and no file change for ${STALL_SEC}s"
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null; sleep 30; kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
      # HARNESS-FIX 2026-10-29: with the agy driver the real agent runs in agy-turn-loop.sh, not under $pid, so killing
      #   $pid left agy running and the next turn waited behind it. Stop that agy turn too (the loop writes its pid).
      agy_stop_turn; fi
    hb_tick
  done
  wait "$pid"; rc=$?
  { [ "$rc" = 124 ] || [ "$rc" = 137 ]; } && agy_stop_turn   # HARNESS-FIX 2026-10-29: the cap also ends the agy turn
  rm -f "$WS/.agents/hooks/unattended-allow" "$MAIN/.agents/hooks/unattended-allow" 2>/dev/null || :
  TURN_CLASS=$(classify "$rc" "$RUN/turn-$k.stderr" "$RUN/turn-$k.jsonl" "$st")
  jq -r 'select(.type=="result" or .type=="PLANNER_RESPONSE") | (.result // .content // empty)' "$RUN/turn-$k.jsonl" > "$RUN/final-$k.md" 2>/dev/null || :
  {
    jq -c 'select(.type=="tool_call" and .subtype=="started")' "$RUN/turn-$k.jsonl" 2>/dev/null |
      jq -r '.. | objects | (.command? // .cmd? // .CommandLine? // empty) | strings' 2>/dev/null || :
    jq -r 'select(.type=="PLANNER_RESPONSE") | .tool_calls[]? | select(.name=="run_command") | .args.CommandLine // empty' "$RUN/turn-$k.jsonl" 2>/dev/null || :
    [ -f "$WS/.agents/hooks/audit.jsonl" ] && tail -n +"$((audit_a_before + 1))" "$WS/.agents/hooks/audit.jsonl" 2>/dev/null |
      jq -r 'select(.event=="shell" or .event=="pre-shell" or .event=="beforeShellExecution") | (.subject // .detail // empty)' 2>/dev/null || :
    [ -f "$WS/.cursor/hooks/audit.jsonl" ] && tail -n +"$((audit_c_before + 1))" "$WS/.cursor/hooks/audit.jsonl" 2>/dev/null |
      jq -r 'select(.event=="shell" or .event=="pre-shell" or .event=="beforeShellExecution") | (.subject // .detail // empty)' 2>/dev/null || :
  } | awk 'NF && !seen[$0]++' > "$RUN/commands-$k.txt"
  state_dump > "$RUN/state-after-$k.tsv"
  printf 'turn-%s\trc=%s\tclass=%s\n' "$k" "$rc" "$TURN_CLASS" >> "$RUN/turns.tsv"
  post TURN-END "run=${RUN##*/} turn=$k class=$TURN_CLASS rc=$rc"; }

# HARNESS-FIX 2026-10-29: stop the agy turn that agy-turn-loop.sh is running (its process group), if any.
agy_stop_turn(){ local f="$TEST_ROOT/agy-driver/agy-turn.pid" p; [ -s "$f" ] || return 0; p="$(cat "$f")"
  kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || return 0; post AGY-STOP "agy turn pid=$p stopped (stall or cap)"; }
# HARNESS-FIX 2026-10-29: wait before fresh retry <try>: INFRA_BACKOFF values in order, the last one repeats.
infra_backoff(){ local i=0 v last=120; for v in $INFRA_BACKOFF; do i=$((i+1)); last=$v; [ "$i" -lt "$1" ] || { echo "$v"; return; }; done; echo "$last"; }

# ---------- one agent run: new chat, first prompt, then scripted replies only ----------
# gate_pending <k>: 0 when exactly one state file went to awaiting_approval in turn k, its gate is in drive_run's
#   $allowed and was not sent yet ($sent). Sets gfile. Uses drive_run's locals (bash dynamic scope). HARNESS-FIX 2026-10-29.
gate_pending(){ local g; gfile="$(comm -13 "$RUN/state-before-$1.tsv" "$RUN/state-after-$1.tsv" | awk -F'\t' '$2 ~ /"activeStatus":"awaiting_approval"/ {print $1}')"
  [ -n "$gfile" ] && [ "$(printf '%s\n' "$gfile" | wc -l | tr -d ' ')" = 1 ] || return 1
  g="$(jq -r .activePhase "$gfile")"; case "$gfile" in *"/${P0A_SLUG:-p0-a-platform-skeleton}.state.json") [ "$g" = release ] && g=release-p0a;; esac
  printf ' %s ' "$allowed" | grep -q " ${g%-p0a} " && ! printf '%s' "$sent" | grep -q "|$gfile:$g|"; }
# drive_run <name> <workspace> <prompt> <context> "<allowed gates>" <timeout>
#   allowed gates: words from approvals.tsv (roadmap architecture plan onboard intake design build verify maintain release branch)
#   context: scripted-answers.tsv context (phase name, or "negative")
# Sets RUN (evidence dir), RUN_END (NORMAL-END|GATE-HELD|CAP|STALL|INFRA|USAGE|AUTH|AGENT-ERROR|MAX-TURNS), GATES_SENT.
drive_run(){
  local name="$1" ws="$2" prompt="$3" ctx="$4" allowed="$5" tmo="$6" n=1 try=0 k gate gfile line text allow answers sent
  local pg="${IN_STORY_GATE:-}" pgf="${IN_STORY_GATE_FILE:-}" mfile   # STAGED HARNESS-FIX 2026-10-30 (in-story resume)
  while :; do
    while [ -d "$EVID/$name-$n" ]; do n=$((n+1)); done; RUN="$EVID/$name-$n"; mkdir -p "$RUN"; WS="$ws"
    printf 'name=%s\nworkspace=%s\ncontext=%s\nallowed=%s\nkit_ref=%s\nkit_label=%s\nstart=%s Asia/Manila\n' "$name" "$ws" "$ctx" "$allowed" "${KIT_FIX_REF:-$KIT_REF}" "${KIT_LABEL:-?}" "$(ts)" > "$RUN/run.meta"
    tar -C "$TEST_ROOT" --exclude=node_modules --exclude=target -czf "$RUN/pre.tgz" work
    CHAT="$(create_agent_chat "$ws" 2>>"$RUN/create-chat.err")"; echo "$CHAT" > "$RUN/chat.id"
    RUN_DEADLINE=$(( $(now) + tmo )); GATES_SENT=""; answers=0; sent=""
    if [ -n "$pg" ]; then
      # STAGED HARNESS-FIX 2026-10-30 (in-story resume, approved by Sensei 21:14 Asia/Manila; not yet applied): the run
      #   started with the gate already awaiting_approval (the earlier attempt stopped after the agent asked for approval
      #   and before the harness sent it). Turn 1 sends that gate's scripted approval (approval_for, same allowlist, same
      #   approvals.log row, same harness_complete and release post-merge step as below), plus one context line because
      #   this is a new chat. The loop below then handles turn k as usual (USAGE/AUTH -> HALT, STALL/INFRA -> fresh
      #   retry from pre.tgz, which sends the approval again). Only drive_story sets IN_STORY_GATE, only on the first
      #   run of the in-story resume story.
      line="$(approval_for "$pg")"; text="${line%%$'\t'*}"; allow="${line#*$'\t'}"
      sent="|$pgf:$pg|"; GATES_SENT=" $pg"
      printf '%s\tturn-1\tSENT\tgate=%s\tstate=%s\ttext=%s\tallow=%s\tin-story-resume\n' "$(ts)" "$pg" "$pgf" "$text" "$allow" >> "$RUN/approvals.log"
      post IN-STORY-GATE "run=${RUN##*/} $pg was awaiting approval at resume start: turn 1 sends the scripted approval"
      run_turn 1 "$text"$'\n\n'"(Harness note: this is a new chat after a harness resume. Story ${STORY_SLUG:-?}: the $pg gate in ${pgf#"$ws"/} is awaiting approval; the line above is that approval.)" "$allow"; k=1
      harness_complete "$pg" "$allow" "$pgf"
      if [ "$pg" = release ] && [ "$SEMI" = 1 ] && [ -n "${STORY_SLUG:-}" ] && [ "$k" -lt "$MAX_TURNS" ]; then
        mfile="$MAIN/docs/agents-v0/requirements/$STORY_SLUG.state.json"
        if ! has_appr "$mfile" release; then
          WS="$MAIN"
          printf '%s\tturn-%s\tSENT\tgate=release-post-merge\tstate=%s\ttext=%s\tallow=%s\n' "$(ts)" "$((k+1))" "$mfile" "$text" "$allow" >> "$RUN/approvals.log"
          sleep "${TURN_PAUSE_SEC:-5}"; k=$((k+1)); run_turn "$k" "$text" "$allow"; harness_complete "$pg" "$allow" "$mfile"
        fi
      fi
    else run_turn 1 "$prompt" -; k=1; fi
    while :; do
      # HARNESS-FIX 2026-10-29 (gate-aware end of turn): last run, P1-A build tries 4 and 5 had already set the story
      #   state to build/awaiting_approval when the agy stream dropped and the turn was classed STALL. The harness
      #   retried from scratch instead of approving, and the step failed. Now, after STALL, INFRA or CAP, if exactly one
      #   state file went to awaiting_approval in this turn and that gate is allowed and not yet approved in this run,
      #   the turn is treated like a normal one and the scripted approval is sent (same rules as below).
      case "$TURN_CLASS" in
        STALL|INFRA|CAP) if gate_pending "$k"; then post GATE-AWARE "run=${RUN##*/} turn=$k class=$TURN_CLASS but $(jq -r .activePhase "$gfile") is awaiting approval: sending the scripted approval"; TURN_CLASS=NORMAL; fi;;
        # HARNESS-FIX 2026-10-31 (kitfix-20261031): classify by outcome. P2-P build (run 8) and release (run 9) reached
        #   their gate after an error agy recovered from, but agy reported status ERROR -> AGENT-ERROR -> STUCK, and
        #   ~107 min of correct work was thrown away. An AGENT-ERROR turn whose state reached an allowed, unsent gate is
        #   now handled like the STALL/INFRA/CAP case, with a FINDING so the error stays visible.
        AGENT-ERROR) if gate_pending "$k"; then post GATE-AWARE "run=${RUN##*/} turn=$k class=AGENT-ERROR but $(jq -r .activePhase "$gfile") is awaiting approval: sending the scripted approval"
                       post FINDING "run=${RUN##*/} turn=$k ended AGENT-ERROR after reaching its gate; see turn-$k.agy.jsonl / turn-$k.stderr"; TURN_CLASS=NORMAL; fi;;
      esac
      case "$TURN_CLASS" in
        USAGE|AUTH) halt "$TURN_CLASS in ${RUN##*/}"; RUN_END=$TURN_CLASS; return 0;;
        STALL|INFRA) RUN_END=$TURN_CLASS; break;;
        CAP|AGENT-ERROR) RUN_END=$TURN_CLASS; return 0;;
      esac
      # self-approval guard: --approve in a turn whose prompt was not a scripted approval
      if grep -Eq 'sync-feature-state\.sh([[:space:]].*)?[[:space:]]--approve([[:space:]]|$)' "$RUN/commands-$k.txt" 2>/dev/null && ! grep -qxF -f <(cut -f2 <(grep -v '^#' "$PLAN_DIR/fixtures/approvals.tsv")) "$RUN/turn-$k.prompt"; then
        echo "turn-$k" >> "$RUN/self-approval.txt"; fi
      grep -En -- "$PAT_SHELL_FORBIDDEN" "$RUN/commands-$k.txt" >> "$RUN/forbidden-commands.txt" 2>/dev/null || :
      [ "$k" -lt "$MAX_TURNS" ] || { RUN_END=MAX-TURNS; return 0; }
      # gate: exactly one state file went to awaiting_approval in this turn
      gfile="$(comm -13 "$RUN/state-before-$k.tsv" "$RUN/state-after-$k.tsv" | awk -F'\t' '$2 ~ /"activeStatus":"awaiting_approval"/ {print $1}')"
      if [ -n "$gfile" ] && [ "$(printf '%s\n' "$gfile" | wc -l | tr -d ' ')" = 1 ]; then
        gate="$(jq -r .activePhase "$gfile")"; case "$gfile" in *"/${P0A_SLUG:-p0-a-platform-skeleton}.state.json") [ "$gate" = release ] && gate=release-p0a;; esac
        if printf ' %s ' "$allowed" | grep -q " ${gate%-p0a} " && ! printf '%s' "$sent" | grep -q "|$gfile:$gate|"; then
          line="$(approval_for "$gate")"; text="${line%%$'\t'*}"; allow="${line#*$'\t'}"
          sent="$sent|$gfile:$gate|"; GATES_SENT="$GATES_SENT $gate"
          printf '%s\tturn-%s\tSENT\tgate=%s\tstate=%s\ttext=%s\tallow=%s\n' "$(ts)" "$((k+1))" "$gate" "$gfile" "$text" "$allow" >> "$RUN/approvals.log"
          sleep "${TURN_PAUSE_SEC:-5}"; k=$((k+1)); run_turn "$k" "$text" "$allow"; harness_complete "$gate" "$allow" "$gfile"
          if [ "$gate" = release ] && [ "$SEMI" = 1 ] && [ -n "${STORY_SLUG:-}" ] && [ "$k" -lt "$MAX_TURNS" ]; then
            local mfile="$MAIN/docs/agents-v0/requirements/$STORY_SLUG.state.json"
            [ "${STORY_KIND:-feature}" = maintain ] && mfile="$MAIN/docs/agents-v0/maintain/$STORY_SLUG/state.json"
            if ! has_appr "$mfile" release; then
              WS="$MAIN"
              printf '%s\tturn-%s\tSENT\tgate=release-post-merge\tstate=%s\ttext=%s\tallow=%s\n' "$(ts)" "$((k+1))" "$mfile" "$text" "$allow" >> "$RUN/approvals.log"
              sleep "${TURN_PAUSE_SEC:-5}"; k=$((k+1)); run_turn "$k" "$text" "$allow"; harness_complete "$gate" "$allow" "$mfile"
            fi
          fi
          continue
        fi
        RUN_END=GATE-HELD; return 0
      fi
      # branch authorisation request (after an Intake or Maintain step)
      if printf ' %s ' "$allowed" | grep -q ' branch ' && ! printf '%s' "$sent" | grep -q '|branch|' &&
         grep -qiE 'branch|worktree' "$RUN/final-$k.md" && grep -qiE 'authori[sz]' "$RUN/final-$k.md"; then
        line="$(approval_for branch)"; text="${line%%$'\t'*}"; allow="${line#*$'\t'}"; sent="$sent|branch|"; GATES_SENT="$GATES_SENT branch"
        printf '%s\tturn-%s\tSENT\tgate=branch\ttext=%s\tallow=%s\n' "$(ts)" "$((k+1))" "$text" "$allow" >> "$RUN/approvals.log"
        sleep "${TURN_PAUSE_SEC:-5}"; k=$((k+1)); run_turn "$k" "$text" "$allow"; harness_complete branch "$allow" ""; continue
      fi
      # question: final message asks something and nothing else happened
      if [ "$answers" -lt "$MAX_ANSWERS" ] && tail -n 25 "$RUN/final-$k.md" | grep -q '?' && text="$(answer_for "$ctx" "$RUN/final-$k.md")"; then
        answers=$((answers+1)); printf '%s\tturn-%s\tANSWER\tcontext=%s\ttext=%s\n' "$(ts)" "$((k+1))" "$ctx" "$text" >> "$RUN/answers.log"
        sleep "${TURN_PAUSE_SEC:-5}"; k=$((k+1)); run_turn "$k" "$text" -; continue
      fi
      RUN_END=NORMAL-END; return 0
    done
    # stall / infra: fresh retry from the pre-run copy (never a resume)
    try=$((try+1)); [ "$try" -le "$MAX_RETRY_INFRA" ] || { RUN_END=INFRA-GIVEUP; return 0; }
    local wait_s; wait_s="$(infra_backoff "$try")"   # HARNESS-FIX 2026-10-29: 60/120/240 s backoff (was a flat 120 s)
    post RETRY "$name after $RUN_END (try $try of $MAX_RETRY_INFRA, waiting ${wait_s}s)"; sleep "$wait_s"
    mv "$WORK" "$TEST_ROOT/trash/work.$(date +%s%N)"; tar -C "$TEST_ROOT" -xzf "$RUN/pre.tgz"
  done; }

# ---------- harness-complete: the one git step an approval authorised but the CLI denied ----------
SEMI=0
harness_complete(){ # <gate> <allow> <state file>
  local g="$1" a="$2" f="$3" w slug
  [ "$a" != - ] || return 0
  case "$g" in
    branch) slug="${STORY_SLUG:-}"; [ -n "$slug" ] || return 0
            if [ "${STORY_KIND:-feature}" = maintain ]; then [ -n "$(wt_for_branch "maintain/$slug")" ] && return 0
              (cd "$MAIN" && sh .agents-v0/scripts/feature-worktree.sh --maintain "$slug") >> "$RUN/harness-complete.log" 2>&1
            else [ -n "$(wt_for_branch "feature/$slug")" ] && return 0
              (cd "$MAIN" && sh .agents-v0/scripts/feature-worktree.sh "$slug") >> "$RUN/harness-complete.log" 2>&1; fi
            SEMI=1; echo "$(ts) branch: ran feature-worktree.sh for $slug" >> "$RUN/SEMI-SYNTHETIC";;
    build|maintain|release|release-p0a)
            w="$(cd "$(dirname "$f")" && git rev-parse --show-toplevel 2>/dev/null)"; [ -n "$w" ] || return 0
            if [ -n "$(git -C "$w" status --porcelain)" ] && [ "$(git -C "$w" rev-parse HEAD)" = "$(cat "$RUN/head-before-$((k))" 2>/dev/null)" ]; then
              git -C "$w" add -A && git -C "$w" commit -q -m "chore(${STORY_SLUG:-story}): $g evidence [harness-complete]" &&
              { SEMI=1; echo "$(ts) $g: committed pending files in $w" >> "$RUN/SEMI-SYNTHETIC"; }; fi
            if [ "$g" = release ] && [ -n "${STORY_SLUG:-}" ]; then
              local br="feature/$STORY_SLUG"; [ "${STORY_KIND:-feature}" = maintain ] && br="maintain/$STORY_SLUG"
              if git -C "$MAIN" rev-parse -q --verify "$br" >/dev/null && ! git -C "$MAIN" merge-base --is-ancestor "$br" HEAD; then
                # HARNESS-FIX 2026-10-29 (P1-E double merge): last run, the agent merged feature/<slug> into main itself,
                #   then made one more commit on the feature branch (98fa7a9). The branch tip was then no longer an
                #   ancestor of main, so this step ran a SECOND `git merge --no-ff`, which conflicted in the story's
                #   state.json and left main half-merged (MERGE_HEAD, UU file). Now: if main already holds a merge of
                #   the branch, or main is mid-merge, do not merge; write a FINDING to harness-complete.log instead.
                #   A merge that fails is undone with `git merge --abort`, so main is never left half-merged.
                local mc; mc="$(main_merge_of "$br")"
                if git -C "$MAIN" rev-parse -q --verify MERGE_HEAD >/dev/null; then
                  echo "$(ts) FINDING release: main is already mid-merge (MERGE_HEAD exists); not merging $br" >> "$RUN/harness-complete.log"
                  post FINDING "harness-complete: main mid-merge before release merge of $br; not merging (see ${RUN##*/}/harness-complete.log)"
                elif [ -n "$mc" ]; then
                  { echo "$(ts) FINDING release: main already has merge commit ${mc:0:12} of $br, but the branch tip $(git -C "$MAIN" rev-parse --short "$br") is not an ancestor of main; NOT merging again. Branch commits not on main:"
                    git -C "$MAIN" log --oneline "HEAD..$br" 2>&1 | sed 's/^/    /'; } >> "$RUN/harness-complete.log"
                  post FINDING "harness-complete: $br already merged into main (${mc:0:12}) but has later commits; no second merge (see ${RUN##*/}/harness-complete.log)"
                elif git -C "$MAIN" merge -q --no-ff -m "Merge branch '$br'" "$br" >> "$RUN/harness-complete.log" 2>&1; then
                  SEMI=1; echo "$(ts) release: merged $br into $(git -C "$MAIN" branch --show-current)" >> "$RUN/SEMI-SYNTHETIC"
                else
                  echo "$(ts) FINDING release: git merge of $br into main failed; running git merge --abort" >> "$RUN/harness-complete.log"
                  if ! git -C "$MAIN" rev-parse -q --verify MERGE_HEAD >/dev/null; then
                    echo "$(ts) release: no merge in progress (git merge stopped before starting); nothing to abort" >> "$RUN/harness-complete.log"
                  elif git -C "$MAIN" merge --abort >> "$RUN/harness-complete.log" 2>&1; then
                    echo "$(ts) release: git merge --abort done; main back at $(git -C "$MAIN" rev-parse --short HEAD)" >> "$RUN/harness-complete.log"
                  else echo "$(ts) release: git merge --abort FAILED; main may be half-merged" >> "$RUN/harness-complete.log"; fi
                  post FINDING "harness-complete: merge of $br failed and was aborted (see ${RUN##*/}/harness-complete.log)"
                fi
              fi
            fi;;
  esac; }

# main_merge_of <branch>: prints the merge commit on main's first-parent history (since the branch forked) that merged
#   <branch> (one of its later parents is an ancestor of <branch>), or one whose subject names the branch; empty if none.
#   HARNESS-FIX 2026-10-29 (P1-E double merge).
main_merge_of(){ local b="$1" base line c p
  base="$(git -C "$MAIN" merge-base HEAD "$b" 2>/dev/null)" || return 0
  while read -r line; do set -- $line; c="$1"; shift 2
    for p in "$@"; do git -C "$MAIN" merge-base --is-ancestor "$p" "$b" 2>/dev/null && { echo "$c"; return 0; }; done
  done < <(git -C "$MAIN" rev-list --merges --first-parent --parents "$base..HEAD" 2>/dev/null)
  git -C "$MAIN" log --merges --first-parent --format='%H %s' "$base..HEAD" 2>/dev/null | grep -F "'$b'" | head -1 | cut -d' ' -f1; }

# ---------- a whole story (feature or maintenance note) to local release ----------
next_cmd(){ # <state file> <kind> <is_p0a>  -> phase command word or DONE / STUCK:<why>
  local f="$1" kind="$2" p0a="$3" la ap as br
  if [ ! -f "$f" ]; then [ "$kind" = maintain ] && echo maintain || { [ "$p0a" = 1 ] && echo build || echo intake; }; return; fi
  has_appr "$f" release && { echo DONE; return; }
  ap="$(jq -r '.activePhase//""' "$f")"; as="$(jq -r '.activeStatus//""' "$f")"; la="$(jq -r '.lastApprovedPhase//""' "$f")"
  case "$as" in in_progress|blocked) [ "$ap" = release ] && echo local-release || echo "$ap"; return;;
                awaiting_approval)
                  if [ "$ap" = release ] && [ -n "${STORY_SLUG:-}" ]; then
                    br="feature/$STORY_SLUG"; [ "$kind" = maintain ] && br="maintain/$STORY_SLUG"
                    merged_into_main "$br" && { echo local-release; return; }
                  fi
                  echo "STUCK:awaiting_approval($ap) at run start"; return;; esac
  if [ "$kind" = maintain ]; then case "$la" in ""|null) echo maintain;; maintain) echo verify;; verify) echo local-release;; *) echo "STUCK:$la";; esac
  else case "$la" in ""|null) [ "$p0a" = 1 ] && echo build || echo intake;; intake) echo design;; design) echo build;; build) echo verify;; verify) echo local-release;; *) echo "STUCK:$la";; esac; fi; }
# in_story_pending_gate <state file> (STAGED HARNESS-FIX 2026-10-30, in-story resume): prints the phase whose gate is
#   awaiting_approval, when it is a gate drive_story allows and is not yet in approvedPhases; else returns 1.
in_story_pending_gate(){ local f="$1" ap
  [ -f "$f" ] && [ "$(jq -r '.activeStatus//""' "$f" 2>/dev/null)" = awaiting_approval ] || return 1
  ap="$(jq -r '.activePhase//""' "$f")"
  case " intake design build verify maintain release " in *" $ap "*) ;; *) return 1;; esac
  ! has_appr "$f" "$ap" || return 1
  echo "$ap"; }
# drive_story <step> <kind feature|maintain> <slug-or-id> <is_p0a 0|1> [<extra text for the first prompt>]
drive_story(){
  local step="$1" kind="$2" slug="$3" p0a="$4" extra="${5:-}" ae_runs=0 runs=0 f cmd ws prev="" prev_ws="" cur same=0 tmo prompt
  STORY_SLUG="$slug"; STORY_KIND="$kind"; SEMI=0
  while [ "$runs" -lt "$MAX_RUNS_PER_STORY" ]; do
    [ ! -e "$TEST_ROOT/HALT" ] || return 1
    if [ "$kind" = maintain ]; then f="$(maint_state "$slug")"; ws="$(wt_for_branch "maintain/$slug")"; else f="$(story_state "$slug")"; ws="$(wt_for_branch "feature/$slug")"; fi
    cmd="$(next_cmd "$f" "$kind" "$p0a")"
    # HARNESS-FIX 2026-10-31 (kitfix-20261031 fix 1e): a non-P0-A feature story past intake must have its
    #   feature/<slug> worktree. Run 3 (P2-A) fell back to $MAIN here and ran design/build/release on main.
    if [ -z "$ws" ] && [ "$kind" = feature ] && [ "$p0a" = 0 ]; then case "$cmd" in design|build|verify)
      post STUCK "$slug intake approved but no feature/$slug worktree (next: $cmd)"; echo "no feature/$slug worktree at $cmd" > "$EVID/$step-$slug.stuck"; return 1;; esac; fi
    [ -n "$ws" ] || ws="$MAIN"
    # STAGED HARNESS-FIX 2026-10-30 (in-story resume): on the first run of the story an in-story resume continues
    #   (run-plan.sh sets CRS_IN_STORY_SLUG only after chain_resume_prepare passed), a gate that is already
    #   awaiting_approval is approved with the scripted text instead of STUCK. One-shot: later runs use next_cmd as is.
    IN_STORY_GATE=""; IN_STORY_GATE_FILE=""
    if [ "$runs" = 0 ] && [ "$kind" = feature ] && [ "$p0a" = 0 ] && [ -n "${CRS_IN_STORY_SLUG:-}" ] && [ "$slug" = "$CRS_IN_STORY_SLUG" ]; then
      case "$cmd" in STUCK:awaiting_approval*)
        if IN_STORY_GATE="$(in_story_pending_gate "$f")"; then IN_STORY_GATE_FILE="$f"; cmd="$IN_STORY_GATE"; [ "$cmd" = release ] && cmd=local-release
        else IN_STORY_GATE=""; fi;; esac
      CRS_IN_STORY_SLUG=""
    fi
    case "$cmd" in DONE) return 0;; STUCK:*) post STUCK "$slug $cmd"; echo "$cmd" > "$EVID/$step-$slug.stuck"; return 1;; esac
    if [ "$cmd" = local-release ] && [ "$p0a" = 0 ]; then
      local br="feature/$slug"; [ "$kind" = maintain ] && br="maintain/$slug"
      merged_into_main "$br" && ws="$MAIN"
    fi
    cur="$(state_sem "$f" 2>/dev/null)"
    if [ "$cur" = "$prev" ] && [ "$ws" = "$prev_ws" ]; then same=$((same+1)); else same=0; fi
    prev="$cur"; prev_ws="$ws"
    [ "$same" -lt 2 ] || { post STUCK "$slug no state progress in 2 runs at $cmd"; echo "no progress at $cmd" > "$EVID/$step-$slug.stuck"; return 1; }
    # HARNESS-FIX 2026-10-31 (kitfix-20261031): an AGENT-ERROR run gets one retry, not two (P2-P design ran 3 times in 77 s).
    [ "$ae_runs" -lt 2 ] || { post STUCK "$slug AGENT-ERROR in 2 runs in a row at $cmd"; echo "agent error twice at $cmd" > "$EVID/$step-$slug.stuck"; return 1; }
    prompt="/v0-$cmd $slug"; { [ "$runs" = 0 ] || [ "$cmd" = maintain ]; } && [ -n "$extra" ] && prompt="$prompt"$'\n\n'"$extra"
    tmo=$RUN_TIMEOUT; [ "$p0a" = 1 ] && tmo=$RUN_TIMEOUT_P0A
    drive_run "$step-$slug-$cmd" "$ws" "$prompt" "$( [ "$cmd" = local-release ] && echo release || echo "$cmd")" \
      "intake design build verify maintain release branch" "$tmo"
    IN_STORY_GATE=""; IN_STORY_GATE_FILE=""
    echo "${RUN##*/} $RUN_END gates:${GATES_SENT:- none}" >> "$EVID/$step-$slug.runs"
    if [ "$RUN_END" = AGENT-ERROR ]; then ae_runs=$((ae_runs+1)); else ae_runs=0; fi
    runs=$((runs+1))
  done; post STUCK "$slug MAX_RUNS_PER_STORY reached"; return 1; }

# ---------- common checks ----------
clean_main(){ [ -z "$(git -C "$MAIN" status --porcelain)" ]; }
no_forbidden(){ ! cat "$EVID"/"$1"*/forbidden-commands.txt 2>/dev/null | grep -q .; }
no_self_approval(){ ! ls "$EVID"/"$1"*/self-approval.txt >/dev/null 2>&1; }
real_dirs_fp(){ local d; for d in $REAL_DIRS; do printf '%s %s %s\n' "$d" "$(git -C "$d" rev-parse HEAD 2>/dev/null)" "$(GIT_OPTIONAL_LOCKS=0 git -C "$d" status --porcelain 2>/dev/null | sha256_cmd | cut -c1-16)"; done; }
real_dirs_same(){ diff <(real_dirs_fp) "$TEST_ROOT/status/real-dirs.baseline" >/dev/null; }
# story_on_branch <slug> (HARNESS-FIX 2026-10-31, kitfix-20261031 fix 4c): the story's work reached main through
#   feature/<slug>: the branch exists, main holds its merge, and no commit on main's first-parent line since the story
#   started (STORY_H0, when set) touches app/ except the merge itself. Run 3 (P2-A) built on main and passed H1.
story_on_branch(){ local b="feature/$1" mc stray
  git -C "$MAIN" rev-parse -q --verify "$b" >/dev/null || { echo "story_on_branch: no branch $b"; return 1; }
  mc="$(main_merge_of "$b")"; [ -n "$mc" ] || { echo "story_on_branch: main has no merge of $b"; return 1; }
  [ -n "${STORY_H0:-}" ] || return 0
  stray="$(git -C "$MAIN" rev-list --first-parent --no-merges "$STORY_H0..HEAD" -- app/ 2>/dev/null | grep -v "^$mc\$" | head -3)"
  [ -z "$stray" ] || { echo "story_on_branch: commits on main touch app/ outside the merge of $b: $stray"; return 1; }; }
released_ok(){ # <slug> <is_p0a>: state, evidence, git
  local f; f="$(story_state "$1")"
  for p in build verify release; do has_appr "$f" "$p" || return 1; done
  [ "$2" = 1 ] || { has_appr "$f" intake && has_appr "$f" design && story_on_branch "$1"; } || return 1
  [ "$(jq -r .verifyPassed "$f")" = true ] && [ "$(jq -r '.activePhase//""' "$f")" = "" ] || return 1
  [ -s "$MAIN/docs/agents-v0/verify/$1/quality-gate.md" ] || return 1
  git -C "$MAIN" ls-files --error-unmatch "docs/agents-v0/requirements/$1.state.json" >/dev/null 2>&1 || return 1
  if [ -f "$MAIN/.agents-v0/scripts/check-release-evidence.sh" ]; then (cd "$MAIN" && sh .agents-v0/scripts/check-release-evidence.sh "docs/agents-v0/requirements/$1.md"); fi; }
# phases_in_order <state file> [<evidence glob prefix>] (HARNESS-FIX 2026-10-31, fix 4d): phaseTimes (ISO with offset,
#   written by --approve since kitfix-20261031) must be non-decreasing intake <= design <= build <= verify <= release;
#   without phaseTimes the phaseDates day check is used. With an evidence prefix, every gate's approvals.log SENT time
#   (Asia/Manila) must also be non-decreasing in the same order.
phases_in_order(){ python3 - "$1" "${2:-}" <<'PYX'
import datetime as dt, glob, json, re, sys
f, pre = sys.argv[1], sys.argv[2]
s = json.load(open(f)); order = ["intake", "design", "build", "verify", "release"]
t = s.get("phaseTimes") or {}
if all(p in t for p in order):
    v = [dt.datetime.fromisoformat(t[p]) for p in order]
    bad = [f"{a}>{b}" for a, b, x, y in zip(order, order[1:], v, v[1:]) if x > y]
else:
    d = s.get("phaseDates") or {}
    v = [d.get(p, "") for p in order]
    bad = [f"{a}>{b}" for a, b, x, y in zip(order, order[1:], v, v[1:]) if not x or not y or x > y]
if pre:
    sent = {}
    for lf in sorted(glob.glob(pre + "*/approvals.log")):
        for l in open(lf, encoding="utf-8", errors="replace"):
            c = l.rstrip("\n").split("\t")
            m = re.match(r"gate=(\w+)", c[3]) if len(c) > 3 and c[2] == "SENT" else None
            if m and m.group(1) in order:
                sent.setdefault(m.group(1), c[0])  # first SENT of each gate
    seen = [sent[p] for p in order if p in sent]
    bad += [f"approvals.log SENT out of order: {x} > {y}" for x, y in zip(seen, seen[1:]) if x > y]
if bad:
    print("phases_in_order:", "; ".join(bad)); sys.exit(1)
PYX
}
# ac_count_matches <slug> <planned count> (HARNESS-FIX 2026-10-31, fix 4a / H6): '### AC-<n>' headings in the
#   requirements doc vs the milestone Size column. An approved '## Proposed split' or 'Plan deviation:' line excuses it.
ac_count_matches(){ local doc="$MAIN/docs/agents-v0/requirements/$1.md" n
  [ -f "$doc" ] || { echo "ac_count: no $doc"; return 1; }
  n="$(grep -cE '^### AC-[0-9]+' "$doc")"
  case "$2" in ''|*[!0-9]*) echo "ac_count: plan Size '$2' is not a number"; return 0;; esac
  [ "$n" = "$2" ] && return 0
  grep -qE '^## Proposed split|Plan deviation:' "$doc" && { echo "ac_count: $n ACs vs plan $2, deviation recorded"; return 0; }
  echo "ac_count: $1 has $n ACs, the milestone plan says $2"; return 1; }
# native_verify <slug> <surface> (HARNESS-FIX 2026-10-31, fix 4b / V1): re-run the project's own verify in $MAIN after
#   the release instead of trusting the agent's evidence. NATIVE_VERIFY=0 skips it (the check then passes with a note).
native_verify(){ local slug="$1" surf="${2:-}" log="$RES/native-verify-$1.log" cmd rc=0 tmo="${NATIVE_VERIFY_TIMEOUT:-1800}"
  [ "${NATIVE_VERIFY:-1}" = 1 ] || { echo "native_verify: skipped (NATIVE_VERIFY=${NATIVE_VERIFY:-})"; return 0; }
  : > "$log"
  if [ -d "$MAIN/app/backend" ]; then
    cmd="$(cd "$MAIN" && sh .agents-v0/scripts/run-backend-verify.sh "Backend verify" 2>/dev/null)"; [ -n "$cmd" ] || cmd="cd app/backend && ./mvnw -q verify"
    echo "$(ts) backend: $cmd" >> "$log"; (cd "$MAIN" && timeout "$tmo" sh -c "$cmd") >> "$log" 2>&1 || rc=1
    if [ -f "$MAIN/.agents-v0/scripts/check-tests-ran.sh" ]; then (cd "$MAIN" && sh .agents-v0/scripts/check-tests-ran.sh) >> "$log" 2>&1 || rc=1; fi
  fi
  case "$surf" in *frontend*|*vertical*) if [ -f "$MAIN/app/frontend/package.json" ]; then
    cmd="$(cd "$MAIN" && sh .agents-v0/scripts/run-backend-verify.sh "Frontend verify" 2>/dev/null)"; [ -n "$cmd" ] || cmd="cd app/frontend && npm run verify"
    echo "$(ts) frontend: $cmd" >> "$log"; (cd "$MAIN" && timeout "$tmo" sh -c "$cmd") >> "$log" 2>&1 || rc=1; fi;; esac
  echo "$(ts) native_verify rc=$rc" >> "$log"; echo "native_verify $slug rc=$rc (log $log)"; [ "$rc" = 0 ]; }
merged_into_main(){ git -C "$MAIN" rev-parse -q --verify "$1" >/dev/null && git -C "$MAIN" merge-base --is-ancestor "$1" HEAD &&
                    git -C "$MAIN" log --merges --format=%s | grep -qF "$1"; }
fp_paths(){ (cd "$MAIN" && find "$@" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do sha256_cmd "$p"; done); }
