#!/usr/bin/env bash
# test-classify.sh — offline tests of turn classification by outcome (HARNESS-FIX 2026-10-31, kitfix-20261031):
#   A. classify() on synthetic turn files: lasting quota (incl. a reset in minutes) -> USAGE, recovered 429/503 ->
#      NORMAL, empty result -> INFRA, unknown error -> AGENT-ERROR;
#   B. drive_story with stub turns: AGENT-ERROR at a reached gate -> GATE-AWARE + FINDING, approval sent, story DONE;
#      AGENT-ERROR twice with no progress -> STUCK after 2 runs (was 3); USAGE -> HALT after 1 run;
#   C. replay of the saved run-20261029-1629 evidence (P2-A empty intake turn, P2-P recovered 429 build turn,
#      P2-P recovered 503 release turn) when the results branch is reachable (E2E_RESULTS_REF, default
#      origin/e2e-results-20261030, else e2e-results-20261030); otherwise those cases print SKIP.
# Usage: bash tests/test-classify.sh   (exit 0 when every non-skipped case passes)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PASS=0; FAILN=0; SKIP=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; mkdir -p "$TEST_ROOT/status"
PLAN_DIR="$HERE"; MAX_TURNS=30 MAX_ANSWERS=3 MAX_RETRY_INFRA=1 INFRA_BACKOFF=0 TURN_PAUSE_SEC=0 RUN_TIMEOUT=600 RUN_TIMEOUT_P0A=600
MAX_RUNS_PER_STORY=8 HEARTBEAT_SEC=99999 P0A_SLUG=p0-a-platform-skeleton KIT_REF=test KIT_LABEL=test
. "$HERE/scripts/lib.sh"

# ---------- A. classify on synthetic files ----------
mk(){ # <case> <rc> <agy result error or -> <transcript jsonl lines> [<agy step_update max index>]
  local d="$SB/a/$1"; mkdir -p "$d"; : > "$d/turn-1.stderr"; : > "$d/turn-1.agy.stderr"
  printf '%s\n' "$4" > "$d/turn-1.jsonl"
  { [ -z "${5:-}" ] || for i in $(seq 1 "$5"); do printf '{"event":"step_update","step_update":{"step_index":%s}}\n' "$i"; done
    if [ "$3" = - ]; then printf '{"event":"result","result":{"status":"SUCCESS"}}\n'
    else jq -nc --arg e "$3" '{event:"result",result:{status:"ERROR",error:$e}}'; fi; } > "$d/turn-1.agy.jsonl"
  printf '%s\n' "$d"; }
