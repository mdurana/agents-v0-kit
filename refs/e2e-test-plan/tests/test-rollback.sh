#!/usr/bin/env bash
# test-rollback.sh — offline tests of commit-on-every-gate in the harness (HARNESS-FIX 2026-10-31, kitfix-20261031):
#   rollback to the last clean gate commit of the current story (story_rollback, fix-and-resume.md 5.6), the
#   step-back rules (a consistency check names an earlier phase; the rerun fails the same way), the stops that wait
#   for Marlon, squash-aware merge detection (squash_of, merged_into_main, main_merge_of, story_on_branch), the
#   gate-commit fallback label (GATE-COMMIT-MISSING, check H7) and the chain_resume_prepare hook-up.
# Usage: bash tests/test-rollback.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; KITROOT="$(cd "$HERE/../.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; mkdir -p "$TEST_ROOT/status"; PLAN_DIR="$HERE"
MAX_RUNS_PER_STORY=8 P0A_SLUG=p0-a-platform-skeleton
. "$HERE/scripts/lib.sh"
SLUG=orders; ID=P1-A; SF="docs/agents-v0/requirements/$SLUG.state.json"
gc(){ git -C "$W" add -A; git -C "$W" commit -qm "$1"; }
st(){ mkdir -p "$W/docs/agents-v0/requirements"; printf '%s\n' "$1" > "$W/$SF"; }
setup(){ # <name>: main + feature/orders worktree with intake, design and build gate commits; verify in flight
  S="$SB/$1"; TEST_ROOT="$S"; WORK="$S/work"; MAIN="$WORK/portal"; EVID="$S/evidence"; RES="$S/results"; STATUS_LOG="$S/status/progress.log"
  mkdir -p "$S"/{status,evidence,results,trash} "$MAIN"; git -C "$MAIN" init -q -b main
  git -C "$MAIN" config user.email t@example.invalid; git -C "$MAIN" config user.name t
  echo base > "$MAIN/README.md"; git -C "$MAIN" add -A; git -C "$MAIN" commit -qm base
  git -C "$MAIN" worktree add -q -b "feature/$SLUG" "$WORK/portal-$SLUG"; W="$WORK/portal-$SLUG"
  mkdir -p "$W/.agents-v0/scripts" "$W/docs/agents-v0/requirements" "$W/docs/agents-v0/design/$SLUG" "$W/docs/agents-v0/verify/$SLUG" "$W/app/backend/src/test/java"
  cp "$KITROOT/templates/.agents-v0/scripts/check-traceability.sh" "$W/.agents-v0/scripts/"
  printf '# Orders\n### AC-1 — a\n### AC-2 — b\n' > "$W/docs/agents-v0/requirements/$SLUG.md"
  st '{"approvedPhases":["intake"],"lastApprovedPhase":"intake","activePhase":null,"activeStatus":null}'; gc "$ID: intake approved"
  printf '# Design\n| AC-1 | x |\n| AC-2 | y |\n' > "$W/docs/agents-v0/design/$SLUG/design.md"
  st '{"approvedPhases":["intake","design"],"lastApprovedPhase":"design","activePhase":null,"activeStatus":null}'; gc "$ID: design approved"
  printf 'class T { // AC-1\n}\n' > "$W/app/backend/src/test/java/T.java"
  st '{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":null,"activeStatus":null}'; gc "$ID: build approved"
  BUILD_SHA="$(git -C "$W" rev-parse HEAD)"; DESIGN_SHA="$(git -C "$W" rev-parse HEAD~1)"
  # the failed verify phase: a wip commit, an uncommitted edit, an untracked file
  echo wip > "$W/wip.txt"; gc "wip during verify"; echo edit >> "$W/README.md"; echo junk > "$W/untracked.log"
  st '{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":"verify","activeStatus":"in_progress"}'
  printf '| AC-1 | T | PASS |\n| AC-2 | T | PASS |\n' > "$W/docs/agents-v0/verify/$SLUG/quality-gate.md"   # untracked: AC-2 passes
  mkdir -p "$RES/attempt-1" "$EVID/attempt-1"; : > "$RES/attempt-1/checks.tsv"; echo "no progress at verify" > "$EVID/attempt-1/S4-$SLUG.stuck"; }

