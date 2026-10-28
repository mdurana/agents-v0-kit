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
resolve_driver() {
  if [ "${AGENT_DRIVER:-auto}" != auto ]; then echo "$AGENT_DRIVER"
  elif [ -x "${AGENT_BIN:-}" ]; then echo cursor
  elif [ -n "${AGENT_TURN_CMD:-}" ]; then echo antigravity
  else echo antigravity; fi
}
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
classify(){ # <rc> <stderr> <jsonl> <stalled>
  if grep -qiE 'usage limit|quota|rate.?limit|out of (credits|requests)' "$2"; then echo USAGE
  elif grep -qiE 'not logged in|unauthori[sz]ed|authentication (failed|required)|\b401\b|\b403\b' "$2"; then echo AUTH
  elif [ "$4" = 1 ]; then echo STALL
  elif [ "$1" = 124 ] || [ "$1" = 137 ]; then echo CAP
  elif [ "$1" = 0 ] && jq -e 'select(.type=="result" or .type=="PLANNER_RESPONSE")' "$3" >/dev/null 2>&1; then echo NORMAL
  elif grep -qiE 'Connection stalled|no progress|ECONNRESET|network error|503|502' "$2"; then echo INFRA
  else echo AGENT-ERROR; fi; }
run_turn(){ # <k> <message> <allow csv or -> ; uses RUN WS CHAT RUN_DEADLINE ; sets TURN_CLASS
  local k="$1" msg="$2" allow="$3" rem cap pid rc sz last=0 lastch st=0 mark drv
  rem=$(( RUN_DEADLINE - $(now) )); cap=$TURN_CAP; [ "$rem" -lt "$cap" ] && cap=$rem; [ "$cap" -gt 60 ] || { TURN_CLASS=CAP; return; }
  printf '%s\n' "$msg" > "$RUN/turn-$k.prompt"; printf '%s\n' "$allow" > "$RUN/turn-$k.allow"
  local envv=(HOME="$HOME" USER="${USER:-tester}" LANG=C.UTF-8 TZ=Asia/Manila TERM=xterm
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
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null; sleep 30; kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null; fi
    hb_tick
  done
  wait "$pid"; rc=$?
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

# ---------- one agent run: new chat, first prompt, then scripted replies only ----------
# drive_run <name> <workspace> <prompt> <context> "<allowed gates>" <timeout>
#   allowed gates: words from approvals.tsv (roadmap architecture plan onboard intake design build verify maintain release branch)
#   context: scripted-answers.tsv context (phase name, or "negative")
# Sets RUN (evidence dir), RUN_END (NORMAL-END|GATE-HELD|CAP|STALL|INFRA|USAGE|AUTH|AGENT-ERROR|MAX-TURNS), GATES_SENT.
drive_run(){
  local name="$1" ws="$2" prompt="$3" ctx="$4" allowed="$5" tmo="$6" n=1 try=0 k gate gfile line text allow answers sent
  while :; do
    while [ -d "$EVID/$name-$n" ]; do n=$((n+1)); done; RUN="$EVID/$name-$n"; mkdir -p "$RUN"; WS="$ws"
    printf 'name=%s\nworkspace=%s\ncontext=%s\nallowed=%s\nkit_ref=%s\nkit_label=%s\nstart=%s Asia/Manila\n' "$name" "$ws" "$ctx" "$allowed" "${KIT_FIX_REF:-$KIT_REF}" "${KIT_LABEL:-?}" "$(ts)" > "$RUN/run.meta"
    tar -C "$TEST_ROOT" --exclude=node_modules --exclude=target -czf "$RUN/pre.tgz" work
    CHAT="$(create_agent_chat "$ws" 2>>"$RUN/create-chat.err")"; echo "$CHAT" > "$RUN/chat.id"
    RUN_DEADLINE=$(( $(now) + tmo )); GATES_SENT=""; answers=0; sent=""
    run_turn 1 "$prompt" -; k=1
    while :; do
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
    post RETRY "$name after $RUN_END (try $try of $MAX_RETRY_INFRA)"; sleep 120
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
                git -C "$MAIN" merge -q --no-ff -m "Merge branch '$br'" "$br" >> "$RUN/harness-complete.log" 2>&1 &&
                { SEMI=1; echo "$(ts) release: merged $br into $(git -C "$MAIN" branch --show-current)" >> "$RUN/SEMI-SYNTHETIC"; }; fi
            fi;;
  esac; }

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
# drive_story <step> <kind feature|maintain> <slug-or-id> <is_p0a 0|1> [<extra text for the first prompt>]
drive_story(){
  local step="$1" kind="$2" slug="$3" p0a="$4" extra="${5:-}" runs=0 f cmd ws prev="" prev_ws="" cur same=0 tmo prompt
  STORY_SLUG="$slug"; STORY_KIND="$kind"; SEMI=0
  while [ "$runs" -lt "$MAX_RUNS_PER_STORY" ]; do
    [ ! -e "$TEST_ROOT/HALT" ] || return 1
    if [ "$kind" = maintain ]; then f="$(maint_state "$slug")"; ws="$(wt_for_branch "maintain/$slug")"; else f="$(story_state "$slug")"; ws="$(wt_for_branch "feature/$slug")"; fi
    [ -n "$ws" ] || ws="$MAIN"
    cmd="$(next_cmd "$f" "$kind" "$p0a")"
    case "$cmd" in DONE) return 0;; STUCK:*) post STUCK "$slug $cmd"; echo "$cmd" > "$EVID/$step-$slug.stuck"; return 1;; esac
    if [ "$cmd" = local-release ] && [ "$p0a" = 0 ]; then
      local br="feature/$slug"; [ "$kind" = maintain ] && br="maintain/$slug"
      merged_into_main "$br" && ws="$MAIN"
    fi
    cur="$(state_sem "$f" 2>/dev/null)"
    if [ "$cur" = "$prev" ] && [ "$ws" = "$prev_ws" ]; then same=$((same+1)); else same=0; fi
    prev="$cur"; prev_ws="$ws"
    [ "$same" -lt 2 ] || { post STUCK "$slug no state progress in 2 runs at $cmd"; echo "no progress at $cmd" > "$EVID/$step-$slug.stuck"; return 1; }
    prompt="/v0-$cmd $slug"; { [ "$runs" = 0 ] || [ "$cmd" = maintain ]; } && [ -n "$extra" ] && prompt="$prompt"$'\n\n'"$extra"
    tmo=$RUN_TIMEOUT; [ "$p0a" = 1 ] && tmo=$RUN_TIMEOUT_P0A
    drive_run "$step-$slug-$cmd" "$ws" "$prompt" "$( [ "$cmd" = local-release ] && echo release || echo "$cmd")" \
      "intake design build verify maintain release branch" "$tmo"
    echo "${RUN##*/} $RUN_END gates:${GATES_SENT:- none}" >> "$EVID/$step-$slug.runs"
    runs=$((runs+1))
  done; post STUCK "$slug MAX_RUNS_PER_STORY reached"; return 1; }