want(){ local got; got="$(classify "$2" "$3/turn-1.stderr" "$3/turn-1.jsonl" 0)"; [ "$got" = "$4" ] && ok "$1 -> $got" || ko "$1: wanted $4, got $got"; }
echo "-- A. classify"
d="$(mk pers 1 'API error: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 53h19m58s.' '{"type":"ERROR_MESSAGE","step_index":1,"error":"RESOURCE_EXHAUSTED (code 429): Individual quota reached. Resets in 53h19m58s."}')"
want "lasting quota with 'Individual quota reached ... Resets in 53h' (P2-P design, run 7)" 1 "$d" USAGE
d="$(mk minutes 1 'RESOURCE_EXHAUSTED (code 429): limit hit. Resets in 45m.' '{"type":"ERROR_MESSAGE","step_index":1,"error":"RESOURCE_EXHAUSTED (code 429): limit hit. Resets in 45m."}')"
want "a reset given in minutes is lasting (new)" 1 "$d" USAGE
d="$(mk daily 1 'RESOURCE_EXHAUSTED (code 429): daily limit for this model' '{"type":"ERROR_MESSAGE","step_index":1,"error":"daily limit for this model"}')"
want "a daily limit is lasting (new)" 1 "$d" USAGE
REC='{"type":"ERROR_MESSAGE","step_index":3,"error":"API error (attempt 1): RESOURCE_EXHAUSTED (code 429) quota will reset after 0s"}
{"type":"PLANNER_RESPONSE","step_index":5,"content":"continuing"}
{"type":"result","result":"Build is awaiting your approval."}'
d="$(mk rec429 1 'API error (attempt 1): RESOURCE_EXHAUSTED (code 429) quota will reset after 0s' "$REC" 9)"
want "recovered transient 429 ('quota will reset after 0s', P2-P build, run 8)" 1 "$d" NORMAL
REC5='{"type":"ERROR_MESSAGE","step_index":"1","error":"API error (attempt 1): UNAVAILABLE (code 503): The service is currently unavailable."}
{"type":"PLANNER_RESPONSE","step_index":4,"content":"ok"}
{"type":"result","result":"Release is awaiting your approval."}'
d="$(mk rec503 1 'API error (attempt 1): UNAVAILABLE (code 503): The service is currently unavailable.' "$REC5" 6)"
want "recovered transient 503 (P2-P release, run 9)" 1 "$d" NORMAL
d="$(mk trans 1 'RESOURCE_EXHAUSTED (code 429) quota will reset after 0s' '{"type":"ERROR_MESSAGE","step_index":3,"error":"RESOURCE_EXHAUSTED (code 429)"}')"
want "transient 429 with no recovery" 1 "$d" INFRA
d="$(mk empty 0 - '{"type":"result","result":""}')"
want "rc=0 with an empty final result (P2-A intake turn 2)" 0 "$d" INFRA
d="$(mk normal 0 - '{"type":"PLANNER_RESPONSE","step_index":1,"content":"x"}
{"type":"result","result":"Intake is awaiting your approval."}')"
want "normal turn" 0 "$d" NORMAL
d="$(mk unknown 1 'tool crashed: segmentation fault' '{"type":"ERROR_MESSAGE","step_index":1,"error":"tool crashed"}')"
want "unknown error" 1 "$d" AGENT-ERROR

# ---------- B. drive_story with stub turns ----------
echo "-- B. drive_story / drive_run"
SLUG=cls-x
setup(){ S="$SB/b/$1"; mkdir -p "$S"/{status,evidence,results,snapshots,trash}
  TEST_ROOT="$S"; WORK="$S/work"; MAIN="$WORK/portal"; EVID="$S/evidence"; RES="$S/results"; STATUS_LOG="$S/status/progress.log"
  mkdir -p "$MAIN/docs/agents-v0/requirements"; git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email t@example.invalid; git -C "$MAIN" config user.name t
  echo base > "$MAIN/README.md"; git -C "$MAIN" add -A; git -C "$MAIN" commit -qm base
  git -C "$MAIN" worktree add -q -b "feature/$SLUG" "$WORK/portal-$SLUG"
  mkdir -p "$WORK/portal-$SLUG/docs/agents-v0/requirements"
  printf '%s\n' "$2" > "$WORK/portal-$SLUG/docs/agents-v0/requirements/$SLUG.state.json"
  git -C "$WORK/portal-$SLUG" add -A; git -C "$WORK/portal-$SLUG" commit -qm state
  : > "$S/turns.log"; CLASSES=("${@:3}"); CI=0; SEMI=0; CRS_IN_STORY_SLUG=""; }
setj(){ jq "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
resolve_driver(){ echo antigravity; }
run_turn(){ local k="$1" msg="$2" allow="$3" sf ap first
  printf '%s\n' "$msg" > "$RUN/turn-$k.prompt"; printf '%s\n' "$allow" > "$RUN/turn-$k.allow"
  state_dump > "$RUN/state-before-$k.tsv"; git -C "$WS" rev-parse HEAD > "$RUN/head-before-$k" 2>/dev/null || :
  sf="$WORK/portal-$SLUG/docs/agents-v0/requirements/$SLUG.state.json"; first="$(head -1 <<<"$msg")"
  TURN_CLASS="${CLASSES[$CI]:-NORMAL}"; CI=$((CI+1))
  case "$TURN_CLASS:$first" in
    NORMAL:"Approved by mdurana"*|AGENT-ERROR-GATE:"Approved by mdurana"*) ap="$(jq -r .activePhase "$sf")"
       setj "$sf" ".approvedPhases += [\"$ap\"] | .lastApprovedPhase=\"$ap\" | .activePhase=null | .activeStatus=null";;
    NORMAL:"/v0-local-release"*|AGENT-ERROR-GATE:"/v0-local-release"*) setj "$sf" '.approvedPhases += ["release"] | .lastApprovedPhase="release" | .activePhase=null | .activeStatus=null';;
    NORMAL:"/v0-"*|AGENT-ERROR-GATE:"/v0-"*) ap="${first#/v0-}"; ap="${ap%% *}"; setj "$sf" ".activePhase=\"$ap\" | .activeStatus=\"awaiting_approval\"";;
  esac
  [ "$TURN_CLASS" = AGENT-ERROR-PROG ] && setj "$sf" ".reopenCount=$CI"   # the turn changed state, then failed
  case "$TURN_CLASS" in AGENT-ERROR-GATE|AGENT-ERROR-PROG) TURN_CLASS=AGENT-ERROR;; esac
  : > "$RUN/commands-$k.txt"; echo "done." > "$RUN/final-$k.md"; state_dump > "$RUN/state-after-$k.tsv"
  printf 'turn=%s run=%s class=%s prompt1=%s\n' "$k" "${RUN##*/}" "$TURN_CLASS" "$first" >> "$S/turns.log"; }