echo "-- R1 default: reset to the last clean gate commit of the story"
setup r1; story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" > "$S/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$W" rev-parse HEAD)" = "$BUILD_SHA" ] && [ -z "$(git -C "$W" status --porcelain)" ] \
  && ok "feature/$SLUG reset to the build gate commit, tree clean" || ko "rc=$rc head=$(git -C "$W" log -1 --format=%s) $(cat "$S/out")"
[ "$(git -C "$W" symbolic-ref --short HEAD)" = "feature/$SLUG" ] && [ -d "$W" ] && ok "branch and worktree kept" || ko "branch/worktree"
[ "$(jq -r .lastApprovedPhase "$W/$SF")" = build ] && [ "$(jq -r '.activePhase' "$W/$SF")" = null ] && ok "state = build approved, verify reruns" || ko "state $(cat "$W/$SF")"
grep -q 'wip during verify' "$RES/attempt-1/rollback-discarded-commits.txt" && grep -q 'edit' "$RES/attempt-1/rollback-discarded.patch" \
  && [ -f "$S/trash/rollback-1/untracked.log" ] && ok "discarded work kept (patch, commit list, untracked files in trash/)" || ko "discarded work not kept"
grep -q 'gate=build reason=default: last clean gate' "$RES/attempt-1/rollback.txt" && grep -q 'ROLLBACK P1-A' "$STATUS_LOG" && ok "rollback.txt + ROLLBACK progress line" || ko "rollback.txt: $(cat "$RES/attempt-1/rollback.txt" 2>/dev/null)"

echo "-- R2 a consistency check of the failed phase names an earlier phase -> step back to that phase's gate"
setup r2; printf '| AC-1 | T | PASS |\n| AC-2 | T | FAIL |\n' > "$W/docs/agents-v0/verify/$SLUG/quality-gate.md"
story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" > "$S/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$W" rev-parse HEAD)" = "$DESIGN_SHA" ] && grep -q 'reason=consistency check names build' "$RES/attempt-1/rollback.txt" \
  && ok "T6 blames build (no test names AC-2) -> reset to the design gate, build reruns" || ko "rc=$rc $(cat "$S/out") $(cat "$RES/attempt-1/rollback.txt" 2>/dev/null)"

echo "-- R3 the rerun fails the same way -> step back one gate"
setup r3; story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" >/dev/null 2>&1
echo wip2 > "$W/wip2.txt"; st '{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":"verify","activeStatus":"in_progress"}'
printf '| AC-1 | T | PASS |\n| AC-2 | T | PASS |\n' > "$W/docs/agents-v0/verify/$SLUG/quality-gate.md"
mkdir -p "$RES/attempt-2" "$EVID/attempt-2"; : > "$RES/attempt-2/checks.tsv"; echo "no progress at verify" > "$EVID/attempt-2/S4-$SLUG.stuck"
story_rollback "$SLUG" "$ID" "$RES/attempt-2" "$EVID/attempt-2" > "$S/out" 2>&1; rc=$?
[ "$rc" = 0 ] && [ "$(git -C "$W" rev-parse HEAD)" = "$DESIGN_SHA" ] && grep -q 'gate=design reason=same failure after the rerun' "$RES/attempt-2/rollback.txt" \
  && ok "same signature twice -> reset to the design gate" || ko "rc=$rc $(cat "$S/out")"

echo "-- R4 the rerun fails differently -> stop, wait for Marlon"
setup r4; story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" >/dev/null 2>&1
mkdir -p "$RES/attempt-2" "$EVID/attempt-2"; printf 't\t4\tP1-A\tH1\tFAIL\td\n' > "$RES/attempt-2/checks.tsv"
st '{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":"verify","activeStatus":"in_progress"}'
printf '| AC-1 | T | PASS |\n| AC-2 | T | PASS |\n' > "$W/docs/agents-v0/verify/$SLUG/quality-gate.md"
before="$(git -C "$W" rev-parse HEAD)"; story_rollback "$SLUG" "$ID" "$RES/attempt-2" "$EVID/attempt-2" > "$S/out" 2>&1; rc=$?
[ "$rc" = 1 ] && [ "$(git -C "$W" rev-parse HEAD)" = "$before" ] && grep -q 'failed differently' <<<"$ROLLBACK_STOP" && ok "no clear cause -> no reset, ROLLBACK_STOP set" || ko "rc=$rc stop=$ROLLBACK_STOP"

