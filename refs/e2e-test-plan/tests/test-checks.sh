#!/usr/bin/env bash
# test-checks.sh — offline tests of the discriminating story checks (HARNESS-FIX 2026-10-31, kitfix-20261031 fix 4):
#   H1 branch part (story_on_branch), H3 at time level (phases_in_order), H6 (ac_count_matches), V1 (native_verify),
#   the no-worktree fail-fast in drive_story, the summary Validity block, and the AGENT_TZ default.
# Usage: bash tests/test-checks.sh
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
expect(){ local want="$1" name="$2"; shift 2; if ( "$@" ) >"$SB/out" 2>&1; then r=0; else r=1; fi
  if { [ "$want" = pass ] && [ "$r" = 0 ]; } || { [ "$want" = fail ] && [ "$r" = 1 ]; }; then ok "$name"; else ko "$name (wanted $want): $(head -3 "$SB/out")"; fi; }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; RES="$TEST_ROOT/results"; EVID="$TEST_ROOT/evidence"
mkdir -p "$TEST_ROOT/status" "$RES" "$EVID"; PLAN_DIR="$HERE"; MAX_RUNS_PER_STORY=8 P0A_SLUG=p0-a-platform-skeleton
. "$HERE/scripts/lib.sh"
g(){ git -C "$MAIN" "$@"; }
newrepo(){ MAIN="$SB/$1/portal"; WORK="$SB/$1"; mkdir -p "$MAIN/app/backend"; g init -q -b main; g config user.email t@example.invalid; g config user.name t
  echo base > "$MAIN/app/backend/A.java"; g add -A; g commit -qm base; }

echo "-- H1 branch part"
newrepo good; STORY_H0="$(g rev-parse HEAD)"
g checkout -qb feature/s1; echo work > "$MAIN/app/backend/S1.java"; g add -A; g commit -qm "s1 work"; g checkout -q main
g merge -q --no-ff -m "Merge branch 'feature/s1'" feature/s1
expect pass "story built on feature/s1 and merged with --no-ff" story_on_branch s1
newrepo onmain; STORY_H0="$(g rev-parse HEAD)"
echo work > "$MAIN/app/backend/S1.java"; g add -A; g commit -qm "s1 work on main"; g branch feature/s1
expect fail "story built on main (run 3, P2-A) -> H1 fails" story_on_branch s1
newrepo stray; STORY_H0="$(g rev-parse HEAD)"
g checkout -qb feature/s1; echo work > "$MAIN/app/backend/S1.java"; g add -A; g commit -qm "s1 work"; g checkout -q main
echo fix > "$MAIN/app/backend/B.java"; g add -A; g commit -qm "app change straight on main"; g merge -q --no-ff -m "Merge branch 'feature/s1'" feature/s1
expect fail "an app/ commit on main beside the merge -> H1 fails" story_on_branch s1
newrepo nobranch; STORY_H0="$(g rev-parse HEAD)"
expect fail "no feature branch at all -> H1 fails" story_on_branch s1

echo "-- H3 at time level"
st(){ printf '%s\n' "$1" > "$SB/st.json"; echo "$SB/st.json"; }
expect pass "phaseTimes in order across midnight Asia/Manila" phases_in_order "$(st '{"phaseDates":{"intake":"2026-10-29","design":"2026-10-29","build":"2026-10-30","verify":"2026-10-30","release":"2026-10-30"},"phaseTimes":{"intake":"2026-10-29T23:10:00+08:00","design":"2026-10-29T23:50:00+08:00","build":"2026-10-30T00:30:00+08:00","verify":"2026-10-30T01:00:00+08:00","release":"2026-10-30T01:20:00+08:00"}}')"
expect fail "phaseTimes out of order within one day -> H3 fails (the day check missed this)" phases_in_order "$(st '{"phaseDates":{"intake":"2026-10-30","design":"2026-10-30","build":"2026-10-30","verify":"2026-10-30","release":"2026-10-30"},"phaseTimes":{"intake":"2026-10-30T10:00:00+08:00","design":"2026-10-30T12:00:00+08:00","build":"2026-10-30T11:00:00+08:00","verify":"2026-10-30T13:00:00+08:00","release":"2026-10-30T14:00:00+08:00"}}')"
expect pass "mixed offsets compare as instants (UTC agent time vs Manila)" phases_in_order "$(st '{"phaseTimes":{"intake":"2026-10-29T16:10:00+00:00","design":"2026-10-30T00:20:00+08:00","build":"2026-10-30T00:30:00+08:00","verify":"2026-10-30T01:00:00+08:00","release":"2026-10-30T01:20:00+08:00"}}')"
expect fail "phaseDates fallback: verify dated before build (P2-A run 4) -> H3 fails" phases_in_order "$(st '{"phaseDates":{"intake":"2026-10-30","design":"2026-10-30","build":"2026-10-30","verify":"2026-10-29","release":"2026-10-30"}}')"
expect pass "phaseDates fallback in order" phases_in_order "$(st '{"phaseDates":{"intake":"2026-10-29","design":"2026-10-29","build":"2026-10-30","verify":"2026-10-30","release":"2026-10-30"}}')"
GOODT='{"phaseTimes":{"intake":"2026-10-30T10:00:00+08:00","design":"2026-10-30T11:00:00+08:00","build":"2026-10-30T12:00:00+08:00","verify":"2026-10-30T13:00:00+08:00","release":"2026-10-30T14:00:00+08:00"}}'
mkdir -p "$EVID/S4-s1-intake-1" "$EVID/S4-s1-design-1"
printf '2026-10-30 10:00:00\tturn-2\tSENT\tgate=intake\tstate=x\ttext=t\tallow=-\n' > "$EVID/S4-s1-intake-1/approvals.log"
printf '2026-10-30 09:00:00\tturn-2\tSENT\tgate=design\tstate=x\ttext=t\tallow=-\n' > "$EVID/S4-s1-design-1/approvals.log"
expect fail "approvals.log: design SENT before intake SENT -> H3 fails" phases_in_order "$(st "$GOODT")" "$EVID/S4-s1-"
printf '2026-10-30 11:00:00\tturn-2\tSENT\tgate=design\tstate=x\ttext=t\tallow=-\n' > "$EVID/S4-s1-design-1/approvals.log"
expect pass "approvals.log SENT rows in order" phases_in_order "$(st "$GOODT")" "$EVID/S4-s1-"