ST_BUILD='{"approvedPhases":["intake","design"],"lastApprovedPhase":"design","activePhase":"build","activeStatus":"in_progress","verifyPassed":false}'

setup gate "$ST_BUILD" AGENT-ERROR-GATE; drive_story S4 feature "$SLUG" 0; rc=$?
grep -q 'GATE-AWARE .*class=AGENT-ERROR but build is awaiting approval' "$STATUS_LOG" && ok "AGENT-ERROR at a reached build gate -> GATE-AWARE" || ko "no GATE-AWARE line"
grep -q 'FINDING .*ended AGENT-ERROR after reaching its gate' "$STATUS_LOG" && ok "the error stays visible as a FINDING" || ko "no FINDING"
sed -n 2p "$S/turns.log" | grep -q 'prompt1=Approved by mdurana, commit it' && ok "the scripted build approval was sent next" || ko "approval not sent: $(sed -n 2p "$S/turns.log")"
[ "$rc" = 0 ] && ok "the story went on to DONE" || ko "drive_story rc=$rc"

setup ae2 "$ST_BUILD" AGENT-ERROR-PROG AGENT-ERROR-PROG AGENT-ERROR-PROG AGENT-ERROR-PROG; drive_story S4 feature "$SLUG" 0; rc=$?
[ "$rc" = 1 ] && [ "$(wc -l < "$S/turns.log")" = 2 ] && grep -q 'AGENT-ERROR in 2 runs in a row at build' "$STATUS_LOG" \
  && ok "AGENT-ERROR twice while the state still changes -> STUCK after 2 runs (P2-P design ran 3)" || ko "rc=$rc runs=$(wc -l < "$S/turns.log")"
setup ae1 "$ST_BUILD" AGENT-ERROR-PROG NORMAL; drive_story S4 feature "$SLUG" 0; rc=$?
[ "$rc" = 0 ] && ok "one AGENT-ERROR run then a good run -> story DONE (one retry kept)" || ko "rc=$rc"

setup usage "$ST_BUILD" USAGE NORMAL; drive_story S4 feature "$SLUG" 0; rc=$?
[ "$rc" = 1 ] && [ -f "$S/HALT" ] && [ "$(wc -l < "$S/turns.log")" = 1 ] && ok "USAGE -> HALT after 1 run" || ko "rc=$rc runs=$(wc -l < "$S/turns.log")"

# ---------- C. replay of saved evidence ----------
echo "-- C. replay of run-20261029-1629 evidence"
REF="${E2E_RESULTS_REF:-}"
if [ -z "$REF" ]; then for r in origin/e2e-results-20261030 e2e-results-20261030; do git -C "$HERE" rev-parse -q --verify "$r" >/dev/null && { REF="$r"; break; }; done; fi
E=e2e-results/run-20261029-1629/evidence
replay(){ # <name> <dir under evidence> <k> <rc> <expected>
  if [ -z "$REF" ]; then echo "  SKIP $1 (results branch not reachable)"; SKIP=$((SKIP+1)); return; fi
  local d="$SB/c/$1"; mkdir -p "$d"
  for f in jsonl stderr agy.jsonl agy.stderr; do git -C "$HERE" show "$REF:$E/$2/turn-$3.$f" > "$d/turn-$3.$f" 2>/dev/null || : > "$d/turn-$3.$f"; done
  local got; got="$(classify "$4" "$d/turn-$3.stderr" "$d/turn-$3.jsonl" 0)"
  [ "$got" = "$5" ] && ok "$1 -> $got" || ko "$1: wanted $5, got $got"; }
