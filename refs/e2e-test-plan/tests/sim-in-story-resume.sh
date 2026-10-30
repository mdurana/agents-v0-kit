#!/usr/bin/env bash
# sim-in-story-resume.sh — offline sandbox simulation of the in-story resume (CHAIN_RESUME_IN_STORY,
# fix-and-resume.md 5.8). Staged 2026-10-30 21:22 Asia/Manila (21/21 PASS on the VM), committed with the
# harness on kitfix-20261031. Stub agent turns; no agent, no network. Touches only a temp folder.
# Usage: bash tests/sim-in-story-resume.sh [<dir with lib.sh> <run-plan.sh> <approvals.tsv> <SIMROOT> <label>]
#   default: this harness's scripts/lib.sh, scripts/run-plan.sh, fixtures/approvals.tsv, a mktemp sandbox.
# Exit 0 when every case passes.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LIBDIR="${1:-$HERE/scripts}"; RP="${2:-$HERE/scripts/run-plan.sh}"; APPR="${3:-$HERE/fixtures/approvals.tsv}"
SIMROOT="${4:-$(mktemp -d)}"; LABEL="${5:-staged}"
BASE="$SIMROOT/$LABEL-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$BASE"
SLUG=sim-x; PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
setj(){ local f="$1" q="$2"; jq "$q" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }

setup(){ # <name> <state json for the worktree>
  S="$BASE/$1"; mkdir -p "$S"/{status,evidence,results,snapshots,trash,plan/fixtures}
  TEST_ROOT="$S"; WORK="$S/work"; MAIN="$WORK/portal"; EVID="$S/evidence"; RES="$S/results"; SNAP="$S/snapshots"
  PLAN_DIR="$S/plan"; STATUS_LOG="$S/status/progress.log"; cp "$APPR" "$PLAN_DIR/fixtures/approvals.tsv"
  MAX_TURNS=30 MAX_ANSWERS=3 MAX_RETRY_INFRA=1 INFRA_BACKOFF=0 TURN_PAUSE_SEC=0 RUN_TIMEOUT=600 RUN_TIMEOUT_P0A=600 MAX_RUNS_PER_STORY=8 HEARTBEAT_SEC=99999 P0A_SLUG=p0-a-platform-skeleton KIT_REF=sim KIT_LABEL=sim
  mkdir -p "$MAIN/docs/agents-v0/requirements"; git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email sim@example.invalid; git -C "$MAIN" config user.name sim
  echo base > "$MAIN/docs/agents-v0/requirements/README.md"; git -C "$MAIN" add -A; git -C "$MAIN" commit -qm base
  git -C "$MAIN" worktree add -q -b "feature/$SLUG" "$WORK/portal-$SLUG"
  printf '%s\n' "$2" > "$WORK/portal-$SLUG/docs/agents-v0/requirements/$SLUG.state.json"
  git -C "$WORK/portal-$SLUG" add -A; git -C "$WORK/portal-$SLUG" commit -qm "state"
  : > "$S/turns.log"; SIM_CLASS_ONCE=""; SIM_CLASS=NORMAL; SEMI=0; }

. "$LIBDIR/lib.sh"
resolve_driver(){ echo antigravity; }
# stub agent turn: an approval approves the pending phase (build leaves an uncommitted file, like the real P2-P case);
#   /v0-<p> finishes the phase and asks for approval; /v0-local-release releases.
run_turn(){ local k="$1" msg="$2" allow="$3" sf ap first
  printf '%s\n' "$msg" > "$RUN/turn-$k.prompt"; printf '%s\n' "$allow" > "$RUN/turn-$k.allow"
  state_dump > "$RUN/state-before-$k.tsv"; git -C "$WS" rev-parse HEAD > "$RUN/head-before-$k" 2>/dev/null || :
  sf="$WORK/portal-$SLUG/docs/agents-v0/requirements/$SLUG.state.json"; first="$(head -1 <<<"$msg")"
  TURN_CLASS="$SIM_CLASS"; [ -z "$SIM_CLASS_ONCE" ] || { TURN_CLASS="$SIM_CLASS_ONCE"; SIM_CLASS_ONCE=""; }
  if [ "$TURN_CLASS" = NORMAL ]; then
    case "$first" in
      "Approved by mdurana"*) ap="$(jq -r .activePhase "$sf")"
         setj "$sf" ".approvedPhases += [\"$ap\"] | .lastApprovedPhase=\"$ap\" | .activePhase=null | .activeStatus=null"
         [ "$ap" = build ] && echo "evidence" > "$WORK/portal-$SLUG/build-evidence.md";;
      "/v0-local-release"*) setj "$sf" '.approvedPhases += ["release"] | .lastApprovedPhase="release" | .activePhase=null | .activeStatus=null';;
      "/v0-"*) ap="${first#/v0-}"; ap="${ap%% *}"; setj "$sf" ".activePhase=\"$ap\" | .activeStatus=\"awaiting_approval\"";;
    esac; fi
  : > "$RUN/commands-$k.txt"; echo "done." > "$RUN/final-$k.md"; state_dump > "$RUN/state-after-$k.tsv"
  printf 'turn=%s run=%s class=%s allow=%s ws=%s prompt1=%s lines=%s\n' "$k" "${RUN##*/}" "$TURN_CLASS" "$allow" "${WS##*/}" "$first" "$(printf '%s\n' "$msg" | wc -l)" >> "$S/turns.log"; }
