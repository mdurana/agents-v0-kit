#!/usr/bin/env bash
# test-guards.sh — offline tests for the harness guard checks added by kitfix-20261031-guard-override
# (second review of dd980e6):
#   H8 guard_override_scan: an AGENTS_V0_* assignment in a turn's commands or in a non-markdown file it wrote;
#   H9 gate_chain / gate_chain_check / gate_chain_ok: the story's gate commits survive every turn and stay in order
#      (catches --amend, reset, rebase, forced ref moves).
# Usage: bash tests/test-guards.sh   (exit 0 when every case passes)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; mkdir -p "$TEST_ROOT/status"
PLAN_DIR="$HERE"; MAX_TURNS=30 MAX_ANSWERS=3 MAX_RETRY_INFRA=1 INFRA_BACKOFF=0 TURN_PAUSE_SEC=0 RUN_TIMEOUT=600 RUN_TIMEOUT_P0A=600
MAX_RUNS_PER_STORY=8 HEARTBEAT_SEC=99999 P0A_SLUG=p0-a-platform-skeleton KIT_REF=test KIT_LABEL=test
. "$HERE/scripts/lib.sh"
EVID="$TEST_ROOT/evidence"; RES="$TEST_ROOT/results"; mkdir -p "$EVID" "$RES"
g(){ git -C "$WS" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
MAIN="$SB/main"; git init -q -b main "$MAIN"; echo base > "$MAIN/README.md"
git -C "$MAIN" add -A; git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid commit -qm base
WS="$SB/portal-s1"; git -C "$MAIN" worktree add -q -b feature/s1 "$WS" main
gate(){ echo "$1" >> "$WS/log.txt"; g add -A; g commit -qm "S1: $1 approved"; }

echo "-- H8 guard_override_scan"
RUN="$EVID/S4-s1-design-1"; mkdir -p "$RUN"; k=1; g rev-parse HEAD > "$RUN/head-before-$k"
printf '%s\n' 'git status' 'echo "$AGENTS_V0_TZ"' 'grep -n AGENTS_V0_TZ docs/agents-v0/project-profile.md' 'test -n "${AGENTS_V0_TZ:-}"' > "$RUN/commands-$k.txt"
mkdir -p "$WS/docs"; echo 'Run with `AGENTS_V0_TRACE_MODE=fail` to refuse.' > "$WS/docs/notes.md"
guard_override_scan $k
[ ! -e "$RUN/guard-override.txt" ] && ok "reading AGENTS_V0_* and a markdown mention are not overrides" || ko "false positive: $(cat "$RUN/guard-override.txt")"
for c in 'AGENTS_V0_SKIP_BRANCH_GUARD=1 sh .agents-v0/scripts/sync-feature-state.sh --approve build r.md' \
         'export AGENTS_V0_SKIP_COMMIT_CHECK=1' 'env AGENTS_V0_NOW=2026-10-30T00:30:00+08:00 sh x' \
         'bash -c "declare -x AGENTS_V0_TRACE_MODE=warn; sh y"' 'echo ${AGENTS_V0_TRACE_MODE:=warn}' \
         'python3 -c "import os; os.environ[\"AGENTS_V0_NOW\"]=\"x\""'; do
  R="$EVID/S4-s1-c-$PASS"; mkdir -p "$R"; RUN="$R"; g rev-parse HEAD > "$RUN/head-before-1"; printf '%s\n' "$c" > "$RUN/commands-1.txt"
  guard_override_scan 1
  grep -q 'turn-1 command:' "$RUN/guard-override.txt" 2>/dev/null && ok "command flagged: $c" || ko "not flagged: $c"
done
RUN="$EVID/S4-s1-build-1"; mkdir -p "$RUN"; g rev-parse HEAD > "$RUN/head-before-1"; : > "$RUN/commands-1.txt"
mkdir -p "$WS/tools"; printf '#!/bin/sh\nexport AGENTS_V0_SKIP_BRANCH_GUARD=1\nsh .agents-v0/scripts/sync-feature-state.sh "$@"\n' > "$WS/tools/approve.sh"
guard_override_scan 1
grep -q 'turn-1 file: tools/approve.sh' "$RUN/guard-override.txt" 2>/dev/null && ok "a script the turn wrote that sets AGENTS_V0_* is flagged" || ko "script not flagged"
grep -q 'FINDING H8 run=S4-s1-build-1' "$STATUS_LOG" && ok "H8 FINDING posted" || ko "no H8 FINDING"
mkdir -p "$SB/trash"; mv "$WS/tools" "$WS/docs" "$SB/trash/"

echo "-- H9 gate chain"
gate intake; gate design
RUN="$EVID/S4-s1-build-2"; mkdir -p "$RUN"
gate_chain "$WS" HEAD > "$RUN/gate-chain-before-1.tsv"
[ "$(cut -f2 "$RUN/gate-chain-before-1.tsv" | paste -sd' ' -)" = "intake design" ] && ok "gate_chain lists the story's gate commits in order" || ko "chain: $(cat "$RUN/gate-chain-before-1.tsv")"
echo b > "$WS/b.txt"; g add -A; g commit -qm "chore(s1): build evidence [harness-complete]"; gate build
gate_chain_check 1
[ ! -e "$RUN/GATE-CHAIN-BROKEN" ] && ok "new commits on top keep the chain (harness commits ignored)" || ko "false break: $(cat "$RUN/GATE-CHAIN-BROKEN")"
RUN="$EVID/S4-s1-verify-1"; mkdir -p "$RUN"; gate_chain "$WS" HEAD > "$RUN/gate-chain-before-1.tsv"
echo amended >> "$WS/b.txt"; g add -A; g commit -q --amend -m "S1: build approved"
gate_chain_check 1
grep -q 'gate commit .* (build) is no longer on feature/s1' "$RUN/GATE-CHAIN-BROKEN" 2>/dev/null && ok "--amend of a gate commit -> GATE-CHAIN-BROKEN" || ko "amend not caught"
grep -q 'FINDING H9 run=S4-s1-verify-1' "$STATUS_LOG" && ok "H9 FINDING posted" || ko "no H9 FINDING"
RUN="$EVID/S4-s1-verify-2"; mkdir -p "$RUN"; gate_chain "$WS" HEAD > "$RUN/gate-chain-before-1.tsv"
g reset -q --soft HEAD~1; echo again >> "$WS/b.txt"; g add -A; g commit -qm "S1: build approved"
gate_chain_check 1
grep -q '(build) is no longer on' "$RUN/GATE-CHAIN-BROKEN" 2>/dev/null && ok "reset --soft + recommit -> GATE-CHAIN-BROKEN" || ko "reset not caught"
RUN="$EVID/S4-s1-verify-3"; mkdir -p "$RUN"; gate_chain "$WS" HEAD > "$RUN/gate-chain-before-1.tsv"
gate verify; gate intake
gate_chain_check 1
grep -q 'out of order: .*(intake) comes after verify' "$RUN/GATE-CHAIN-BROKEN" 2>/dev/null && ok "an intake gate after verify -> out of order" || ko "order not caught: $(cat "$RUN/GATE-CHAIN-BROKEN" 2>/dev/null)"
echo "-- H9 check (gate_chain_ok) and wiring"
gate_chain "$MAIN" feature/s1 > "$RES/gate-chain-s1.tsv"
gate_chain_ok 4 s1 "$RES/gate-chain-s1.tsv" && ko "H9 passed with broken runs" || ok "H9 fails when a run recorded GATE-CHAIN-BROKEN"
mkdir -p "$SB/ev2"; EVID="$SB/ev2"; printf 'a\tintake\nb\tdesign\nc\tbuild\nd\tverify\ne\trelease\n' > "$SB/c.tsv"
gate_chain_ok 4 s1 "$SB/c.tsv" && ok "H9 passes for a clean, ordered chain" || ko "clean chain failed"
: > "$SB/e.tsv"; gate_chain_ok 4 s1 "$SB/e.tsv" && ko "H9 passed with no gate commits" || ok "H9 fails with no gate commits on the branch"
gate_chain "$MAIN" main | grep -q . && ko "gate_chain listed main" || ok "gate_chain ignores a non-story branch"
grep -q 'chk "$st" "$id" H8 ' "$HERE/scripts/run-plan.sh" && grep -q 'chk "$st" "$id" H9 ' "$HERE/scripts/run-plan.sh" \
  && grep -q 'guard_override_scan "$k"; gate_chain_check "$k"' "$HERE/scripts/lib.sh" && ok "H8/H9 wired into story_run and run_turn" || ko "wiring missing"
grep -q '"${H8_MODE:-fail}" = warn' "$HERE/scripts/run-plan.sh" && grep -q '"${H9_MODE:-fail}" = warn' "$HERE/scripts/run-plan.sh" \
  && ok "H8/H9 fail by default, warn on request" || ko "H8/H9 modes"
echo "== test-guards: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
