#!/usr/bin/env bash
# test-guards.sh — offline tests for the harness guard checks added by kitfix-20261031-guard-override
# (second review of dd980e6):
#   H8 guard_override_scan: an AGENTS_V0_* assignment in a turn's commands or in a non-markdown file it wrote;
#   H9 gate_chain / gate_chain_check / gate_chain_ok: the story's gate commits survive every turn and stay in order
#      (catches --amend, reset, rebase, forced ref moves);
#   H10 kit_integrity / kit_integrity_check / kit_policy_apply / kit_policy_ok / modes_preflight
#      (kitfix-20261031-installed-no-overrides): content hashes of the installed kit, the harness-owned trace mode.
#   kit_source_locked / kit_installed_ok / kit-manifest.sh (kitfix-20261031-kit-source-lock): the agent user cannot read
#      (kitfix-20261031-kit-git-source: nor any *.bundle or kit git repository)
#      the kit source, and the installed kit is checked against a manifest written before the lock.
#   harness_locked / harness_integrity_check / agy-ws-exec.sh / agy-ipc-turn.sh (kitfix-20261031-harness-lock): the
#      agent user cannot write or replace the harness, and a changed harness or allowlist file is caught.
#   run-plan.sh `modes_preflight early` (kitfix-20261031-preflight-first): a refused launch counts no resume.
#   v3_launch_ok / escalation_none_ok / escalation-check.sh / home-hash.sh (kitfix-20261031-launch-env, -escalation-none):
#      a V3 launch cannot be weakened through files the agent user can write, and that user has no escalation path.
# Usage: bash tests/test-guards.sh   (exit 0 when every case passes)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SB="$(mktemp -d)"; trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; mkdir -p "$TEST_ROOT/status"
HARNESS_LOCK_PATHS=/usr/bin   # stands in for the root-owned /opt/harness-v3 (this box user cannot write it)
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
echo "-- H10 installed kit integrity and the trace-mode policy (kitfix-20261031-installed-no-overrides)"
KIT="$(cd "$HERE/../.." && pwd)"; EVID="$TEST_ROOT/evidence"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid   # the harness commits as the VM user
MAIN="$SB/m2"; git init -q -b main "$MAIN"
sh "$KIT/scripts/install.sh" "$MAIN" > "$SB/install.log" 2>&1 || ko "install.sh into m2"
mkdir -p "$MAIN/docs/agents-v0/requirements" "$MAIN/docs/agents-v0/design/s2"
printf '# S2\n\n### AC-1 a\n### AC-2 b\n' > "$MAIN/docs/agents-v0/requirements/s2.md"
printf '# Design\n\n| AC | x |\n|---|---|\n| AC-1 | a |\n' > "$MAIN/docs/agents-v0/design/s2/design.md"
gm(){ git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
gm add -A; gm commit -qm base
KIT_TRACE_MODE=fail kit_policy_apply "test" > /dev/null
[ "$(cat "$MAIN/.agents-v0/policy.conf")" = trace_mode=fail ] && gm log -1 --format=%s | grep -q 'trace_mode=fail (test) \[harness commit\]' \
  && ok "kit_policy_apply writes trace_mode=fail and makes one harness commit" || ko "policy apply: $(gm log -1 --format=%s)"
n0="$(gm rev-list --count HEAD)"; KIT_TRACE_MODE=fail kit_policy_apply "again" > /dev/null
[ "$(gm rev-list --count HEAD)" = "$n0" ] && ok "kit_policy_apply is a no-op when the file already matches" || ko "policy apply not idempotent"
( cd "$MAIN" && sh .agents-v0/scripts/check-traceability.sh --print-mode ) | grep -q '^trace_mode=fail source=policy.conf' && ok "the installed copy reads trace mode fail from policy.conf" || ko "print-mode"
out="$(trace_bad_phase "$MAIN" s2 design)"; [ -z "$(gm status --porcelain)" ] && ok "trace_bad_phase on an installed copy writes nothing (--no-write)" || ko "trace probe dirtied: $(gm status --porcelain)"
k=1; RUN="$EVID/S4-s2-build-1"; mkdir -p "$RUN"; WS="$MAIN"
kit_integrity "$MAIN" "$WS" > "$RUN/kit-integrity-before-$k.tsv"
grep -q $'\t.agents-v0/scripts/sync-feature-state.sh\t' "$RUN/kit-integrity-before-$k.tsv" && grep -q $'\t.agents-v0/policy.conf\t' "$RUN/kit-integrity-before-$k.tsv" \
  && [ "$(cut -f1 "$RUN/kit-integrity-before-$k.tsv" | sort -u | wc -l)" = 1 ] && ok "kit_integrity hashes scripts, hooks and policy.conf (main = ws listed once)" || ko "integrity snapshot"
echo '{"event":"shell"}' >> "$MAIN/.agents/hooks/audit.jsonl"; echo 'Shell(git:commit*)' > "$MAIN/.agents/hooks/unattended-allow"
kit_integrity_check $k
[ ! -e "$RUN/kit-tamper.txt" ] && ok "no change (audit log and allowlist ignored) -> nothing flagged" || ko "false positive: $(cat "$RUN/kit-tamper.txt")"
k=2; RUN="$EVID/S4-s2-build-2"; mkdir -p "$RUN"; kit_integrity "$MAIN" > "$RUN/kit-integrity-before-$k.tsv"
printf '\n# agent edit\n' >> "$MAIN/.agents-v0/scripts/check-traceability.sh"; mkdir -p "$SB/trash"; mv "$MAIN/.agents-v0/policy.conf" "$SB/trash/policy.conf"
kit_integrity_check $k
grep -q 'turn-2 changed .agents-v0/scripts/check-traceability.sh' "$RUN/kit-tamper.txt" 2>/dev/null && ok "an edited installed script -> kit-tamper.txt" || ko "script edit not caught"
grep -q 'turn-2 changed .agents-v0/policy.conf' "$RUN/kit-tamper.txt" 2>/dev/null && ok "a removed policy.conf -> kit-tamper.txt" || ko "policy removal not caught: $(cat "$RUN/kit-tamper.txt" 2>/dev/null)"
grep -q 'FINDING H10 run=S4-s2-build-2' "$STATUS_LOG" && ok "H10 FINDING posted" || ko "no H10 FINDING"
gm checkout -q -- .agents-v0/scripts/check-traceability.sh .agents-v0/policy.conf
k=3; RUN="$EVID/S4-s2-verify-1"; mkdir -p "$RUN"; kit_integrity "$MAIN" > "$RUN/kit-integrity-before-$k.tsv"
( cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --quick --allow-in-flight --test-overrides "$MAIN" ) > "$SB/reinstall.log" 2>&1
kit_integrity_check $k
grep -q 'turn-3 changed .agents-v0/scripts/sync-feature-state.sh' "$RUN/kit-tamper.txt" 2>/dev/null && ok "a reinstall with --test-overrides -> kit-tamper.txt" || ko "reinstall not caught"
sh "$KIT/scripts/check-installed-kit.sh" "$MAIN" > "$SB/cik.out" 2>&1 && ko "check-installed-kit passed a test-override copy" || ok "check-installed-kit.sh flags the reinstalled copy"
gm checkout -q -- .agents-v0
k=4; RUN="$EVID/S4-s2-verify-2"; mkdir -p "$RUN"; kit_integrity "$MAIN" > "$RUN/kit-integrity-before-$k.tsv"
cp "$MAIN/.agents-v0/policy.conf" "$SB/trash/p2"; echo trace_mode=warn > "$MAIN/.agents-v0/policy.conf"; cp "$SB/trash/p2" "$MAIN/.agents-v0/policy.conf"
kit_integrity_check $k
[ ! -e "$RUN/kit-tamper.txt" ] && ok "limit (documented): an edit undone inside the same turn is not seen by the hash check" || ko "unexpected flag"
printf '{"design": {"result": "warn", "mode": "warn"}, "build": {"result": "ok", "mode": "fail"}}\n' > "$MAIN/docs/agents-v0/requirements/s2.trace.json"
KIT_TRACE_MODE=fail kit_policy_ok s2 > "$SB/kpo.out" 2>&1 && ko "kit_policy_ok passed a warn-mode gate" || { grep -q 'not in mode fail: design' "$SB/kpo.out" && ok "kit_policy_ok catches a gate recorded in warn mode (trace.json)" || ko "kpo text"; }
printf '{"design": {"result": "ok", "mode": "fail"}}\n' > "$MAIN/docs/agents-v0/requirements/s2.trace.json"
KIT_TRACE_MODE=fail kit_policy_ok s2 && ok "kit_policy_ok passes when every gate was in fail mode" || ko "kpo clean"
mv "$MAIN/docs/agents-v0/requirements/s2.trace.json" "$SB/trash/"
echo "-- modes_preflight (REQUIRE_FAIL_MODES=1)"
LK="$SB/kit-locked"; mkdir -p "$LK/templates" "$SB/scan"; chmod 000 "$LK"   # stands for the kit source after the lock
export KIT_SOURCE_PATHS="$LK" KIT_SCAN_ROOTS="$SB/scan"
( REQUIRE_FAIL_MODES=1; unset H6_MODE; KIT_TRACE_MODE=fail; modes_preflight ) && ko "preflight passed without H6_MODE=fail" || { grep -q 'H6_MODE=warn (need fail)' "$RES/modes-preflight.log" && ok "preflight refuses H6_MODE unset" || ko "h6 text"; }
( REQUIRE_FAIL_MODES=1 H6_MODE=fail H9_MODE=warn KIT_TRACE_MODE=fail; modes_preflight ) && ko "preflight passed H9_MODE=warn" || ok "preflight refuses H9_MODE=warn"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail; unset KIT_TRACE_MODE; modes_preflight ) && ko "preflight passed without KIT_TRACE_MODE" || ok "preflight refuses KIT_TRACE_MODE unset"
( AGENTS_V0_TRACE_MODE=fail; export AGENTS_V0_TRACE_MODE; modes_preflight ) && ko "preflight accepted AGENTS_V0_TRACE_MODE" || { grep -q 'installed kit scripts ignore it: use KIT_TRACE_MODE' "$RES/modes-preflight.log" && ok "preflight refuses AGENTS_V0_TRACE_MODE in the launch env (it has no effect)" || ko "atm text"; }
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail; modes_preflight ) && grep -q '^OK m2: HASH-OK .*trace_mode=fail' "$RES/modes-preflight.log" \
  && grep -q 'MODES H6=fail .* trace=fail require_fail=1 lock=checked OK' "$STATUS_LOG" && ok "preflight passes with every mode fail and HASH-OK in main" || ko "preflight ok: $(cat "$RES/modes-preflight.log")"