# chain_resume_prepare from the run-plan.sh under test
eval "$(awk '/^chain_resume_prepare\(\)\{/{p=1} p{print} p&&/^  return "\$ok"; \}/{exit}' "$RP")"
restore(){ echo "restore $*" >> "$S/restore.log"; return 1; }

ST_DESIGN='{"approvedPhases":["intake"],"lastApprovedPhase":"intake","activePhase":"design","activeStatus":"in_progress","verifyPassed":false}'
ST_BUILD_AW='{"approvedPhases":["intake","design"],"lastApprovedPhase":"design","activePhase":"build","activeStatus":"awaiting_approval","verifyPassed":false}'
ST_BUILD_AW_DUP='{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":"build","activeStatus":"awaiting_approval","verifyPassed":false}'

crp(){ # <flag> -> runs chain_resume_prepare, prints rc and the log
  CRS=SIM; CRS_PREV=P2-O; CRS_SKIP_IDS=""; CRS_IN_STORY="$1"; CRS_IN_STORY_SLUG=""; A="$S/results/attempt-1"; mkdir -p "$A"; : > "$A/story-ids.tsv"
  printf '21\tP2-O\tprev\n22\tSIM\t%s\n' "$SLUG" > "$RES/chain.tsv"
  chain_resume_prepare "$A"; CRP_RC=$?; sed 's/^/    log: /' "$A/chain-resume-check.log"; mv "$A/chain-resume-check.log" "$A/chain-resume-check.log.$(date +%s%N)"; }

echo "== $LABEL: lib=$LIBDIR rp=$RP  sandbox=$BASE"
if grep -q in_story_pending_gate "$LIBDIR/lib.sh"; then STAGED=1; else STAGED=0; fi

echo "-- T1 chain_resume_prepare, flag=0, branch+worktree exist (old behaviour must stay: refuse)"
setup t1 "$ST_DESIGN"; crp 0; [ "$CRP_RC" != 0 ] && ok "refused rc=$CRP_RC" || ko "not refused"
if [ "$STAGED" = 1 ]; then
echo "-- T2 flag=1, design in_progress"; setup t2 "$ST_DESIGN"; crp 1
  [ "$CRP_RC" = 0 ] && [ "$CRS_IN_STORY_SLUG" = "$SLUG" ] && ok "accepted, CRS_IN_STORY_SLUG=$CRS_IN_STORY_SLUG" || ko "rc=$CRP_RC slug=$CRS_IN_STORY_SLUG"
echo "-- T3 flag=1, build awaiting_approval (the known gap)"; setup t3 "$ST_BUILD_AW"; crp 1
  [ "$CRP_RC" = 0 ] && ok "accepted (pending gate)" || ko "rc=$CRP_RC"
echo "-- T4 flag=1, build awaiting_approval but build already approved (inconsistent state)"; setup t4 "$ST_BUILD_AW_DUP"; crp 1
  [ "$CRP_RC" != 0 ] && ok "refused" || ko "accepted"
echo "-- T5 flag=1, worktree mid-merge"; setup t5 "$ST_DESIGN"
  git -C "$MAIN" rev-parse HEAD > "$MAIN/.git/worktrees/portal-$SLUG/MERGE_HEAD"; crp 1
  [ "$CRP_RC" != 0 ] && ok "refused" || ko "accepted"; mkdir -p "$S/trash"; mv "$MAIN/.git/worktrees/portal-$SLUG/MERGE_HEAD" "$S/trash/"
echo "-- T6 flag=1, work/ absent (would be restored from snapshot): refuse, never restore"; setup t6 "$ST_DESIGN"; mv "$WORK" "$S/trash/work.moved"; crp 1
  [ "$CRP_RC" != 0 ] && [ ! -s "$S/restore.log" ] && ok "refused, restore not called" || ko "rc=$CRP_RC restore=$(cat "$S/restore.log" 2>/dev/null)"; mv "$S/trash/work.moved" "$WORK"
echo "-- T7 flag=1, main dirty"; setup t7 "$ST_DESIGN"; echo x > "$MAIN/dirty.txt"; crp 1
  [ "$CRP_RC" != 0 ] && ok "refused" || ko "accepted"; mv "$MAIN/dirty.txt" "$S/trash/"
fi

echo "-- T8 drive_story, pending build gate, NOT an in-story resume (must stay STUCK)"
setup t8 "$ST_BUILD_AW"; CRS_IN_STORY_SLUG=""; drive_story S4 feature "$SLUG" 0; rc=$?
  [ "$rc" = 1 ] && grep -q 'STUCK:awaiting_approval(build)' "$EVID/S4-$SLUG.stuck" && ok "STUCK as before" || ko "rc=$rc"