# ---------- common checks ----------
clean_main(){ [ -z "$(git -C "$MAIN" status --porcelain)" ]; }
no_forbidden(){ ! cat "$EVID"/"$1"*/forbidden-commands.txt 2>/dev/null | grep -q .; }
no_self_approval(){ ! ls "$EVID"/"$1"*/self-approval.txt >/dev/null 2>&1; }
real_dirs_fp(){ local d; for d in $REAL_DIRS; do printf '%s %s %s\n' "$d" "$(git -C "$d" rev-parse HEAD 2>/dev/null)" "$(GIT_OPTIONAL_LOCKS=0 git -C "$d" status --porcelain 2>/dev/null | sha256_cmd | cut -c1-16)"; done; }
real_dirs_same(){ diff <(real_dirs_fp) "$TEST_ROOT/status/real-dirs.baseline" >/dev/null; }
released_ok(){ # <slug> <is_p0a>: state, evidence, git
  local f; f="$(story_state "$1")"
  for p in build verify release; do has_appr "$f" "$p" || return 1; done
  [ "$2" = 1 ] || { has_appr "$f" intake && has_appr "$f" design; } || return 1
  [ "$(jq -r .verifyPassed "$f")" = true ] && [ "$(jq -r '.activePhase//""' "$f")" = "" ] || return 1
  [ -s "$MAIN/docs/agents-v0/verify/$1/quality-gate.md" ] || return 1
  git -C "$MAIN" ls-files --error-unmatch "docs/agents-v0/requirements/$1.state.json" >/dev/null 2>&1 || return 1
  if [ -f "$MAIN/.agents-v0/scripts/check-release-evidence.sh" ]; then (cd "$MAIN" && sh .agents-v0/scripts/check-release-evidence.sh "docs/agents-v0/requirements/$1.md"); fi; }
merged_into_main(){ git -C "$MAIN" rev-parse -q --verify "$1" >/dev/null && git -C "$MAIN" merge-base --is-ancestor "$1" HEAD &&
                    git -C "$MAIN" log --merges --format=%s | grep -qF "$1"; }
fp_paths(){ (cd "$MAIN" && find "$@" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do sha256_cmd "$p"; done); }