printf '\n# drift\n' >> "$MAIN/.agents-v0/scripts/sync-feature-state.sh"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail; modes_preflight ) && ko "preflight passed a changed installed script" || { grep -q '^FAIL m2: DIFF .agents-v0/scripts/sync-feature-state.sh' "$RES/modes-preflight.log" && ok "preflight refuses a changed installed script" || ko "drift text"; }
gm checkout -q -- .agents-v0
echo "-- kit source lock and manifest (kitfix-20261031-kit-source-lock)"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail KIT_SOURCE_PATHS="$KIT"; modes_preflight ) && ko "preflight passed with a readable kit source" \
  || { grep -q "^LOCK READABLE by $(id -un): $KIT\$" "$RES/modes-preflight.log" && grep -q 'lock=checked REFUSED' "$STATUS_LOG" && ok "preflight refuses a kit source the agent user can read" || ko "lock text: $(cat "$RES/modes-preflight.log")"; }
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail; modes_preflight ) >/dev/null
grep -q "^LOCK ok $LK (not readable by $(id -un))" "$RES/modes-preflight.log" && ok "a root-only (mode 000) kit source counts as locked" || ko "locked dir: $(cat "$RES/modes-preflight.log")"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail KIT_SOURCE_PATHS="$SB/moved-away"; modes_preflight ) && grep -q "^LOCK absent $SB/moved-away" "$RES/modes-preflight.log" \
  && ok "a kit source moved out of reach counts as locked" || ko "absent: $(cat "$RES/modes-preflight.log")"
mkdir -p "$SB/scan/trash/old-worktree/.agents-v0/scripts"; cp "$KIT/templates/.agents-v0/scripts/sync-feature-state.sh" "$SB/scan/trash/old-worktree/.agents-v0/scripts/"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail; modes_preflight ) && ko "preflight passed with a readable unstripped copy" \
  || { grep -q "^LOCK READABLE unstripped kit script for $(id -un): $SB/scan/trash/old-worktree/.agents-v0/scripts/sync-feature-state.sh" "$RES/modes-preflight.log" && ok "preflight refuses a readable unstripped kit copy anywhere under the scan roots (old install, trash)" || ko "scan: $(cat "$RES/modes-preflight.log")"; }
mkdir -p "$SB/trash2"; mv "$SB/scan/trash" "$SB/trash2/"
( KIT_SOURCE_LOCK=1 KIT_SOURCE_PATHS="$KIT"; unset REQUIRE_FAIL_MODES; modes_preflight ) && ko "KIT_SOURCE_LOCK=1 alone not checked" || ok "KIT_SOURCE_LOCK=1 checks the lock without the fail modes"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail AGENT_USER=nobody-such-user; modes_preflight ) && ko "preflight passed for another agent user it cannot test" \
  || { grep -q '^LOCK cannot test as nobody-such-user' "$RES/modes-preflight.log" && ok "preflight refuses when it cannot test as the agent user (not root, not that user)" || ko "other user: $(cat "$RES/modes-preflight.log")"; }
bash "$HERE/scripts/kit-manifest.sh" "$MAIN" "$SB/kit-manifest.tsv" "$KIT" > "$SB/manifest.log" 2>&1 && grep -q '^# kit=' "$SB/kit-manifest.tsv" && grep -q $'^.agents-v0/scripts/sync-feature-state.sh\t' "$SB/kit-manifest.tsv" \
  && ! grep -q 'policy.conf' "$SB/kit-manifest.tsv" && ok "kit-manifest.sh writes the manifest after HASH-OK (policy.conf excluded)" || ko "manifest: $(cat "$SB/manifest.log")"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail KIT="$LK" KIT_MANIFEST="$SB/kit-manifest.tsv"; modes_preflight ) && grep -q '^OK m2: MANIFEST-OK files=.* trace_mode=fail kit=' "$RES/modes-preflight.log" \
  && ok "with the source locked, preflight checks main against the manifest (no kit source needed)" || ko "manifest preflight: $(cat "$RES/modes-preflight.log")"
printf '\n# drift\n' >> "$MAIN/.agents-v0/scripts/check-gate-commit.sh"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail KIT="$LK" KIT_MANIFEST="$SB/kit-manifest.tsv"; modes_preflight ) && ko "manifest preflight passed a changed script" \
  || { grep -q '^FAIL m2: MANIFEST-DIFF' "$RES/modes-preflight.log" && grep -q 'check-gate-commit.sh' "$RES/modes-preflight.log" && ok "manifest preflight refuses a changed installed script" || ko "manifest drift: $(cat "$RES/modes-preflight.log")"; }
gm checkout -q -- .agents-v0
printf 'trace_mode=warn\n' > "$MAIN/.agents-v0/policy.conf"
( KIT_MANIFEST="$SB/kit-manifest.tsv"; kit_installed_ok "$MAIN" ) > "$SB/kio.txt" 2>&1 && ko "kit_installed_ok passed trace_mode=warn" || { grep -q 'TRACE-MODE warn (need fail)' "$SB/kio.txt" && ok "kit_installed_ok refuses trace_mode=warn" || ko "kio: $(cat "$SB/kio.txt")"; }
gm checkout -q -- .agents-v0
( KIT_MANIFEST="$SB/none.tsv"; kit_installed_ok "$MAIN" ) > "$SB/kio.txt" 2>&1 && ko "kit_installed_ok passed without its manifest" || ok "kit_installed_ok refuses a missing manifest"
echo "-- kit bundles and kit git repositories (kitfix-20261031-kit-git-source)"
KG="$SB/kgit"; mkdir -p "$KG/templates/.agents-v0/scripts"; cp "$KIT/templates/.agents-v0/scripts/sync-feature-state.sh" "$KG/templates/.agents-v0/scripts/"
git -C "$KG" init -q -b main; git -C "$KG" add -A; git -C "$KG" commit -qm kit
pf(){ ( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail; modes_preflight ); }
mkdir -p "$SB/scan/lib"; git -C "$SB/scan/lib" init -q -b main; echo a > "$SB/scan/lib/a"; git -C "$SB/scan/lib" add -A; git -C "$SB/scan/lib" commit -qm lib
pf && grep -q 'LOCK git scan ok: no readable \*.bundle, [1-9][0-9]* git dirs checked' "$RES/modes-preflight.log" && ok "an unrelated git repo under the scan roots is checked and passes" || ko "lib repo: $(cat "$RES/modes-preflight.log")"
git -C "$KG" bundle create "$SB/scan/kitfix.bundle" main 2>/dev/null
pf && ko "preflight passed with a readable kit bundle" || { grep -q "^LOCK READABLE git bundle for $(id -un): $SB/scan/kitfix.bundle" "$RES/modes-preflight.log" && ok "preflight refuses a readable *.bundle" || ko "bundle: $(cat "$RES/modes-preflight.log")"; }
chmod 000 "$SB/scan/kitfix.bundle"
pf && ok "a root-only (mode 000) bundle is accepted" || ko "000 bundle: $(cat "$RES/modes-preflight.log")"
git clone -q --bare "$KG" "$SB/scan/kit-mirror.git"
pf && ko "preflight passed with a readable kit mirror" || { grep -q "^LOCK READABLE kit git repository for $(id -un): $SB/scan/kit-mirror.git" "$RES/modes-preflight.log" && ok "preflight refuses a readable bare kit mirror" || ko "mirror: $(cat "$RES/modes-preflight.log")"; }
mv "$SB/scan/kit-mirror.git" "$SB/trash2/"
git clone -q "$KG" "$SB/scan/kit-clone"
pf && ko "preflight passed with a readable kit clone" || { grep -q "^LOCK READABLE kit git repository for $(id -un): $SB/scan/kit-clone/.git" "$RES/modes-preflight.log" && ok "preflight refuses a readable kit clone" || ko "clone: $(cat "$RES/modes-preflight.log")"; }
mv "$SB/scan/kit-clone" "$SB/trash2/"
git -C "$SB/scan/lib" fetch -q "$KG" main 2>/dev/null
pf && ko "preflight passed a repo whose FETCH_HEAD is the kit" || { grep -q "^LOCK READABLE kit git repository for $(id -un): $SB/scan/lib/.git" "$RES/modes-preflight.log" && ok "preflight refuses a repo that fetched the kit (FETCH_HEAD)" || ko "fetch_head: $(cat "$RES/modes-preflight.log")"; }
mv "$SB/scan/lib" "$SB/trash2/lib-fetched"
mkdir -p "$SB/scan/rooted"; git clone -q "$KG" "$SB/scan/rooted"; git -C "$SB/scan/rooted" rm -rq templates; git -C "$SB/scan/rooted" commit -qm drop; git -C "$SB/scan/rooted" remote remove origin
pf && ok "a repo whose tips no longer hold templates/ passes when its root is not a known kit root" || ko "rooted unknown: $(cat "$RES/modes-preflight.log")"
( KIT_ROOT_COMMITS="$(git -C "$KG" rev-list --max-parents=0 HEAD)"; pf ) && ko "preflight passed a repo holding a kit root commit" \
  || { grep -q "^LOCK READABLE kit git repository for $(id -un): $SB/scan/rooted/.git" "$RES/modes-preflight.log" && ok "preflight refuses a repo whose objects hold a kit root commit" || ko "rooted: $(cat "$RES/modes-preflight.log")"; }