replay "P2-A intake turn 2 (empty result, run 3)" attempt-4/S4-p2-a-bff-oidc-fail-closed-session-auth-intake-1 2 0 INFRA
replay "P2-P build turn 1 (recovered 429, run 8; was AGENT-ERROR)" attempt-9/S4-p2-p-frontend-shell-dashboard-and-notifications-build-1 1 1 NORMAL
replay "P2-P release turn 1 (recovered 503, run 9; was AGENT-ERROR)" attempt-10/S4-p2-p-frontend-shell-dashboard-and-notifications-local-release-1 1 1 NORMAL
# D7: MAX_RESUMES_TOTAL counts failure resumes only (the nfail line of run-plan.sh, run on the saved fix-attempts.tsv)
NF_LINE="$(grep -m1 '^  nfail=' "$HERE/scripts/run-plan.sh")"
if [ -z "$NF_LINE" ]; then ko "run-plan.sh has no nfail line"
elif [ -z "$REF" ]; then echo "  SKIP D7 replay (results branch not reachable)"; SKIP=$((SKIP+1))
else RES="$SB/c/res"; mkdir -p "$RES"; git -C "$HERE" show "$REF:e2e-results/run-20261029-1629/results/fix-attempts.tsv" > "$RES/fix-attempts.tsv"
  eval "$NF_LINE"; [ "$nfail" = 8 ] && ok "D7: 10 rows, 2 kit-update -> 8 failure resumes counted" || ko "D7: nfail=$nfail"; fi
grep -q '"$nfail" -lt "$MAX_RESUMES_TOTAL"' "$HERE/scripts/run-plan.sh" && ok "D7: the limit compares nfail" || ko "D7: the limit does not use nfail"
# ---------- D. committed fixtures: the real P2-P persistent quota (kitfix-20261031-quota-fixture) ----------
echo "-- D. P2-P persistent-quota fixtures (tests/fixtures/p2p-quota-20261030)"
FX="$HERE/tests/fixtures/p2p-quota-20261030"
for n in 1 3; do d="$FX/design-$n"
  if [ ! -s "$d/turn-1.agy.jsonl" ]; then ko "fixture design-$n missing"; continue; fi
  [ ! -s "$d/turn-1.stderr" ] && ! grep -qiE 'quota|usage limit' "$d/turn-1.stderr" \
    && ok "design-$n: runner stderr is empty (the quota is only in the agy side files)" || ko "design-$n: fixture stderr not empty"
  k="$(agy_api_error_kind "$d/turn-1.agy.jsonl" "$d/turn-1.agy.stderr" "$d/turn-1.jsonl")"
  [ "$k" = persistent ] && ok "design-$n: agy_api_error_kind -> persistent" || ko "design-$n: agy_api_error_kind -> $k"
  for rc in 1 0; do got="$(classify "$rc" "$d/turn-1.stderr" "$d/turn-1.jsonl" 0)"
    [ "$got" = USAGE ] && ok "design-$n rc=$rc -> USAGE (was AGENT-ERROR in the run; not the empty-result INFRA rule)" || ko "design-$n rc=$rc: wanted USAGE, got $got"; done
  # the "retryable":true flag agy prints must not make a lasting quota look transient
  grep -q '"retryable":true' "$d/turn-1.agy.stderr" && ok "design-$n: agy says retryable, still USAGE" || ko "design-$n: fixture lost the retryable flag"
done
grep -rqE '/home/e2e|"error_id":"[0-9a-f]{8}-|"conversation_id":"[0-9a-f]{0,7}[1-9a-f]' "$FX" \
  && ko "fixtures still hold host paths or real ids" || ok "fixtures hold no host paths or real ids"
echo "== test-classify: $PASS passed, $FAILN failed, $SKIP skipped"
[ "$FAILN" = 0 ]