echo "-- R5 two rollbacks already -> stop"
setup r5; for a in 1 2; do mkdir -p "$RES/attempt-$a"; echo "slug=$SLUG id=$ID from=x to=y gate=build reason=r sig=s" > "$RES/attempt-$a/rollback.txt"; done
mkdir -p "$RES/attempt-3" "$EVID/attempt-3"; : > "$RES/attempt-3/checks.tsv"
story_rollback "$SLUG" "$ID" "$RES/attempt-3" "$EVID/attempt-3" > "$S/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'rolled back twice' <<<"$ROLLBACK_STOP" && ok "2-attempt limit" || ko "rc=$rc stop=$ROLLBACK_STOP"

echo "-- R6 no clean gate commit (story branch broken) -> stop, snapshot fallback named"
setup r6; git -C "$W" reset -q --soft "$(git -C "$MAIN" rev-parse HEAD)"; git -C "$W" commit -qm "everything at once"
story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" > "$S/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'CHAIN_RESUME_IN_STORY=0' <<<"$ROLLBACK_STOP" && ok "branch broken -> previous story's END snapshot (CHAIN_RESUME_IN_STORY=0)" || ko "rc=$rc stop=$ROLLBACK_STOP"
setup r6b; git -C "$W" commit -q --allow-empty -m "chore($SLUG): build evidence [harness-complete]"
[ "$(gate_commits "$W" "$SLUG" | wc -l | tr -d ' ')" = 3 ] && ok "a [harness-complete] commit is never a clean gate" || ko "gate_commits: $(gate_commits "$W" "$SLUG")"

echo "-- R7 the failed design phase's checks blame intake -> stop (intake reruns on main)"
setup r7; git -C "$W" reset -q --hard HEAD~3   # back to the intake gate; design in flight
st '{"approvedPhases":["intake"],"lastApprovedPhase":"intake","activePhase":"design","activeStatus":"in_progress"}'
mkdir -p "$W/docs/agents-v0/milestones" "$W/docs/agents-v0/design/$SLUG"; printf '# Design\n| AC-1 | x |\n| AC-2 | y |\n' > "$W/docs/agents-v0/design/$SLUG/design.md"
printf '| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |\n|---|---|---|---|---|---|---|\n| P1-A | u | docs/agents-v0/requirements/%s.md | planned | — | backend | 3 |\n' "$SLUG" > "$W/docs/agents-v0/milestones/p1.md"
story_rollback "$SLUG" "$ID" "$RES/attempt-1" "$EVID/attempt-1" > "$S/out" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q 'blame intake' <<<"$ROLLBACK_STOP" && ok "T2 (2 ACs vs Size 3) blames intake -> stop" || ko "rc=$rc stop=$ROLLBACK_STOP $(cat "$S/out")"