mv "$SB/scan/rooted" "$SB/trash2/"
grep -q '^KIT_ROOT_COMMITS=.*550da9df6dcfb46995d5af2adced25e21d372bd9.*fc4b642cb947cf38b5fea7cc1005e22d58e17eef' "$HERE/scripts/lib.sh" \
  && grep -q 'KIT_ROOT_COMMITS = ("550da9df6dcfb46995d5af2adced25e21d372bd9", "fc4b642cb947cf38b5fea7cc1005e22d58e17eef")' "$KIT/core/common/hooks/hook-policy.py" \
  && ok "harness and hook list the same kit root commits" || ko "root commit lists differ"
echo "-- harness lock (kitfix-20261031-harness-lock)"
HC="$SB/hcopy"; mkdir -p "$HC"; cp -a "$HERE/scripts" "$HERE/fixtures" "$HC/"
harness_locked > "$SB/hl.log" 2>&1 && grep -q '^HARNESS ok /usr/bin' "$SB/hl.log" && ok "a harness the agent user cannot write or move passes" || ko "root-owned harness: $(cat "$SB/hl.log")"
( HARNESS_LOCK_PATHS="$HC"; harness_locked ) > "$SB/hl.log" 2>&1 && ko "a writable harness passed" \
  || { grep -q "^HARNESS WRITABLE by $(id -un): $HC" "$SB/hl.log" && ok "preflight refuses a harness the agent user can write" || ko "writable text: $(cat "$SB/hl.log")"; }
chmod -R a-w "$HC"
( HARNESS_LOCK_PATHS="$HC"; harness_locked ) > "$SB/hl.log" 2>&1 && ko "a read-only harness in a writable folder passed" \
  || { grep -q "^HARNESS REPLACEABLE by $(id -un): $SB is writable" "$SB/hl.log" && ! grep -q WRITABLE "$SB/hl.log" && ok "preflight refuses a read-only harness the agent user could move aside" || ko "replaceable text: $(cat "$SB/hl.log")"; }
chmod -R u+w "$HC"
( REQUIRE_FAIL_MODES=1 H6_MODE=fail KIT_TRACE_MODE=fail HARNESS_LOCK_PATHS="$HC"; modes_preflight ) && ko "preflight passed with a writable harness" \
  || { grep -q '^HARNESS WRITABLE' "$RES/modes-preflight.log" && ok "REQUIRE_FAIL_MODES=1 runs the harness lock" || ko "preflight hl: $(cat "$RES/modes-preflight.log")"; }
( HARNESS_LOCK=1 HARNESS_LOCK_PATHS="$HC"; unset REQUIRE_FAIL_MODES; modes_preflight ) && ko "HARNESS_LOCK=1 alone not checked" || ok "HARNESS_LOCK=1 checks the harness lock without the fail modes"
( AGENT_USER=nobody-such-user; harness_locked ) > "$SB/hl.log" 2>&1 && ko "harness lock passed for an agent user it cannot test" \
  || { grep -q '^HARNESS cannot test as nobody-such-user' "$SB/hl.log" && ok "harness lock refuses an agent user it cannot test" || ko "untestable: $(cat "$SB/hl.log")"; }
# H10 detector: a harness file or the allowlist file changed during a turn
RUN="$EVID/S4-s1-harness-1"; mkdir -p "$RUN"; k=1
( PLAN_DIR="$HC"; harness_integrity > "$RUN/harness-integrity-before-$k.tsv"; harness_integrity_check $k ); [ ! -e "$RUN/kit-tamper.txt" ] && ok "an unchanged harness is not a finding" || ko "false harness tamper"
( PLAN_DIR="$HC"; harness_integrity > "$RUN/harness-integrity-before-$k.tsv"; printf 'x\ty\n' >> "$HC/fixtures/approvals.tsv"; harness_integrity_check $k )
grep -q '^turn-1 changed harness fixtures/approvals.tsv' "$RUN/kit-tamper.txt" 2>/dev/null && grep -q 'FINDING H10 .*changed the harness' "$STATUS_LOG" && ok "a fixture changed during a turn is an H10 finding" || ko "harness tamper: $(cat "$RUN/kit-tamper.txt" 2>/dev/null)"
RUN="$EVID/S4-s1-harness-2"; mkdir -p "$RUN"; echo "harness status/pending-turn.json changed during turn 1 (sha a, written b)" > "$RUN/pending-tamper-1.txt"
( PLAN_DIR="$HC"; harness_integrity > "$RUN/harness-integrity-before-1.tsv"; harness_integrity_check 1 )
grep -q '^turn-1 harness status/pending-turn.json changed' "$RUN/kit-tamper.txt" 2>/dev/null && ok "a changed allowlist file is an H10 finding" || ko "pending tamper not reported"
grep -q 'harness_integrity_check "$k"' "$HERE/scripts/lib.sh" && grep -q 'harness_integrity > "$RUN/harness-integrity-before-$k.tsv"' "$HERE/scripts/lib.sh" && ok "run_turn checks the harness before and after every turn" || ko "harness integrity not wired"
# agy-ipc-turn.sh records a pending-turn.json changed during the turn; agy-ws-exec.sh refuses a file that differs from the turn's allowlist
IR="$SB/ipc"; IWS="$IR/work/ws"; mkdir -p "$IR/status" "$IR/evidence/S4-x-1" "$IWS/.agents/hooks" "$IR/agy-driver"; IRUN="$IR/evidence/S4-x-1"
printf '#!/bin/sh\ncat > /dev/null; echo "{\\"permission\\": \\"allow\\"}"\n' > "$IWS/.agents/hooks/pre-shell.sh"   # stub hook: allow
wx(){ env TEST_ROOT="$IR" AGY_ALLOW_TOOLS='Shell(git:commit*)' AGY_TURN_WS="$IWS" "$@"; }
( TEST_ROOT="$IR" bash "$HERE/scripts/agy-ipc-turn.sh" chat "$IWS" m "hello" 'Shell(git:commit*)' "$IRUN" 1 > /dev/null ) & ipid=$!
for _ in $(seq 1 50); do [ -s "$IR/status/pending-turn.json" ] && break; sleep 0.1; done
wx bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo ran-ok' > "$SB/wx.out" 2>&1 && grep -q ran-ok "$SB/wx.out" && ok "the wrapper runs a command when the file matches the turn's allowlist" || ko "wrapper match: $(cat "$SB/wx.out")"
WTD="$SB/wtools"; mkdir -p "$WTD"; echo 'export JAVA_HOME=/pwned-jh' > "$WTD/tools.env"
wx env -u JAVA_HOME TOOLS_DIR="$WTD" REQUIRE_FAIL_MODES=1 bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo "jh=${JAVA_HOME:-}"' > "$SB/wxt.out" 2>&1
wx env -u JAVA_HOME TOOLS_DIR="$WTD" REQUIRE_FAIL_MODES=0 bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo "jh=${JAVA_HOME:-}"' > "$SB/wxt0.out" 2>&1
grep -q '^jh=' "$SB/wxt.out" && ! grep -q pwned-jh "$SB/wxt.out" && grep -q '^jh=/pwned-jh' "$SB/wxt0.out" \
  && ok "the wrapper loads no writable tools.env with REQUIRE_FAIL_MODES=1 (still loads it when attended)" || ko "wrapper tools.env: $(cat "$SB/wxt.out" "$SB/wxt0.out")"
# kitfix-20261031-ws-exec (Sasuke round 2): the wrapper fails closed
wxr(){ "$@" > "$SB/wx.out" 2>&1; local r=$?; [ "$r" = 2 ] && ! grep -q ran-bad "$SB/wx.out"; }
wxr env TEST_ROOT="$IR" AGY_ALLOW_TOOLS='Shell(git:commit*)' AGY_TURN_WS="$IWS" bash "$HERE/scripts/agy-ws-exec.sh" --test-root /x --ws /tmp 'sudo id; echo ran-bad' \
  && ! grep -q 'uid=' "$SB/wx.out" && ok "Sasuke's probe --test-root /x --ws /tmp 'sudo id' fails without running" || ko "probe: $(cat "$SB/wx.out")"
wxr env -u TEST_ROOT AGY_ALLOW_TOOLS='Shell(git:commit*)' AGY_TURN_WS="$IWS" bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" --ws /tmp 'echo ran-bad' \
  && grep -q 'is not under' "$SB/wx.out" && ok "the wrapper refuses --ws outside \$TEST_ROOT/work" || ko "ws outside: $(cat "$SB/wx.out")"
mkdir -p "$IR/work/nohook"; wxr wx bash "$HERE/scripts/agy-ws-exec.sh" --ws "$IR/work/nohook" 'echo ran-bad' && grep -q 'no .agents/hooks/pre-shell.sh' "$SB/wx.out" \
  && ok "the wrapper refuses a workspace without pre-shell.sh" || ko "no hook: $(cat "$SB/wx.out")"
wxr env TEST_ROOT="$IR" AGY_TURN_WS="$IWS" bash "$HERE/scripts/agy-ws-exec.sh" 'echo ran-bad' && grep -q 'AGY_ALLOW_TOOLS is not set' "$SB/wx.out" \
  && ok "the wrapper refuses when AGY_ALLOW_TOOLS is unset" || ko "allow unset: $(cat "$SB/wx.out")"
wxr env TEST_ROOT="$IR" AGY_ALLOW_TOOLS='Shell(git:commit*)' AGY_TURN_WS="$IR/work/other" bash "$HERE/scripts/agy-ws-exec.sh" 'echo ran-bad' && grep -q 'workspace mismatch' "$SB/wx.out" \
  && ok "the wrapper refuses a pending-turn.json whose workspace differs from the turn's" || ko "ws mismatch: $(cat "$SB/wx.out")"
wxr wx bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$SB/root" 'echo ran-bad' && grep -q 'differs from this turn' "$SB/wx.out" \
  && ok "the wrapper refuses a --test-root that differs from TEST_ROOT" || ko "test-root differs: $(cat "$SB/wx.out")"