echo "-- H6 AC count"
newrepo h6; mkdir -p "$MAIN/docs/agents-v0/requirements"; R="$MAIN/docs/agents-v0/requirements/s1.md"
{ echo "# S1"; for i in 1 2 3 4 5 6 7; do echo "### AC-$i — x"; done; } > "$R"
expect fail "7 ACs written, plan Size 8 (P2-F, P2-P) -> H6 flags it" ac_count_matches s1 8
expect pass "7 ACs, plan 7" ac_count_matches s1 7
echo "Plan deviation: AC-8 moved to P3-B, approved at Intake" >> "$R"
expect pass "a recorded plan deviation excuses the mismatch" ac_count_matches s1 8
grep -q 'H6_MODE:-warn' "$HERE/scripts/run-plan.sh" && ok "H6 warns by default (D8), H6_MODE=fail makes it fail" || ko "H6 default is not warn"

echo "-- V1 native verify"
newrepo v1; mkdir -p "$MAIN/docs/agents-v0" "$MAIN/.agents-v0/scripts"
cp "$HERE/../../templates/.agents-v0/scripts/run-backend-verify.sh" "$MAIN/.agents-v0/scripts/"
printf '# Profile\n\n## Commands\n\n| Command | Value |\n|---|---|\n| Backend verify | `true` |\n| Frontend verify | `false` |\n' > "$MAIN/docs/agents-v0/project-profile.md"
expect pass "backend verify command from the profile passes" native_verify s1 backend
mkdir -p "$MAIN/app/frontend"; echo '{}' > "$MAIN/app/frontend/package.json"
expect fail "a frontend story whose frontend verify fails -> V1 fails" native_verify s1 frontend
NATIVE_VERIFY=0 expect pass "NATIVE_VERIFY=0 skips V1" native_verify s1 frontend

echo "-- drive_story fail-fast (1e)"
newrepo ff; mkdir -p "$MAIN/docs/agents-v0/requirements"
echo '{"approvedPhases":["intake"],"lastApprovedPhase":"intake","activePhase":null,"activeStatus":null}' > "$MAIN/docs/agents-v0/requirements/s1.state.json"
drive_run(){ echo "drive_run called: $*" >> "$SB/ff.calls"; RUN_END=NORMAL-END; }
drive_story S4 feature s1 0 >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && [ ! -s "$SB/ff.calls" ] && grep -q 'STUCK s1 intake approved but no feature/s1 worktree (next: design)' "$STATUS_LOG" \
  && ok "intake approved, no feature/s1 worktree -> STUCK before any run on main" || ko "rc=$rc calls=$(cat "$SB/ff.calls" 2>/dev/null)"