echo "-- R8 squash-aware merge detection, H1 branch part, H7 label"
setup r8; git -C "$W" checkout -q -- . 2>/dev/null; git -C "$W" add -A; git -C "$W" commit -qm "$ID: release approved"
STORY_H0="$(git -C "$MAIN" rev-parse HEAD)"; tip="$(git -C "$W" rev-parse HEAD)"
git -C "$MAIN" merge -q --squash "feature/$SLUG"; git -C "$MAIN" commit -qm "$ID: release approved (squash-merge of feature/$SLUG)" -m "Story-Branch: feature/$SLUG
Story-Tip: $tip"
sq="$(git -C "$MAIN" rev-parse HEAD)"
merged_into_main "feature/$SLUG" && ok "merged_into_main: squash commit whose Story-Tip is the branch tip" || ko "merged_into_main squash"
[ "$(main_merge_of "feature/$SLUG")" = "$sq" ] && ok "main_merge_of returns the squash commit" || ko "main_merge_of=$(main_merge_of "feature/$SLUG")"
mkdir -p "$MAIN/app"; story_on_branch "$SLUG" >/dev/null && ok "H1 story_on_branch accepts the squash" || ko "story_on_branch: $(story_on_branch "$SLUG")"
git -C "$W" commit -q --allow-empty -m "late"; ! merged_into_main "feature/$SLUG" && ok "a branch commit after the squash -> not merged (P1-E rule)" || ko "late commit not caught"
mkdir -p "$EVID/S4-$SLUG-build-1"; echo "x" > "$EVID/S4-$SLUG-build-1/GATE-COMMIT-MISSING"
! bash -c '! ls "$1"/S"$2"-"$3"-*/GATE-COMMIT-MISSING >/dev/null 2>&1' _ "$EVID" 4 "$SLUG" && ok "H7 expression fails when a gate-commit fallback triggered" || ko "H7"
grep -q 'H7_MODE:-fail' "$HERE/scripts/run-plan.sh" && ok "H7 counts as a failure by default" || ko "H7 default"
# harness_complete fallback for a design gate the agent did not commit
RUN="$EVID/S4-$SLUG-design-1"; mkdir -p "$RUN"; k=2; STORY_SLUG="$SLUG"; STORY_KIND=feature; SEMI=0
git -C "$W" rev-parse HEAD > "$RUN/head-before-2"; echo d >> "$W/README.md"
harness_complete design "Shell(git:commit*)" "$W/$SF"
[ "$SEMI" = 1 ] && [ -s "$RUN/GATE-COMMIT-MISSING" ] && grep -q 'FINDING gate-commit missing: orders design' "$STATUS_LOG" \
  && ok "harness fallback commit on a design gate -> SEMI + FINDING + GATE-COMMIT-MISSING" || ko "fallback label (SEMI=$SEMI)"

echo "-- R9 chain_resume_prepare: an in-story resume rolls back first (and not when a gate is pending)"
eval "$(awk '/^chain_resume_prepare\(\)\{/{p=1} p{print} p&&/^  return "\$ok"; \}/{exit}' "$HERE/scripts/run-plan.sh")"
restore(){ return 1; }
crp(){ CRS=P1-A; CRS_PREV=P0-A; CRS_SKIP_IDS=""; CRS_IN_STORY=1; CRS_IN_STORY_SLUG=""; A="$RES/attempt-1"
  printf '1\tP0-A\tp0\n2\tP1-A\t%s\n' "$SLUG" > "$RES/chain.tsv"; : > "$A/story-ids.tsv"; chain_resume_prepare "$A"; CRP_RC=$?; }
setup r9; git -C "$W" rm -q --cached untracked.log 2>/dev/null; crp
[ "$CRP_RC" = 0 ] && [ "$(git -C "$W" rev-parse HEAD)" = "$BUILD_SHA" ] && [ "$CRS_IN_STORY_SLUG" = "$SLUG" ] && grep -q 'ROLLBACK orders to build gate' "$RES/attempt-1/chain-resume-check.log" \
  && ok "in-story resume reset feature/$SLUG to the build gate, then continues" || ko "rc=$CRP_RC $(tail -5 "$RES/attempt-1/chain-resume-check.log")"
setup r9b; st '{"approvedPhases":["intake","design","build"],"lastApprovedPhase":"build","activePhase":"verify","activeStatus":"awaiting_approval","verifyPassed":true}'; crp
[ "$CRP_RC" = 0 ] && [ ! -f "$RES/attempt-1/rollback.txt" ] && ok "pending verify gate -> no rollback (the scripted approval is sent)" || ko "rc=$CRP_RC"
setup r9c; CHAIN_RESUME_ROLLBACK=0; crp; unset CHAIN_RESUME_ROLLBACK
[ "$CRP_RC" = 0 ] && [ ! -f "$RES/attempt-1/rollback.txt" ] && ok "CHAIN_RESUME_ROLLBACK=0 keeps the old in-story behaviour" || ko "rc=$CRP_RC"
echo "== test-rollback: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