python3 - "$IR/status/pending-turn.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["allow"]="Shell(*)"; open(p,"w").write(json.dumps(d))
PY
wx bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo ran-bad' > "$SB/wx.out" 2>&1; wrc=$?
[ "$wrc" = 2 ] && ! grep -q ran-bad "$SB/wx.out" && grep -q 'allowlist mismatch' "$IR/agy-driver/ws-exec-denied.log" && ok "the wrapper refuses a pending-turn.json whose allowlist was widened" || ko "wrapper mismatch rc=$wrc: $(cat "$SB/wx.out")"
echo 0 > "$IRUN/turn-1.done"; wait "$ipid"
grep -q 'pending-turn.json changed during turn 1' "$IRUN/pending-tamper-1.txt" 2>/dev/null && [ -s "$IRUN/pending-turn-1.changed.json" ] && ok "agy-ipc-turn.sh records the changed allowlist file and keeps a copy" || ko "ipc tamper not recorded"
( TEST_ROOT="$IR" bash "$HERE/scripts/agy-ipc-turn.sh" chat "$IR/ws" m "hello" - "$IRUN" 2 > /dev/null ) & ipid=$!
for _ in $(seq 1 50); do [ -s "$IR/status/pending-turn.json" ] && break; sleep 0.1; done; echo 0 > "$IRUN/turn-2.done"; wait "$ipid"
[ ! -e "$IRUN/pending-tamper-2.txt" ] && ok "an untouched allowlist file is not recorded" || ko "ipc false positive"

echo "-- a refused launch counts no resume (kitfix-20261031-preflight-first)"
PR="$SB/pf-run"; mkdir -p "$PR/results" "$PR/status"; : > "$PR/results/run.meta"; : > "$PR/results/results.tsv"; : > "$PR/results/checks.tsv"
printf '2026-10-30 10:00:00\t1\t4\tharness-fix\tk1\tFAIL\tH1\n' > "$PR/results/fix-attempts.tsv"
launch(){ env -i HOME="$SB/pf-home" PATH=/usr/bin:/bin LANG=C.UTF-8 KIT_URL="$SB/no-such-kit" KIT_REF=test MAX_RESUMES_TOTAL=2 \
    HARNESS_LOCK_PATHS=/usr/bin KIT_SCAN_ROOTS="$SB/pf-home" REQUIRE_FAIL_MODES=1 "$@" \
    bash "$HERE/scripts/run-plan.sh" --resume-from 2 --test-root "$PR" --reason harness-fix > "$SB/pf.out" 2>&1; }
mkdir -p "$SB/pf-home"
launch KIT_TRACE_MODE=fail; r1=$?                          # refused: H6_MODE not fail
echo bundle > "$SB/pf-home/kit.bundle"; launch H6_MODE=fail KIT_TRACE_MODE=fail; r2=$?   # refused: a readable bundle
mv "$SB/pf-home/kit.bundle" "$SB/kit.bundle.moved"
[ "$r1" = 3 ] && [ "$r2" = 3 ] && [ "$(grep -c . "$PR/results/fix-attempts.tsv")" = 1 ] && [ ! -e "$PR/results/attempt-2" ] \
  && ok "two refused launches write no fix-attempts row and no attempt archive" || ko "refused launches counted (rc $r1/$r2): $(cat "$PR/results/fix-attempts.tsv")"
printf 'N2=x;touch %s/pwned-state\nREQUIRE_FAIL_MODES=0\nN3=$(touch %s/pwned-state2)\nN1=P1-X\n' "$SB" "$SB" > "$PR/status/runner-state.env"
launch H6_MODE=fail KIT_TRACE_MODE=fail; r3=$?
[ ! -e "$SB/pwned-state" ] && [ ! -e "$SB/pwned-state2" ] && grep -q 'STATE-SKIP runner-state.env:1 not NAME=plain-value' "$PR/status/progress.log" \
  && grep -q 'STATE-SKIP runner-state.env:2 REQUIRE_FAIL_MODES is not a state variable' "$PR/status/progress.log" \
  && ok "a relaunch does not run or apply forged state-file lines (STATE-SKIP)" || ko "state file at relaunch: $(grep STATE "$PR/status/progress.log")"
! grep -q FIX-LIMIT "$PR/results/stop.txt" "$SB/pf.out" 2>/dev/null && [ "$(grep -c . "$PR/results/fix-attempts.tsv")" = 2 ] && grep -q 'RUN-START' "$PR/status/progress.log" \
  && ok "the next good launch starts (no FIX-LIMIT with MAX_RESUMES_TOTAL = counted rows + 1)" || ko "good launch rc=$r3: $(tail -3 "$PR/results/stop.txt" 2>/dev/null) $(tail -2 "$SB/pf.out")"
# a launch the full preflight refuses after the resume preparation: its row is marked REFUSED and counts nowhere
FA="$SB/fa.tsv"; printf 'a\t1\t4\tharness-fix\tk\tFAIL\tH1\na\t2\t4\tharness-fix\tk\t\t\n' > "$FA"
( RES="$SB/fa"; mkdir -p "$RES"; cp "$FA" "$RES/fix-attempts.tsv"; eval "$(sed -n '/^attempt_refused(){/,/; }$/p' "$HERE/scripts/run-plan.sh")"; attempt_refused
  RESUME_STEP=4 RESUME_REASON=harness-fix; eval "$(grep -m1 '^  nfail=' "$HERE/scripts/run-plan.sh")"; eval "$(grep -m1 '^  nstep=' "$HERE/scripts/run-plan.sh")"
  [ "$(awk -F'\t' 'NR==2{print $6}' "$RES/fix-attempts.tsv")" = REFUSED ] && [ "$nfail" = 1 ] && [ "$nstep" = 1 ] ) \
  && ok "a row the full preflight refused is marked REFUSED and not counted" || ko "REFUSED row counted"

echo "-- V3 launch env and escalation records (kitfix-20261031-launch-env, kitfix-20261031-escalation-none)"
# a V3 harness copy in the sandbox: the marker V3-REQUIRED and a HARNESS-FROM older than the records
HV3="$SB/hv3"; mkdir -p "$HV3"; cp -r "$HERE/scripts" "$HERE/fixtures" "$HV3/"; echo v3 > "$HV3/V3-REQUIRED"
echo test > "$HV3/HARNESS-FROM"; touch -d '1 hour ago' "$HV3/HARNESS-FROM"
VH="$SB/v3home"; mkdir -p "$VH/.config" "$SB/v3rec" "$SB/escroot"; echo 'export PATH=$PATH' > "$VH/.profile"; echo k=v > "$VH/.config/e2e-secrets.env"
bash "$HV3/scripts/home-hash.sh" --record "$SB/v3rec/home.sha256" "$VH" > /dev/null
printf 'ESC groups ok\nESCALATION-NONE user=%s uid=%s mode=full at=2026-10-31 13:30:00 Asia/Manila host=t\n' "$(id -un)" "$(id -u)" > "$SB/v3rec/esc.txt"
# v3 [VAR=value ...]: v3_launch_ok from the V3 copy's lib.sh. Records are sandbox files (_root_owned is tested on its
#   own below), the live escalation check reads an empty ESC_ROOT tree, and the home is the sandbox home.
v3(){ ( . "$HV3/scripts/lib.sh"; PLAN_DIR="$HV3" HOME="$VH" REQUIRE_FAIL_MODES=1 HOME_HASH_RECORD="$SB/v3rec/home.sha256" ESCALATION_RECORD="$SB/v3rec/esc.txt"
        TOOLS_DIR=/usr/share/misc AGY_BIN=/usr/bin/true LAUNCH_ENV_FILE=/etc/hostname PATH=/usr/local/bin:/usr/bin:/bin; unset TOOLS_ENV_REFUSED
        unset KIT_SCAN_ROOTS KIT_SOURCE_PATHS HARNESS_LOCK_PATHS AGENT_USER
        _root_owned(){ [ -f "$1" ]; }; _home_of(){ echo "$VH"; }; _esc_live(){ ESC_ROOT="$SB/escroot" bash "$HV3/scripts/escalation-check.sh" --live "$1"; }
        for a in "$@"; do export "${a?}"; done; v3_launch_ok ) > "$SB/v3.log" 2>&1; }