if [ "$STAGED" = 1 ]; then
echo "-- T9 drive_story, in-story resume, pending build gate -> approval first, then verify, local-release, DONE"
setup t9 "$ST_BUILD_AW"; CRS_IN_STORY_SLUG="$SLUG"; drive_story S4 feature "$SLUG" 0; rc=$?; sed 's/^/    /' "$S/turns.log"; cat "$EVID/S4-$SLUG.runs" | sed 's/^/    runs: /'
  head -1 "$S/turns.log" | grep -q 'run=S4-sim-x-build-1 class=NORMAL allow=Shell(git:commit\*) .*prompt1=Approved by mdurana, commit it' && ok "turn 1 = build approval text + build allowlist" || ko "turn 1 wrong"
  grep -qP '\tin-story-resume$' "$EVID/S4-$SLUG-build-1/approvals.log" && ok "approvals.log row" || ko "no approvals.log row"
  grep -qxF -f <(cut -f2 <(grep -v '^#' "$PLAN_DIR/fixtures/approvals.tsv")) "$EVID/S4-$SLUG-build-1/turn-1.prompt" && ok "self-approval guard sees a scripted approval line" || ko "guard would flag"
  [ ! -e "$EVID/S4-$SLUG-build-1/self-approval.txt" ] && ok "no self-approval.txt" || ko "self-approval.txt"
  git -C "$WORK/portal-$SLUG" log -1 --format=%s | grep -q 'harness-complete' && [ -s "$EVID/S4-$SLUG-build-1/SEMI-SYNTHETIC" ] && ok "harness_complete committed pending build files (SEMI)" || ko "harness_complete not run"
  [ "$rc" = 0 ] && grep -q 'S4-sim-x-verify-1' "$S/turns.log" && ok "continued to verify and DONE" || ko "rc=$rc"
  [ -z "$CRS_IN_STORY_SLUG" ] && ok "one-shot flag cleared" || ko "flag not cleared"
echo "-- T10 drive_story, in-story resume, design in_progress -> /v0-design first, no approval sent"
setup t10 "$ST_DESIGN"; CRS_IN_STORY_SLUG="$SLUG"; drive_story S4 feature "$SLUG" 0; rc=$?
  head -1 "$S/turns.log" | grep -q 'run=S4-sim-x-design-1 .*allow=- .*prompt1=/v0-design sim-x' && ok "first turn /v0-design" || { ko "first turn wrong"; head -2 "$S/turns.log"; }
  [ ! -e "$EVID/S4-$SLUG-design-1/approvals.log" ] || ! grep -qP '\tin-story-resume$' "$EVID/S4-$SLUG-design-1/approvals.log" && ok "no in-story approval row" || ko "unexpected approval"
echo "-- T11 in-story pending gate, first turn USAGE -> HALT, run stops (unchanged USAGE path)"
setup t11 "$ST_BUILD_AW"; CRS_IN_STORY_SLUG="$SLUG"; SIM_CLASS_ONCE=USAGE; drive_story S4 feature "$SLUG" 0; rc=$?
  [ -f "$S/HALT" ] && grep -q 'USAGE in S4-sim-x-build-1' "$S/HALT" && [ "$rc" = 1 ] && [ "$(wc -l < "$S/turns.log")" = 1 ] && ok "HALT written, 1 turn, drive_story rc=1" || ko "rc=$rc halt=$(cat "$S/HALT" 2>/dev/null)"
echo "-- T12 in-story pending gate, first turn INFRA -> fresh retry from pre.tgz sends the approval again"
setup t12 "$ST_BUILD_AW"; CRS_IN_STORY_SLUG="$SLUG"; SIM_CLASS_ONCE=INFRA; drive_story S4 feature "$SLUG" 0; rc=$?; sed 's/^/    /' "$S/turns.log" | head -3
  grep -q RETRY "$STATUS_LOG" && sed -n 2p "$S/turns.log" | grep -q 'run=S4-sim-x-build-2 class=NORMAL .*prompt1=Approved by mdurana, commit it' && [ "$rc" = 0 ] && ok "retry re-sent approval, story DONE" || ko "rc=$rc"
echo "-- T13 in-story pending release gate (branch not merged) -> release approval + merge allowlist, harness_complete merges"
ST_REL_AW='{"approvedPhases":["intake","design","build","verify"],"lastApprovedPhase":"verify","activePhase":"release","activeStatus":"awaiting_approval","verifyPassed":true}'
setup t13 "$ST_REL_AW"; CRS_IN_STORY_SLUG="$SLUG"; drive_story S4 feature "$SLUG" 0; rc=$?; sed 's/^/    /' "$S/turns.log"
  head -1 "$S/turns.log" | grep -q 'run=S4-sim-x-local-release-1 class=NORMAL allow=Shell(git:commit\*),Shell(git:merge\*) .*prompt1=Approved by mdurana. Accept P-1' && ok "turn 1 = release approval text + release allowlist" || ko "turn 1 wrong"
  git -C "$MAIN" log -1 --format=%s | grep -q "Merge branch 'feature/$SLUG'" && [ "$rc" = 0 ] && ok "harness_complete merged feature/$SLUG into main, story DONE" || ko "rc=$rc main=$(git -C "$MAIN" log -1 --format=%s)"
fi
echo "== $LABEL: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