echo "-- Validity block and AGENT_TZ"
eval "$(sed -n '/^orn(){/,/^write_summary(){/p' "$HERE/scripts/run-plan.sh" | sed '$d')"
printf 'PREREQ os OK\nPREREQ container DEGRADED no docker\n' > "$RES/preflight.txt"
mkdir -p "$EVID/S4-x-build-1"; echo "2026-10-30 10:00:00 build: committed pending files in /w" > "$EVID/S4-x-build-1/SEMI-SYNTHETIC"
printf 'kit_label=kit-a\n' > "$RES/run.meta"; printf 'resume_2=t step=4 reason=r old_kit=kit-a new_kit=kit-b harness_sha=abc\n' >> "$RES/run.meta"
printf 't\t4\tP2-F\tH6\tFAIL\td\n' > "$RES/checks.tsv"; printf 't\tP2-F\tp2-f\tkit-b\tabc\tPASS\n' > "$RES/story-versions.tsv"
validity_block > "$SB/v.md"
grep -q 'DEGRADED prereqs: container' "$SB/v.md" && ok "DEGRADED prereq listed" || ko "no DEGRADED: $(cat "$SB/v.md")"
grep -q 'SEMI-SYNTHETIC labels: build x1' "$SB/v.md" && ok "SEMI-SYNTHETIC kinds counted" || ko "no SEMI count"
grep -q 'H6 AC-count warnings: P2-F' "$SB/v.md" && ok "H6 warnings listed" || ko "no H6 line"
grep -q 'Single version: no' "$SB/v.md" && ok "two kit versions -> single version: no" || ko "single-version wrong"
grep -q '| P2-F | p2-f | kit-b | abc | PASS |' "$SB/v.md" && ok "story -> kit -> harness table" || ko "no story table"
echo "-- run README gets the Validity block (kitfix-20261031-run-readme)"
TEST_ROOT_SAVE="$TEST_ROOT"; TEST_ROOT="$SB/runA"; mkdir -p "$TEST_ROOT"; RR="$TEST_ROOT/README.md"
write_run_readme
[ -f "$RR" ] && head -1 "$RR" | grep -q '^# agents-v0 kit e2e results: run runA' && grep -q 'DEGRADED prereqs: container' "$RR" \
  && grep -q 'SEMI-SYNTHETIC labels: build x1' "$RR" && grep -q '| P2-F | p2-f | kit-b | abc | PASS |' "$RR" \
  && ok "missing README -> created with header + Validity block (DEGRADED, SEMI, story/kit/harness)" || ko "new README: $(cat "$RR" 2>/dev/null)"
printf '# Hand-written outcome\n\n**Outcome: PASS.** memory 2.2 GB\n' > "$RR"
write_run_readme
grep -q 'Outcome: PASS.\*\* memory 2.2 GB' "$RR" && [ "$(grep -c 'agents-v0-validity:begin' "$RR")" = 1 ] && grep -q 'Single version: no' "$RR" \
  && ok "hand-written README kept, block appended once" || ko "append: $(cat "$RR")"
printf '\n## Contents\n\n- results/\n' >> "$RR"
printf 'PREREQ os OK\n' > "$RES/preflight.txt"; printf 't\tP2-G\tp2-g\tkit-c\tdef\tPASS\n' >> "$RES/story-versions.tsv"
write_run_readme
[ "$(grep -c 'agents-v0-validity:begin' "$RR")" = 1 ] && [ "$(grep -c 'agents-v0-validity:end' "$RR")" = 1 ] \
  && grep -q 'DEGRADED prereqs: none' "$RR" && ! grep -q 'DEGRADED prereqs: container' "$RR" && grep -q '| P2-G | p2-g | kit-c | def | PASS |' "$RR" \
  && grep -q 'Outcome: PASS' "$RR" && tail -1 "$RR" | grep -q '^- results/' \
  && ok "rerun replaces only the marked block (new values), text before and after kept" || ko "replace: $(cat "$RR")"
ls "$TEST_ROOT" | grep -q 'README.md.tmp' && ko "temp README left behind" || ok "no temp README left behind"
# write_summary writes the README too (the harness path, not a manual copy)
eval "$(sed -n '/^write_summary(){/,/^# chain_resume_prepare/p' "$HERE/scripts/run-plan.sh" | sed '$d')"
post(){ :; }; KIT_URL=u KIT_REF=r AGENT_MODEL=m ASK_MODE=allowlist TARGET_SURFACE=; : > "$RES/results.tsv"
TEST_ROOT="$SB/runB"; mkdir -p "$TEST_ROOT"; write_summary
[ -s "$RES/summary.md" ] && grep -q '## Validity' "$TEST_ROOT/README.md" && grep -q 'agents-v0-validity:end' "$TEST_ROOT/README.md" \
  && ok "write_summary -> run README.md has the Validity block" || ko "write_summary did not write the run README"
TEST_ROOT="$TEST_ROOT_SAVE"
grep -q 'TZ="${AGENT_TZ:-Asia/Manila}"' "$HERE/scripts/lib.sh" && grep -q 'TZ="${AGENT_TZ:-Asia/Manila}"' "$HERE/scripts/agy-turn-loop.sh" \
  && ok "AGENT_TZ defaults to Asia/Manila in lib.sh and agy-turn-loop.sh" || ko "AGENT_TZ default"
echo "== test-checks: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