v3 && grep -q '^V3 launch ok' "$SB/v3.log" && grep -q '^ESCALATION ok' "$SB/v3.log" && grep -q '^V3 HOME-HASH-OK' "$SB/v3.log" && ok "a clean V3 launch passes" || ko "clean V3: $(cat "$SB/v3.log")"
v3 REQUIRE_FAIL_MODES=0; [ $? != 0 ] && grep -q 'V3 REFUSED REQUIRE_FAIL_MODES=0' "$SB/v3.log" && ok "V3 refuses REQUIRE_FAIL_MODES=0" || ko "V3 rfm: $(cat "$SB/v3.log")"
v3 PLAN_DIR="$HERE"; [ $? != 0 ] && grep -q 'V3 REFUSED PLAN_DIR=' "$SB/v3.log" && ok "V3 refuses a PLAN_DIR that is not the harness it runs from" || ko "V3 plan_dir: $(cat "$SB/v3.log")"
v3 HOME="$SB"; [ $? != 0 ] && grep -q 'V3 REFUSED HOME=' "$SB/v3.log" && ok "V3 refuses a HOME that is not the agent user's" || ko "V3 home: $(cat "$SB/v3.log")"
v3 KIT_SCAN_ROOTS="$SB/scan"; [ $? != 0 ] && grep -q 'V3 REFUSED KIT_SCAN_ROOTS drops default' "$SB/v3.log" && ok "V3 refuses KIT_SCAN_ROOTS without its defaults" || ko "V3 scan roots: $(cat "$SB/v3.log")"
v3 KIT_SCAN_ROOTS="$VH $TEST_ROOT /tmp $SB/scan" && ok "V3 accepts KIT_SCAN_ROOTS that only adds a place" || ko "V3 scan roots add: $(cat "$SB/v3.log")"
v3 KIT_SOURCE_PATHS="$SB/elsewhere"; [ $? != 0 ] && grep -q 'V3 REFUSED KIT_SOURCE_PATHS drops default' "$SB/v3.log" && ok "V3 refuses KIT_SOURCE_PATHS without its defaults" || ko "V3 source paths: $(cat "$SB/v3.log")"
v3 HARNESS_LOCK_PATHS=/usr/bin; [ $? != 0 ] && grep -q 'V3 REFUSED HARNESS_LOCK_PATHS drops the harness' "$SB/v3.log" && ok "V3 refuses HARNESS_LOCK_PATHS without the harness" || ko "V3 lock paths: $(cat "$SB/v3.log")"
mkdir -p "$SB/fakebin"; printf '#!/bin/sh\nexec /usr/bin/git "$@"\n' > "$SB/fakebin/git"; chmod +x "$SB/fakebin/git"
v3 PATH="$SB/fakebin:$PATH"; [ $? != 0 ] && grep -q 'V3 REFUSED tool git .* writable by' "$SB/v3.log" && ok "V3 refuses a PATH that puts an agent-writable git first" || ko "V3 path: $(cat "$SB/v3.log")"
# kitfix-20261031-n1: the hook interpreter main's installed hooks pin (hook-python) must be out of the agent user's reach,
#   with every folder on its -I -S sys.path; a user-site usercustomize.py is a startup-file change (home-hash .local/lib).
printf '#!/bin/sh\nexec /usr/bin/python3 "$@"\n' > "$SB/fakebin/python3"; chmod +x "$SB/fakebin/python3"
mkdir -p "$SB/v3main/.agents/hooks" "$SB/v3main/.cursor/hooks"
echo /usr/bin/python3 > "$SB/v3main/.agents/hooks/hook-python"; echo /usr/bin/python3 > "$SB/v3main/.cursor/hooks/hook-python"
v3 MAIN="$SB/v3main" && grep -q '^V3 launch ok' "$SB/v3.log" && ok "V3 accepts hooks pinned to the root-owned /usr/bin/python3" || ko "V3 hook python ok: $(cat "$SB/v3.log")"
echo "$SB/fakebin/python3" > "$SB/v3main/.agents/hooks/hook-python"
v3 MAIN="$SB/v3main"; [ $? != 0 ] && grep -q "V3 REFUSED hook interpreter $SB/fakebin/python3: .* not owned by root" "$SB/v3.log" && ok "V3 refuses hooks pinned to an interpreter the agent user owns (N-1)" || ko "V3 hook python user-owned: $(cat "$SB/v3.log")"
echo python3 > "$SB/v3main/.agents/hooks/hook-python"
v3 MAIN="$SB/v3main"; [ $? != 0 ] && grep -q "V3 REFUSED hook interpreter 'python3' is not an absolute path" "$SB/v3.log" && ok "V3 refuses a relative hook interpreter (N-1)" || ko "V3 hook python relative: $(cat "$SB/v3.log")"
echo /usr/bin/python3 > "$SB/v3main/.agents/hooks/hook-python"
( . "$HV3/scripts/lib.sh"; AGENT_USER="$(id -un)"; [ -z "$(hook_python_locked /usr/bin/python3)" ] && hook_python_locked "$SB/fakebin/python3" | grep -q 'not owned by root' ) \
  && ok "hook_python_locked accepts /usr/bin/python3 and refuses a user-owned one" || ko "hook_python_locked"
mkdir -p "$VH/.local/lib/python3.13/site-packages"; echo 'import os' > "$VH/.local/lib/python3.13/site-packages/usercustomize.py"
v3; [ $? != 0 ] && grep -q '^V3 HOME-.*\.local/lib' "$SB/v3.log" && ok "V3 refuses a usercustomize.py added to the user site (home-hash .local/lib, N-1)" || ko "V3 user site: $(cat "$SB/v3.log")"
rm -rf "$VH/.local/lib"
# Sakura B-1: a sourceless usercustomize.pyc in the user site runs in every bare python3 of that user, so home-hash
#   must hash it; only __pycache__/ (a cache Python never imports sourceless) is left out.
HH="$SB/hh"; HHS="$(HOME="$HH" /usr/bin/python3 -c 'import site; print(site.getusersitepackages())')"
mkdir -p "$HHS"; echo 'not python' > "$HHS/README.txt"; echo 'X = 1' > "$SB/plain.py"
bash "$HV3/scripts/home-hash.sh" --record "$SB/hh.sha256" "$HH" > /dev/null || ko "home-hash --record refused a user site without Python source"
mkdir -p "$HHS/__pycache__"; HOME="$HH" /usr/bin/python3 -c 'import sys, py_compile; py_compile.compile(sys.argv[1], cfile=sys.argv[2])' "$SB/plain.py" "$HHS/__pycache__/plain.cpython-0.pyc"
bash "$HV3/scripts/home-hash.sh" --check "$SB/hh.sha256" "$HH" > "$SB/hh.log" 2>&1 && grep -q '^HOME-HASH-OK' "$SB/hh.log" \
  && ok "home-hash ignores a __pycache__/ refresh under .local/lib" || ko "home-hash __pycache__: $(cat "$SB/hh.log")"
printf 'open(%s, "w").write("ran")\n' "'$SB/hh.mark'" > "$SB/hh-uc.py"
/usr/bin/python3 -c 'import sys, py_compile; py_compile.compile(sys.argv[1], cfile=sys.argv[2])' "$SB/hh-uc.py" "$HHS/usercustomize.pyc"
rm -f "$SB/hh.mark"; HOME="$HH" /usr/bin/python3 -c 'pass'
[ "$(cat "$SB/hh.mark" 2>/dev/null)" = ran ] && ok "control: a sourceless usercustomize.pyc in the user site runs in a bare python3" \
  || ko "control: the sourceless usercustomize.pyc did not run (user site disabled here?)"
bash "$HV3/scripts/home-hash.sh" --check "$SB/hh.sha256" "$HH" > "$SB/hh.log" 2>&1; [ $? != 0 ] && grep -q '^HOME-CHANGED .local/lib' "$SB/hh.log" \
  && ok "home-hash sees a sourceless usercustomize.pyc added to the user site (Sakura B-1)" || ko "home-hash .pyc: $(cat "$SB/hh.log")"
rm -rf "$HH" "$SB/hh.mark"
# Sakura R-1 (N-1 follow-up): with a real module in the user site, a swapped __pycache__ .pyc runs and is not hashed.
#   --record therefore refuses while .local/lib holds any .py or .pth outside __pycache__/ (942f076 recorded it).
R1="$SB/r1"; R1S="$(HOME="$R1" /usr/bin/python3 -c 'import site; print(site.getusersitepackages())')"
mkdir -p "$R1S/legit/__pycache__"; echo 'OK = 1' > "$R1S/legit/__init__.py"
printf 'open(%s, "w").write("ran")\nOK = 1\n' "'$SB/r1.mark'" > "$SB/r1-evil.py"
/usr/bin/python3 -c 'import sys, py_compile; py_compile.compile(sys.argv[1], cfile=sys.argv[2], invalidation_mode=py_compile.PycInvalidationMode.UNCHECKED_HASH)' \
  "$SB/r1-evil.py" "$R1S/legit/__pycache__/__init__.$(/usr/bin/python3 -c 'import sys; print(sys.implementation.cache_tag)').pyc"
rm -f "$SB/r1.mark"; ( cd "$SB" && HOME="$R1" /usr/bin/python3 -c 'import legit' ) 2>/dev/null
[ "$(cat "$SB/r1.mark" 2>/dev/null)" = ran ] && ok "control: a swapped __pycache__ .pyc of a user-site module runs in a bare python3 (R-1)" \
  || ko "control: the swapped __pycache__ .pyc did not run"
bash "$HV3/scripts/home-hash.sh" --record "$SB/r1.sha256" "$R1" > "$SB/r1.log" 2>&1; r=$?
[ "$r" = 2 ] && grep -q '^HOME-HASH REFUSED: .*\.local/lib/python\* holds 1 Python source' "$SB/r1.log" && [ ! -e "$SB/r1.sha256" ] \
  && ok "home-hash --record refuses a user site that holds a .py, and writes no record (Sakura R-1)" || ko "home-hash R-1 .py: rc=$r $(cat "$SB/r1.log")"
rm -rf "$R1S/legit"; echo 'import os' > "$R1S/x.pth"
bash "$HV3/scripts/home-hash.sh" --record "$SB/r1.sha256" "$R1" > "$SB/r1.log" 2>&1; r=$?
[ "$r" = 2 ] && grep -q '^HOME-HASH REFUSED' "$SB/r1.log" && ok "home-hash --record refuses a user site that holds a .pth (Sakura R-1)" || ko "home-hash R-1 .pth: rc=$r $(cat "$SB/r1.log")"
rm -f "$R1S/x.pth"; mkdir -p "$R1S/__pycache__"; : > "$R1S/__pycache__/stale.cpython-313.pyc"; : > "$R1S/data.txt"
bash "$HV3/scripts/home-hash.sh" --record "$SB/r1.sha256" "$R1" > "$SB/r1.log" 2>&1 && grep -q '^HOME-HASH recorded' "$SB/r1.log" \
  && ok "home-hash --record accepts a user site with only __pycache__ and data files" || ko "home-hash R-1 allow: $(cat "$SB/r1.log")"
# N-1 final round: a .py outside .local/lib/python*/ (npm prefix ~/.local: node-gyp's gyp_main.py) is not on
#   sys.path: the record is written, and a later change there is still a HOME change (all of .local/lib is hashed).
rm -rf "$R1S/__pycache__" "$R1S/data.txt" "$SB/r1.sha256"; NG="$R1/.local/lib/node_modules/npm/node_modules/node-gyp/gyp"
mkdir -p "$NG"; echo 'import sys' > "$NG/gyp_main.py"
bash "$HV3/scripts/home-hash.sh" --record "$SB/r1.sha256" "$R1" > "$SB/r1.log" 2>&1 && grep -q '^HOME-HASH recorded' "$SB/r1.log" \
  && ok "home-hash --record accepts a .py outside .local/lib/python*/ (node-gyp gyp_main.py)" || ko "home-hash node-gyp: $(cat "$SB/r1.log")"
