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
IR="$SB/ipc"; mkdir -p "$IR/status" "$IR/evidence/S4-x-1" "$IR/ws" "$IR/agy-driver"; IRUN="$IR/evidence/S4-x-1"
( TEST_ROOT="$IR" bash "$HERE/scripts/agy-ipc-turn.sh" chat "$IR/ws" m "hello" 'Shell(git:commit*)' "$IRUN" 1 > /dev/null ) & ipid=$!
for _ in $(seq 1 50); do [ -s "$IR/status/pending-turn.json" ] && break; sleep 0.1; done
AGY_ALLOW_TOOLS='Shell(git:commit*)' bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo ran-ok' > "$SB/wx.out" 2>&1 && grep -q ran-ok "$SB/wx.out" && ok "the wrapper runs a command when the file matches the turn's allowlist" || ko "wrapper match: $(cat "$SB/wx.out")"
python3 - "$IR/status/pending-turn.json" <<'PY'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["allow"]="Shell(*)"; open(p,"w").write(json.dumps(d))
PY
AGY_ALLOW_TOOLS='Shell(git:commit*)' bash "$HERE/scripts/agy-ws-exec.sh" --test-root "$IR" 'echo ran-bad' > "$SB/wx.out" 2>&1; wrc=$?
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
launch H6_MODE=fail KIT_TRACE_MODE=fail; r3=$?
! grep -q FIX-LIMIT "$PR/results/stop.txt" "$SB/pf.out" 2>/dev/null && [ "$(grep -c . "$PR/results/fix-attempts.tsv")" = 2 ] && grep -q 'RUN-START' "$PR/status/progress.log" \
  && ok "the next good launch starts (no FIX-LIMIT with MAX_RESUMES_TOTAL = counted rows + 1)" || ko "good launch rc=$r3: $(tail -3 "$PR/results/stop.txt" 2>/dev/null) $(tail -2 "$SB/pf.out")"
# a launch the full preflight refuses after the resume preparation: its row is marked REFUSED and counts nowhere
FA="$SB/fa.tsv"; printf 'a\t1\t4\tharness-fix\tk\tFAIL\tH1\na\t2\t4\tharness-fix\tk\t\t\n' > "$FA"
( RES="$SB/fa"; mkdir -p "$RES"; cp "$FA" "$RES/fix-attempts.tsv"; eval "$(sed -n '/^attempt_refused(){/,/; }$/p' "$HERE/scripts/run-plan.sh")"; attempt_refused
  RESUME_STEP=4 RESUME_REASON=harness-fix; eval "$(grep -m1 '^  nfail=' "$HERE/scripts/run-plan.sh")"; eval "$(grep -m1 '^  nstep=' "$HERE/scripts/run-plan.sh")"
  [ "$(awk -F'\t' 'NR==2{print $6}' "$RES/fix-attempts.tsv")" = REFUSED ] && [ "$nfail" = 1 ] && [ "$nstep" = 1 ] ) \
  && ok "a row the full preflight refused is marked REFUSED and not counted" || ko "REFUSED row counted"

mk='# >>> kit-test'; mk="$mk-override"
grep -q 'kit_installed_ok "$MAIN"' "$HERE/scripts/run-plan.sh" && ! grep -rlF --include='*.sh' -- "$mk" "$HERE/scripts" "$HERE/tests" | grep -q . \
  && ok "story start uses kit_installed_ok; the harness's own *.sh files never match the marker scan" || ko "wiring/marker: $(grep -rlF --include='*.sh' -- "$mk" "$HERE/scripts" "$HERE/tests")"
grep -q 'chk "$st" "$id" H10 ' "$HERE/scripts/run-plan.sh" && grep -q 'kit_integrity_check "$k"' "$HERE/scripts/lib.sh" && grep -q '^modes_preflight early || stop_resume' "$HERE/scripts/run-plan.sh" && grep -q '^modes_preflight || {' "$HERE/scripts/run-plan.sh" \
  && grep -q '"${H10_MODE:-fail}" = warn' "$HERE/scripts/run-plan.sh" && ok "H10 and the preflight are wired (FAIL by default)" || ko "H10 wiring"
echo "== test-guards: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