echo '# changed' >> "$NG/gyp_main.py"
bash "$HV3/scripts/home-hash.sh" --check "$SB/r1.sha256" "$R1" > "$SB/r1.log" 2>&1; [ $? != 0 ] && grep -q '^HOME-CHANGED .local/lib' "$SB/r1.log" \
  && ok "home-hash still hashes all of .local/lib (a changed node_modules .py is HOME-CHANGED)" || ko "home-hash node_modules change: $(cat "$SB/r1.log")"
rm -rf "$R1" "$SB/r1.mark" "$SB/r1.sha256"
# Sakura B-3: the harness's own Python runs isolated. run-plan.sh's next-story.py calls (they pick the next story) ran
#   bare python3 and loaded the e2e user site. Static: no harness script outside the operator/root setup tools
#   (prereqs.sh, setup-vm.sh, kit-fix.sh) starts python3 without -I -S. Functional: run-plan.sh's own map line,
#   with a user site that plants a marker, gives the story map and no marker (the bare control does plant it).
# N-1 follow-up (Sakura re-review): tests/py-call-guard.py checks each call, not each line, and also catches
#   /usr/bin/python3, python3.13, "$PY"/${PYTHON} and a *.py run through its shebang.
bare="$(/usr/bin/python3 -I -S "$HERE/tests/py-call-guard.py" $(ls "$HERE"/scripts/*.sh | grep -vE '/(prereqs|setup-vm|kit-fix)\.sh$'))"
[ -z "$bare" ] && ok "no harness script runs a bare python3 (only prereqs.sh, setup-vm.sh, kit-fix.sh: operator/root setup)" \
  || ko "harness scripts with a bare python3: $bare"
PG="$SB/pg"; mkdir -p "$PG"
cat > "$PG/bad.sh" <<'EOF'
/usr/bin/python3 -c 'print(1)'
python3.13 -c 'print(1)'
"$PY" -c 'print(1)'
"$HERE/next-story.py" map "$MAIN"
row="$("$HERE/next-story.py" next "$MAIN")"
python3 -I -S -c 'x'; python3 -c 'y'
python3 next-story.py map x
exec python3 -I -c 'x'
${PYTHON} - <<'PY'
env python3 -c x
chk 3 plan L2 "x" -- "$HERE/next-story.py" map "$MAIN"
mapfile -t rows < <("$HERE"/next-story.py chain "$MAIN")
if ./tool.py; then :; fi
python - <<'PY'
EOF
cat > "$PG/good.sh" <<'EOF'
python3 -I -S -c 'x'
/usr/bin/python3 -I -S -c x
"$py" -I -S -c x
python3.13 -I -S "$HERE/next-story.py" map x
row="$(python3 -I -S "$HERE/next-story.py" next "$MAIN")"
V3_TOOLS="bash sh python3 jq"
cat "$HERE"/*.sh "$HERE"/*.py | sha256sum
out="/usr/bin/python3
# python3 -c 'commented'
grep -qE '\.agents-v0/scripts/[a-z-]+\.(sh|py)' f
post FAIL "no story in the plan (next-story.py chain)"
say pyyaml MISSING "use python3 for x"
for f in a.py b.py; do :; done
[ -f "$d/x.py" ] && echo ok
EOF
got="$(/usr/bin/python3 -I -S "$HERE/tests/py-call-guard.py" "$PG/bad.sh" | sed -E 's/^[^:]+:([0-9]+):.*/\1/' | sort -un | tr '\n' ' ')"
[ "$got" = "1 2 3 4 5 6 7 8 9 10 11 12 13 14 " ] && ok "py-call-guard catches /usr/bin/python3, python3.13, \"\$PY\", shebang runs and a bare call beside a good one" \
  || ko "py-call-guard bad lines caught: $got"
gg="$(/usr/bin/python3 -I -S "$HERE/tests/py-call-guard.py" "$PG/good.sh")"; [ -z "$gg" ] && ok "py-call-guard allows -I -S calls, strings, comments and .py arguments" || ko "py-call-guard false positives: $gg"
old="$(grep -nE '(^|[^[:alnum:]_./-])python3? +(-|"|'\''|\$)' "$PG/bad.sh" | grep -v 'python3 -I -S' | cut -d: -f1 | tr '\n' ' ')"
case " $old " in *" 1 "*|*" 2 "*|*" 3 "*|*" 4 "*) ko "control: the 942f076 regex unexpectedly caught one of lines 1-4 ($old)" ;;
  *) ok "control: the 942f076 regex missed /usr/bin/python3, python3.13, \"\$PY\" and the shebang run (caught only: $old)" ;; esac
NS="$SB/ns"; mkdir -p "$NS/ws/docs/agents-v0/milestones"
printf '| Story ID | Title | Dependency |\n|---|---|---|\n| P0-A | Skeleton | - |\n| P1-A | Login | P0-A |\n' > "$NS/ws/docs/agents-v0/milestones/p0-plan.md"
NSS="$(HOME="$NS/home" /usr/bin/python3 -c 'import site; print(site.getusersitepackages())')"; mkdir -p "$NSS"
printf 'open(%s, "w").write("ran")\n' "'$NS/mark'" > "$NSS/usercustomize.py"
mapline="$(grep -m1 -E 'next-story\.py" map "\$MAIN" > "\$RES/stories\.tsv"' "$HERE/scripts/run-plan.sh" | sed 's/^[[:space:]]*//')"
case "$mapline" in *'python3 -I -S "$HERE/next-story.py"'*) ok "run-plan.sh runs next-story.py with python3 -I -S" ;; *) ko "run-plan.sh map line: $mapline" ;; esac
( HERE="$HERE/scripts"; MAIN="$NS/ws"; RES="$NS"; HOME="$NS/home"; export HOME; eval "$mapline" )
[ ! -e "$NS/mark" ] && grep -q 'P1-A' "$NS/stories.tsv" && ok "run-plan.sh's next-story.py map ignores the e2e user site and still maps the plan (Sakura B-3)" \
  || ko "next-story.py under run-plan.sh: mark=$(cat "$NS/mark" 2>/dev/null) map=$(cat "$NS/stories.tsv" 2>/dev/null)"
rm -f "$NS/mark"; ( HOME="$NS/home"; export HOME; python3 "$HERE/scripts/next-story.py" map "$NS/ws" > /dev/null 2>&1 )
[ "$(cat "$NS/mark" 2>/dev/null)" = ran ] && ok "control: a bare python3 next-story.py loads the user site" || ko "control: bare next-story.py did not load the user site"
rm -rf "$NS"
echo 'export REQUIRE_FAIL_MODES=0' >> "$VH/.profile"; v3; [ $? != 0 ] && grep -q '^V3 HOME-CHANGED .profile' "$SB/v3.log" && ok "V3 refuses a changed startup file (.profile)" || ko "V3 dotfile: $(cat "$SB/v3.log")"
sed -i '$d' "$VH/.profile"; mkdir -p "$VH/.local/agents-v0-tools"; echo 'TOOLS_PATH=/x' > "$VH/.local/agents-v0-tools/tools.env"
v3; [ $? != 0 ] && grep -q '^V3 HOME-ADDED .local/agents-v0-tools/tools.env' "$SB/v3.log" && ok "V3 refuses a new tools.env the record did not have" || ko "V3 tools.env: $(cat "$SB/v3.log")"
mv "$VH/.local/agents-v0-tools/tools.env" "$SB/tools.env.moved"
touch -d '2 hours ago' "$SB/v3rec/home.sha256"; v3; [ $? != 0 ] && grep -q 'home-hash record is older than this harness copy' "$SB/v3.log" && ok "V3 refuses a home-hash record older than the harness copy" || ko "V3 old record: $(cat "$SB/v3.log")"
touch "$SB/v3rec/home.sha256"
cp "$SB/v3rec/esc.txt" "$SB/esc.good"; sed -i 's/^ESCALATION-NONE/ESCALATION-FOUND/' "$SB/v3rec/esc.txt"
v3; [ $? != 0 ] && grep -q 'ESCALATION record has no ESCALATION-NONE' "$SB/v3.log" && ok "V3 refuses an escalation record without ESCALATION-NONE" || ko "V3 esc record: $(cat "$SB/v3.log")"
cp "$SB/esc.good" "$SB/v3rec/esc.txt"; mkdir -p "$SB/escroot/run"; : > "$SB/escroot/run/docker.sock"
v3; [ $? != 0 ] && grep -q 'ESCALATION live: ESC sockets HIT' "$SB/v3.log" && ok "V3 refuses when the live check finds a docker socket" || ko "V3 esc live: $(cat "$SB/v3.log")"
mv "$SB/escroot/run/docker.sock" "$SB/docker.sock.moved"
( . "$HV3/scripts/lib.sh"; AGENT_USER="$(id -un)"; _root_owned /etc/passwd && ! _root_owned "$SB/v3rec/esc.txt" ) && ok "_root_owned accepts a root-owned file and refuses one the agent user owns" || ko "_root_owned"
( . "$HV3/scripts/lib.sh"; PLAN_DIR="$HV3" HOME="$VH" HOME_HASH_RECORD="$SB/v3rec/home.sha256"; REQUIRE_FAIL_MODES=0; unset KIT_SCAN_ROOTS KIT_SOURCE_PATHS HARNESS_LOCK_PATHS
  _root_owned(){ [ -f "$1" ]; }; _home_of(){ echo "$VH"; }; _esc_live(){ ESC_ROOT="$SB/escroot" bash "$HV3/scripts/escalation-check.sh" --live "$1"; }
  ESCALATION_RECORD="$SB/v3rec/esc.txt"; modes_preflight early ) >/dev/null 2>&1; r=$?
[ "$r" != 0 ] && grep -q 'V3 REFUSED REQUIRE_FAIL_MODES=0' "$RES/modes-preflight.log" && ok "modes_preflight runs v3_launch_ok on a V3 copy even with REQUIRE_FAIL_MODES=0" || ko "v3 wiring rc=$r: $(cat "$RES/modes-preflight.log")"
( ESCALATION_CHECK=1 ESCALATION_RECORD="$SB/no-such-record"; unset REQUIRE_FAIL_MODES; _esc_live(){ ESC_ROOT="$SB/escroot" bash "$HERE/scripts/escalation-check.sh" --live "$1"; }; modes_preflight early ) >/dev/null 2>&1 \
  && ko "ESCALATION_CHECK=1 passed without a record" || { grep -q 'ESCALATION record missing' "$RES/modes-preflight.log" && ok "ESCALATION_CHECK=1 checks the record without a V3 copy" || ko "esc check alone: $(cat "$RES/modes-preflight.log")"; }
( . "$HV3/scripts/lib.sh"; PLAN_DIR="$HV3" HOME="$VH"; RUN="$SB/v3run"; mkdir -p "$RUN"; : > "$RUN/kit-tamper.txt.none"
  harness_integrity > "$RUN/harness-integrity-before-1.tsv"; grep -q '^home/.profile' "$RUN/harness-integrity-before-1.tsv" || exit 9
  echo 'alias git=true' >> "$VH/.bashrc"; harness_integrity_check 1; grep -q 'added harness home/.bashrc\|changed harness home/.bashrc' "$RUN/kit-tamper.txt" ); r=$?
[ "$r" = 0 ] && ok "per turn, a V3 copy also hashes the startup files (a .bashrc written in a turn is an H10 finding)" || ko "v3 home per turn rc=$r"
mv "$VH/.bashrc" "$SB/bashrc.moved"
grep -q 'TMX=(tmux -L e2e-harness -f /dev/null)' "$HERE/scripts/start-tmux.sh" && grep -q '"${TMX\[@\]}" new-session' "$HERE/scripts/start-tmux.sh" \
  && ok "start-tmux.sh uses its own tmux server without ~/.tmux.conf on a V3 copy" || ko "start-tmux isolation"

echo "-- V3 toolchain, agy and env file out of the agent user's reach (kitfix-20261031-tools-root)"
mkdir -p "$SB/tw"; echo 'export TOOLS_PATH=/x' > "$SB/tw/tools.env"; printf '#!/bin/sh\n' > "$SB/fakebin/agy"; chmod +x "$SB/fakebin/agy"
v3 TOOLS_DIR="$SB/tw"; [ $? != 0 ] && grep -q 'V3 REFUSED TOOLS_DIR: writable by' "$SB/v3.log" && ok "V3 refuses a TOOLS_DIR the agent user can write" || ko "V3 tools dir: $(cat "$SB/v3.log")"
v3 AGY_BIN="$VH/agy"; [ $? != 0 ] && grep -q 'V3 REFUSED AGY_BIN .* is under HOME' "$SB/v3.log" && ok "V3 refuses an AGY_BIN under HOME" || ko "V3 agy home: $(cat "$SB/v3.log")"
v3 AGY_BIN="$SB/fakebin/agy"; [ $? != 0 ] && grep -q 'V3 REFUSED AGY_BIN: writable by' "$SB/v3.log" && ok "V3 refuses an AGY_BIN the agent user can write" || ko "V3 agy writable: $(cat "$SB/v3.log")"
v3 AGY_BIN=; [ $? != 0 ] && grep -q 'V3 REFUSED AGY_BIN is not set' "$SB/v3.log" && ok "V3 refuses an unset AGY_BIN (no fallback)" || ko "V3 agy unset"
v3 LAUNCH_ENV_FILE="$SB/tw/tools.env"; [ $? != 0 ] && grep -q 'V3 REFUSED launch env file: writable by' "$SB/v3.log" && ok "V3 refuses a launch env file the agent user can write" || ko "V3 env file: $(cat "$SB/v3.log")"
v3 LAUNCH_ENV_FILE=; [ $? != 0 ] && grep -q 'V3 REFUSED launch env file: not set' "$SB/v3.log" && ok "V3 refuses a launch without a recorded env file" || ko "V3 env file unset"
v3 PATH="/usr/share/misc:$SB/tw:/usr/bin:/bin"; [ $? != 0 ] && grep -q "V3 REFUSED PATH folder ahead of the system folders: writable by .*$SB/tw" "$SB/v3.log" && ok "V3 refuses a writable PATH folder ahead of /usr/bin" || ko "V3 path dir: $(cat "$SB/v3.log")"
v3 PATH="/usr/bin:/bin:$SB/tw" && ok "V3 accepts a writable PATH folder after the system folders" || ko "V3 path after: $(cat "$SB/v3.log")"
v3 TOOLS_ENV_REFUSED="$SB/tw/tools.env"; [ $? != 0 ] && grep -q 'was not sourced' "$SB/v3.log" && ok "V3 refuses when env.sh skipped a writable tools.env" || ko "V3 tools.env refused"
( env -i HOME="$SB" PATH=/usr/bin:/bin REQUIRE_FAIL_MODES=1 TOOLS_DIR="$SB/tw" bash -c '. "$1/scripts/env.sh"; echo "R=${TOOLS_ENV_REFUSED:-} T=${TOOLS_PATH:-}"' _ "$HERE" ) > "$SB/envsh.out" 2>&1
grep -q "R=$SB/tw/tools.env T=\$" "$SB/envsh.out" && ok "env.sh does not source a writable tools.env with REQUIRE_FAIL_MODES=1" || ko "env.sh tools.env: $(cat "$SB/envsh.out")"
( env -i HOME="$SB" PATH=/usr/bin:/bin TOOLS_DIR="$SB/tw" bash -c '. "$1/scripts/env.sh"; echo "R=${TOOLS_ENV_REFUSED:-} T=${TOOLS_PATH:-}"' _ "$HERE" ) > "$SB/envsh.out" 2>&1
grep -q "R= T=/x" "$SB/envsh.out" && ok "env.sh still sources tools.env outside V3/unattended" || ko "env.sh normal: $(cat "$SB/envsh.out")"
mkdir -p "$SB/tl/status"
( env -i HOME="$SB" PATH=/usr/bin:/bin REQUIRE_FAIL_MODES=1 TOOLS_DIR="$SB/notools" bash "$HERE/scripts/agy-turn-loop.sh" "$SB/tl" "$HERE" 999999 ) > "$SB/tl.out" 2>&1; r1=$?
( env -i HOME="$SB" PATH=/usr/bin:/bin REQUIRE_FAIL_MODES=1 TOOLS_DIR="$SB/notools" AGY_BIN="$SB/fakebin/agy" bash "$HERE/scripts/agy-turn-loop.sh" "$SB/tl" "$HERE" 999999 ) > "$SB/tl2.out" 2>&1; r2=$?
( env -i HOME="$SB" PATH=/usr/bin:/bin REQUIRE_FAIL_MODES=1 TOOLS_DIR="$SB/tw" AGY_BIN=/usr/bin/true bash "$HERE/scripts/agy-turn-loop.sh" "$SB/tl" "$HERE" 999999 ) > "$SB/tl3.out" 2>&1; r3=$?
[ "$r1" = 2 ] && grep -q 'needs AGY_BIN set' "$SB/tl.out" && [ "$r2" = 2 ] && grep -q 'is under \$HOME\|is writable by' "$SB/tl2.out" && [ "$r3" = 2 ] && grep -q 'tools.env is writable' "$SB/tl3.out" \
  && ok "agy-turn-loop.sh refuses the PATH/~/.local/bin fallback, a writable agy and a writable tools.env (V3/unattended)" || ko "turn loop: $r1 $r2 $r3 $(cat "$SB/tl.out" "$SB/tl2.out" "$SB/tl3.out")"

echo "-- state file without eval (kitfix-20261031-state-file)"
SF="$SB/state.env"
( N1=P1-E N1_SLUG=p1-e-x N2=P2-A N3=P2-F P0A_SLUG=p0-a KIT_LABEL="kit (x) a'b" KIT_SHA=abc123 CONFIG_MODE=global ASK_MODE=harness; save_state "$SF" )
printf 'N2=x;touch %s/pwned-sf\nN3=$(touch %s/pwned-sf2)\nN3_SLUG=`touch %s/pwned-sf3`\nREQUIRE_FAIL_MODES=0\nNATIVE_VERIFY=0\nMAX_RESUMES_TOTAL=99\nPATH=/tmp\nKIT_SCAN_ROOTS=/nowhere\nH6_MODE=warn\nN1_SLUG=$'"'"'\\x41'"'"'\n' "$SB" "$SB" "$SB" >> "$SF"
( unset N1 N1_SLUG N2 N3 N3_SLUG P0A_SLUG KIT_LABEL KIT_SHA; REQUIRE_FAIL_MODES=1 NATIVE_VERIFY=1 MAX_RESUMES_TOTAL=3 H6_MODE=fail KIT_SCAN_ROOTS=/keep CONFIG_MODE=perturn ASK_MODE=auto
  _LAUNCH_CONFIG_MODE= _LAUNCH_ASK_MODE=; P0=$PATH
  load_state "$SF" || exit 9
  [ ! -e "$SB/pwned-sf" ] && [ ! -e "$SB/pwned-sf2" ] && [ ! -e "$SB/pwned-sf3" ] || exit 1
  [ "$REQUIRE_FAIL_MODES" = 1 ] && [ "$NATIVE_VERIFY" = 1 ] && [ "$MAX_RESUMES_TOTAL" = 3 ] && [ "$H6_MODE" = fail ] && [ "$KIT_SCAN_ROOTS" = /keep ] && [ "$PATH" = "$P0" ] || exit 2
  [ "$N1" = P1-E ] && [ "$N1_SLUG" = p1-e-x ] && [ "$N2" = P2-A ] && [ "$N3" = P2-F ] && [ "$KIT_LABEL" = "kit (x) a'b" ] && [ "$CONFIG_MODE" = global ] && [ "$ASK_MODE" = harness ] || exit 3 ) > "$SB/sf.out" 2>&1; r=$?
[ "$r" = 0 ] && ok "load_state: injected commands do not run, mode and safety lines are ignored, saved values come back intact" || ko "load_state rc=$r: $(cat "$SB/sf.out")"
grep -c 'STATE-SKIP' "$STATUS_LOG" > "$SB/sf.n"; [ "$(cat "$SB/sf.n")" -ge 10 ] && grep -q "STATE-SKIP state.env:.* REQUIRE_FAIL_MODES is not a state variable" "$STATUS_LOG" \
  && ok "every skipped state line is logged (STATE-SKIP)" || ko "state skips logged: $(cat "$SB/sf.n")"
printf 'CONFIG_MODE=global\nASK_MODE=allowlist\n' > "$SB/sf2.env"
( CONFIG_MODE=perturn ASK_MODE=harness _LAUNCH_CONFIG_MODE=perturn _LAUNCH_ASK_MODE=harness; load_state "$SB/sf2.env"; [ "$CONFIG_MODE" = perturn ] && [ "$ASK_MODE" = harness ] ) \
  && grep -q 'CONFIG_MODE=global ignored, the launch env set perturn (STATE-KEEP)' "$STATUS_LOG" && ok "a mode the launch env set is kept (STATE-KEEP)" || ko "state keep"
printf 'CONFIG_MODE=shared\nASK_MODE=none\n' > "$SB/sf3.env"
( CONFIG_MODE=perturn ASK_MODE=auto _LAUNCH_CONFIG_MODE= _LAUNCH_ASK_MODE=; load_state "$SB/sf3.env"; [ "$CONFIG_MODE" = perturn ] && [ "$ASK_MODE" = auto ] ) \
  && ok "unknown CONFIG_MODE / ASK_MODE values are skipped" || ko "state enum"
! sed -n '/^load_state(){/,/^  done < "\$1"; return 0; }/p' "$HERE/scripts/lib.sh" | grep -Eq '(^|[^_])eval |(^|[[:space:]])(\.|source) ' && sed -n '/^load_state(){/p' "$HERE/scripts/lib.sh" | grep -q . && ok "lib.sh has no eval of state-file lines" || ko "eval still in lib.sh"

T_HLB="$(sed -n 's/^ *\(local hlb=.*\)$/\1/p' "$HERE/scripts/lib.sh")"; [ -n "$T_HLB" ] || T_HLB=missing
eval "hlbt(){ $T_HLB; echo \"[\$hlb]\"; }"
[ "$(HOME=/h REQUIRE_FAIL_MODES=1 hlbt 2>&1)" = "[]" ] && [ "$(HOME=/h REQUIRE_FAIL_MODES=0 hlbt 2>&1)" = "[/h/.local/bin:]" ] \
  && grep -q 'PATH="${TOOLS_PATH:+$TOOLS_PATH:}${hlb}/usr/local/bin:/usr/bin:/bin"' "$HERE/scripts/lib.sh" \
  && ok "run_turn puts no ~/.local/bin ahead of the system folders with REQUIRE_FAIL_MODES=1 (kept when attended)" || ko "run_turn PATH: $(HOME=/h REQUIRE_FAIL_MODES=1 hlbt 2>&1)"

echo "-- escalation-check.sh (kitfix-20261031-escalation-none)"
ER="$SB/er"; EB="$SB/erbin"; mkdir -p "$ER/etc" "$ER/proc/net" "$EB"
printf '#!/bin/sh\ncase "$*" in "-u e2e") echo 1001;; "-nG e2e") echo "${STUB_GROUPS:-e2e}";; *) exec /usr/bin/id "$@";; esac\n' > "$EB/id"
printf '#!/bin/sh\necho "${STUB_SUDO:-User e2e is not allowed to run sudo on vm.}"\n' > "$EB/sudo"; chmod +x "$EB/id" "$EB/sudo"
printf '  sl  local_address rem_address   st\n   0: 0100007F:0947 00000000:0000 01 0\n' > "$ER/proc/net/tcp"
esc(){ env "$@" ESC_ROOT="$ER" PATH="$EB:$PATH" bash "$HERE/scripts/escalation-check.sh" --record "$SB/esc-rec.txt" e2e > "$SB/esc.out" 2>&1; }
esc; r=$?; [ "$r" = 0 ] && tail -1 "$SB/esc.out" | grep -q '^ESCALATION-NONE user=e2e uid=1001 mode=full ' && cmp -s "$SB/esc.out" "$SB/esc-rec.txt" \
  && ok "a clean user is ESCALATION-NONE and the record is written (an established :2375 connection is not a listener)" || ko "esc clean rc=$r: $(cat "$SB/esc.out")"
esc STUB_SUDO='User e2e may run the following commands on vm: (ALL) NOPASSWD: ALL'; [ $? = 1 ] && grep -q '^ESC sudo HIT' "$SB/esc.out" && tail -1 "$SB/esc.out" | grep -q '^ESCALATION-FOUND' && ok "sudo rules are a hit" || ko "esc sudo: $(cat "$SB/esc.out")"
esc STUB_SUDO='sudo: something odd'; [ $? = 1 ] && grep -q '^ESC sudo HIT unclear' "$SB/esc.out" && ok "unclear sudo -l output is a hit (fail closed)" || ko "esc sudo unclear"
esc STUB_GROUPS='e2e docker'; [ $? = 1 ] && grep -q '^ESC groups HIT e2e is in: docker' "$SB/esc.out" && ok "the docker group is a hit" || ko "esc docker group: $(cat "$SB/esc.out")"
esc STUB_GROUPS='e2e lxd'; [ $? = 1 ] && grep -q '^ESC groups HIT e2e is in: lxd' "$SB/esc.out" && ok "the lxd group is a hit" || ko "esc lxd"
printf '# permit e2e as root\npermit persist :wheel\n' > "$ER/etc/doas.conf"; esc; [ $? = 0 ] && grep -q '^ESC doas ok' "$SB/esc.out" && ok "doas.conf naming only other groups and comments is ok" || ko "esc doas ok: $(cat "$SB/esc.out")"
printf 'permit nopass e2e as root\n' > "$ER/etc/doas.conf"; esc; [ $? = 1 ] && grep -q '^ESC doas HIT' "$SB/esc.out" && ok "a doas rule for the user is a hit" || ko "esc doas hit"
mv "$ER/etc/doas.conf" "$SB/doas.conf.moved"; mkdir -p "$ER/etc/polkit-1/rules.d"
printf 'polkit.addRule(function(a, s) { if (s.user == "e2e") return polkit.Result.YES; });\n' > "$ER/etc/polkit-1/rules.d/50-e2e.rules"
esc; [ $? = 1 ] && grep -q '^ESC polkit HIT' "$SB/esc.out" && ok "a polkit rule naming the user is a hit" || ko "esc polkit: $(cat "$SB/esc.out")"
mv "$ER/etc/polkit-1/rules.d/50-e2e.rules" "$SB/50-e2e.rules.moved"; mkdir -p "$ER/var/run"; : > "$ER/var/run/docker.sock"
esc; [ $? = 1 ] && grep -q '^ESC sockets HIT docker socket present: /var/run/docker.sock' "$SB/esc.out" && ok "/var/run/docker.sock is a hit" || ko "esc sock"
mv "$ER/var/run/docker.sock" "$SB/docker.sock2.moved"; printf '  sl  local_address rem_address   st\n   0: 00000000:0948 00000000:0000 0A 0\n' > "$ER/proc/net/tcp6"
esc; [ $? = 1 ] && grep -q '^ESC ports HIT listening on: 2376' "$SB/esc.out" && ok "a listener on 2376 is a hit" || ko "esc port: $(cat "$SB/esc.out")"
mv "$ER/proc/net/tcp6" "$SB/tcp6.moved"
( env ESC_ROOT="$ER" PATH="$EB:$PATH" STUB_SUDO='User e2e may run the following commands on vm: ALL' bash "$HERE/scripts/escalation-check.sh" --live e2e ) > "$SB/esc.out" 2>&1; r=$?
[ "$r" = 0 ] && ! grep -q 'ESC sudo' "$SB/esc.out" && tail -1 "$SB/esc.out" | grep -q 'mode=live' && ok "--live skips the root-only checks" || ko "esc live rc=$r: $(cat "$SB/esc.out")"
( env -u ESC_ROOT bash "$HERE/scripts/escalation-check.sh" e2e ) > "$SB/esc.out" 2>&1; [ $? = 2 ] && grep -q 'needs root' "$SB/esc.out" && ok "a full check as non-root refuses (exit 2)" || ko "esc nonroot"

mk='# >>> kit-test'; mk="$mk-override"
grep -q 'kit_installed_ok "$MAIN"' "$HERE/scripts/run-plan.sh" && ! grep -rlF --include='*.sh' -- "$mk" "$HERE/scripts" "$HERE/tests" | grep -q . \
  && ok "story start uses kit_installed_ok; the harness's own *.sh files never match the marker scan" || ko "wiring/marker: $(grep -rlF --include='*.sh' -- "$mk" "$HERE/scripts" "$HERE/tests")"
grep -q 'chk "$st" "$id" H10 ' "$HERE/scripts/run-plan.sh" && grep -q 'kit_integrity_check "$k"' "$HERE/scripts/lib.sh" && grep -q '^modes_preflight early || stop_resume' "$HERE/scripts/run-plan.sh" && grep -q '^modes_preflight || {' "$HERE/scripts/run-plan.sh" \
  && grep -q '"${H10_MODE:-fail}" = warn' "$HERE/scripts/run-plan.sh" && ok "H10 and the preflight are wired (FAIL by default)" || ko "H10 wiring"
echo "== test-guards: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
