#!/usr/bin/env bash
# test-ledger-turn.sh — offline tests of N84 in the unattended harness (design rev 6, "Ledger integrity (N3A)":
#   the harness records the gate ledger's mark before each unattended turn and compares after it). run_turn takes
#   `gate-checks.sh ledger_mark` before the turn and runs `gate-checks.sh ledger_turn_ok <mark> 0 0` after it; any
#   change stops the run for a person (LEDGER-CHANGED, TURN_CLASS=LEDGER, drive_run HALT, RUN_END=LEDGER).
#   The real run_turn runs with a stub agent (AGENT_TURN_CMD, antigravity driver): no cursor-agent, no agy. The
#   gate-checks.sh used is the installed copy (install.sh into a temp git repo), never the kit's own template copy.
# Cases:
#   LT-1  unchanged ledger (absent, then present) -> the turn is not LEDGER, ledger_turn_ok OK is recorded
#   LT-2  appended REOPEN-REFUSED / FAIL lines -> LEDGER (the harness claims 0 seen: fail closed, see lib.sh N84)
#   LT-3  appended GRANT-USED, an edited line, a cut, a deleted ledger -> LEDGER, with the gate-checks reason
#   LT-4  a worktree turn: the ledger lives in the git common dir, an append from the worktree is caught
#   LT-5  after LEDGER the next run_turn does not start the agent; harness_complete completes nothing
#   LT-6  a mark that cannot be taken (ledger is a folder) -> the turn never starts, LEDGER
#   LT-7  a kit with no N3A ledger (no gate-checks.sh ledger_mark) -> skipped (.na), the turn runs as before
#   LT-8  drive_run: a LEDGER turn -> HALT naming LEDGER-CHANGED, RUN_END=LEDGER, no further turn
#   LT-9  a gate commit step in the turn (staged_secret_scan runs the ledger trailer step first, 2d60290b): creating the empty ledger is OK; a stale
#         REOPEN-REFUSED grant= line for an unnamed grant line -> LEDGER (fail closed: a person looks at the grant)
#   LT-10 the checker itself (Jiraiya must-fix on c0e4492f): GRANT-USED appended AND the workspace gate-checks.sh
#         rewritten so ledger_turn_ok exits 0 -> drive_run stops (RUN_END=LEDGER, one turn); gate-checks.sh edited
#         with no ledger change -> LEDGER via H10; the harness's own snapshot changed -> LEDGER
#   LT-11 the python3 gate-checks.sh runs (lead follow-up on 1b213d17): the agent drops a fake python3 (exit 0) in
#         ~/.local/bin, which the harness PATH holds (as Ubuntu's ~/.profile adds it), and appends GRANT-USED ->
#         RUN_END=LEDGER; a python3 resolving inside the workspace -> refused before the turn; the pinned python3
#         changed during the turn -> LEDGER
# Usage: bash tests/test-ledger-turn.sh   (exit 0 when every case passes). Removes only its own mktemp folder;
#   inside it, files it replaces are moved to $TEST_ROOT/trash.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KIT="${KIT_DIR:-$(cd "$HERE/../.." && pwd)}"
SB="$(mktemp -d)"; trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
PASS=0; FAILN=0
ok(){ echo "  PASS $*"; PASS=$((PASS+1)); }; ko(){ echo "  FAIL $*"; FAILN=$((FAILN+1)); }
TEST_ROOT="$SB/root"; STATUS_LOG="$TEST_ROOT/status/progress.log"; mkdir -p "$TEST_ROOT/status" "$TEST_ROOT/trash"
PLAN_DIR="$HERE"; MAX_TURNS=30 MAX_ANSWERS=0 MAX_RETRY_INFRA=0 INFRA_BACKOFF=0 TURN_PAUSE_SEC=0 HEARTBEAT_SEC=99999
P0A_SLUG=p0-a-platform-skeleton KIT_REF=test KIT_LABEL=test
. "$HERE/scripts/lib.sh"
resolve_driver(){ echo antigravity; }
EVID="$TEST_ROOT/evidence"; RES="$TEST_ROOT/results"; mkdir -p "$EVID" "$RES"
CONFIG_MODE=global JAIL_CMD="" AGENT_MODEL=stub CHAT=stub-chat TURN_CAP=120 POLL_SEC=1 STALL_SEC=600
RUN_DEADLINE=$(( $(now) + 3600 ))
WORK="$TEST_ROOT/work"; MAIN="$WORK/portal"; mkdir -p "$WORK"
g(){ git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
git init -q -b main "$MAIN"; echo base > "$MAIN/README.md"; g add README.md; g commit -qm base
sh "$KIT/scripts/install.sh" "$MAIN" > "$SB/install.log" 2>&1 || { echo "install.sh failed: $(tail -3 "$SB/install.log")"; exit 2; }
grep -q '^  ledger_mark)' "$MAIN/.agents-v0/scripts/gate-checks.sh" || { echo "the installed gate-checks.sh has no ledger_mark"; exit 2; }
LEDGER="$(cd "$MAIN" && sh .agents-v0/scripts/gate-checks.sh paths | sed -n 's/^ledger=//p')"
GRANT="$(cd "$MAIN" && sh .agents-v0/scripts/gate-checks.sh paths | sed -n 's/^grant=//p')"
[ -n "$LEDGER" ] || { echo "no ledger path from gate-checks.sh paths"; exit 2; }
H64="$(printf 'x' | sha256_cmd | cut -c1-64)"
# stub agent: <chat> <ws> <model> <message> <allow> <run> <k>; the message says what it does to the ledger
cat > "$SB/stub.sh" <<'STUB'
#!/bin/sh
ws="$2"; msg="$4"; run="$6"; k="$7"; : > "$run/stub-ran-$k"
L="$(cd "$ws" && sh .agents-v0/scripts/gate-checks.sh paths 2>/dev/null | sed -n 's/^ledger=//p')"
case "$msg" in
  noop) ;;
  append:*) mkdir -p "$(dirname "$L")"; printf '%s\n' "${msg#append:}" >> "$L" ;;
  edit1) sed '1s/.*/FAIL edited/' "$L" > "$L.new" && mv "$L.new" "$L" ;;
  cut) head -n 1 "$L" > "$L.new" && mv "$L.new" "$L" ;;
  delete) mv "$L" "$run/ledger-moved-away" ;;
  fake) mkdir -p "$(dirname "$L")"; printf 'GRANT-USED %064d count=0\n' 0 >> "$L"
        printf '#!/bin/sh\necho "OK ledger_turn_ok: faked"; exit 0\n' > "$ws/.agents-v0/scripts/gate-checks.sh" ;;
  gcedit) printf '# edited\n' >> "$ws/.agents-v0/scripts/gate-checks.sh" ;;
  snapedit) printf '# edited\n' >> "$run/ledger-gc/turn-$k/gate-checks.sh" ;;
  fakepy) mkdir -p "$HOME/.local/bin" "$(dirname "$L")"; printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/python3"
          chmod +x "$HOME/.local/bin/python3"; printf 'GRANT-USED %064d count=0\n' 0 >> "$L" ;;
  pyswap:*) printf '# swapped\n' >> "${msg#pyswap:}" ;;
  scan) (cd "$ws" && mkdir -p docs/agents-v0 && echo "lt $k" > docs/agents-v0/lt-scan.md && git add -- docs/agents-v0/lt-scan.md \
          && sh .agents-v0/scripts/gate-checks.sh staged_secret_scan; git restore --staged -- docs/agents-v0/lt-scan.md) > "$run/scan-$k.txt" 2>&1 ;;
esac
echo '{"type":"result","result":"done"}'
STUB
AGENT_TURN_CMD="sh $SB/stub.sh"
n=0
newrun(){ n=$((n+1)); RUN="$EVID/run-$n"; mkdir -p "$RUN"; WS="${1:-$MAIN}"; }
away(){ [ ! -e "$1" ] || mv "$1" "$TEST_ROOT/trash/$(basename "$1").$n.$RANDOM"; }
setledger(){ mkdir -p "$(dirname "$LEDGER")"; away "$LEDGER"; [ "$#" = 0 ] || printf '%s\n' "$@" > "$LEDGER"; }
turn(){ TURN_CLASS=""; run_turn "$1" "$2" - > /dev/null 2>&1; }
islg(){ [ "$TURN_CLASS" = LEDGER ] && [ -s "$RUN/LEDGER-CHANGED" ]; }

echo "-- LT-1 unchanged ledger"
newrun; setledger; turn 1 noop
[ "$TURN_CLASS" != LEDGER ] && [ ! -e "$RUN/LEDGER-CHANGED" ] && grep -q "^$MAIN	absent	[0-9a-f]\{64\}	/[^	]*	[0-9a-f]\{64\}$" "$RUN/ledger-mark-1" 2>/dev/null && grep -q '^OK ledger_turn_ok' "$RUN/ledger-turn-1.txt" 2>/dev/null \
  && ok "no ledger before or after -> mark absent, ledger_turn_ok OK, class $TURN_CLASS" || ko "absent/noop: class=$TURN_CLASS mark=$(cat "$RUN/ledger-mark-1" 2>&1) turn=$(cat "$RUN/ledger-turn-1.txt" 2>&1)"
newrun; setledger "FAIL docs check 1" "FAIL docs check 2"; turn 1 noop
[ "$TURN_CLASS" != LEDGER ] && [ ! -e "$RUN/LEDGER-CHANGED" ] && grep -q "	lines=2 sha256=" "$RUN/ledger-mark-1" 2>/dev/null && grep -q '^OK ledger_turn_ok' "$RUN/ledger-turn-1.txt" 2>/dev/null \
  && ok "a 2-line ledger left alone -> mark lines=2, OK" || ko "2 lines/noop: class=$TURN_CLASS mark=$(cat "$RUN/ledger-mark-1" 2>&1)"

echo "-- LT-2 appended lines the harness did not see"
newrun; setledger; turn 1 "append:REOPEN-REFUSED grant=$H64 too old"
islg && grep -q 'REFUSED ledger_turn_ok: ledger changed during the unattended turn' "$RUN/LEDGER-CHANGED" && grep -q "FINDING N84 run=run-$n turn=1" "$STATUS_LOG" \
  && ok "a REOPEN-REFUSED line appended to an absent ledger -> LEDGER, FINDING" || ko "append refused: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
newrun; setledger "FAIL docs check 1"; turn 1 "append:FAIL docs check 2"
islg && grep -q 'appended 1 FAIL and 0 REOPEN-REFUSED' "$RUN/LEDGER-CHANGED" && ok "a FAIL line appended -> LEDGER (0 seen: no kit script writes FAIL lines yet)" || ko "append FAIL: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"

echo "-- LT-3 GRANT-USED, edit, cut, delete"
newrun; setledger "FAIL docs check 1"; turn 1 "append:GRANT-USED $H64 count=1"
islg && grep -q 'GRANT-USED line appended during an unattended turn' "$RUN/LEDGER-CHANGED" && ok "GRANT-USED appended -> LEDGER" || ko "grant: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
newrun; setledger "FAIL docs check 1" "FAIL docs check 2"; turn 1 edit1
islg && grep -q 'first 2 lines of the ledger changed' "$RUN/LEDGER-CHANGED" && ok "an earlier line edited -> LEDGER" || ko "edit: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
newrun; setledger "FAIL docs check 1" "FAIL docs check 2"; turn 1 cut
islg && grep -q 'ledger was cut during the turn' "$RUN/LEDGER-CHANGED" && ok "the ledger cut -> LEDGER" || ko "cut: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
newrun; setledger "FAIL docs check 1"; turn 1 delete
islg && grep -q 'ledger was deleted during the turn' "$RUN/LEDGER-CHANGED" && ok "the ledger deleted -> LEDGER" || ko "delete: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
grep -q "class=LEDGER" "$RUN/turns.tsv" 2>/dev/null && ok "turns.tsv records class=LEDGER" || ko "turns.tsv: $(cat "$RUN/turns.tsv" 2>&1)"

echo "-- LT-4 a worktree turn (ledger in the git common dir)"
g add -- .agents-v0 && g commit -qm "installed kit scripts" && g worktree add -q -b feature/lt "$WORK/portal-lt" 2>/dev/null
newrun "$WORK/portal-lt"; setledger "FAIL docs check 1"; turn 1 "append:REOPEN-REFUSED grant=$H64 too old"
islg && grep -q "^$WORK/portal-lt	lines=1 " "$RUN/ledger-mark-1" && ok "an append from a worktree -> LEDGER (mark taken in the worktree)" || ko "worktree: class=$TURN_CLASS mark=$(cat "$RUN/ledger-mark-1" 2>&1)"

echo "-- LT-5 no further turn and no harness completion after LEDGER"
newrun; setledger; turn 1 "append:FAIL x"; turn 2 noop
[ "$TURN_CLASS" = LEDGER ] && [ ! -e "$RUN/stub-ran-2" ] && ok "the next run_turn does not start the agent (class stays LEDGER)" || ko "turn 2 ran: class=$TURN_CLASS"
hc_before="$(git -C "$MAIN" worktree list | wc -l)"; STORY_SLUG=lt2 STORY_KIND=feature harness_complete branch "Shell(git)" ""
[ ! -e "$RUN/harness-complete.log" ] && [ "$(git -C "$MAIN" worktree list | wc -l)" = "$hc_before" ] && ok "harness_complete completes nothing after LEDGER" || ko "harness_complete ran: $(cat "$RUN/harness-complete.log" 2>&1)"

echo "-- LT-6 the mark cannot be taken"
newrun; setledger; mkdir -p "$LEDGER"; turn 1 noop
islg && [ ! -e "$RUN/stub-ran-1" ] && grep -q 'ledger_mark before the turn failed' "$RUN/LEDGER-CHANGED" && ok "ledger_mark fails -> the turn never starts, LEDGER" || ko "mark fail: class=$TURN_CLASS ran=$([ -e "$RUN/stub-ran-1" ] && echo yes) $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
away "$LEDGER"

echo "-- LT-7 a kit without the N3A ledger"
OLD="$WORK/oldkit"; git init -q -b main "$OLD"; mkdir -p "$OLD/.agents-v0/scripts"
printf '#!/bin/sh\necho "usage"; exit 2\n' > "$OLD/.agents-v0/scripts/gate-checks.sh"
SAVE_MAIN="$MAIN"; MAIN="$OLD"; newrun "$OLD"; turn 1 noop
[ "$TURN_CLASS" != LEDGER ] && [ -e "$RUN/stub-ran-1" ] && [ -s "$RUN/ledger-mark-1.na" ] && [ ! -e "$RUN/LEDGER-CHANGED" ] \
  && ok "no gate-checks.sh ledger_mark -> skipped (.na), the turn runs" || ko "old kit: class=$TURN_CLASS na=$(cat "$RUN/ledger-mark-1.na" 2>&1)"
MAIN="$SAVE_MAIN"

echo "-- LT-8 drive_run halts on LEDGER"
away "$TEST_ROOT/HALT"; setledger
create_agent_chat(){ echo stub-chat; }
drive_run lt8 "$MAIN" "append:FAIL from the first turn" onboard "onboard" 600 > /dev/null 2>&1
[ "$RUN_END" = LEDGER ] && [ -s "$TEST_ROOT/HALT" ] && grep -q 'LEDGER-CHANGED in lt8-1' "$TEST_ROOT/HALT" && [ "$(wc -l < "$RUN/turns.tsv")" = 1 ] \
  && ok "drive_run: LEDGER -> HALT naming LEDGER-CHANGED, RUN_END=LEDGER, one turn" || ko "drive_run: RUN_END=${RUN_END:-} halt=$(cat "$TEST_ROOT/HALT" 2>&1)"

echo "-- LT-9 a gate commit step during the turn (staged_secret_scan -> ledger trailer)"
newrun; setledger; away "$GRANT"; turn 1 scan
[ "$TURN_CLASS" != LEDGER ] && [ -f "$LEDGER" ] && [ ! -s "$LEDGER" ] && grep -q '^OK ledger_turn_ok' "$RUN/ledger-turn-1.txt" 2>/dev/null \
  && ok "the gate commit step creates the empty ledger (absent -> lines=0) -> OK" || ko "trailer/empty: class=$TURN_CLASS $(cat "$RUN/scan-1.txt" "$RUN/LEDGER-CHANGED" 2>&1)"
newrun; setledger; printf 'grant 2026-11-01T09:00:00+08:00 phase=p0-a reason="test" by=t\n' > "$GRANT"; turn 1 scan
islg && grep -q 'REOPEN-REFUSED grant=[0-9a-f]* stale' "$LEDGER" && grep -q 'appended 0 FAIL and 1 REOPEN-REFUSED' "$RUN/LEDGER-CHANGED" \
  && ok "the gate commit step names an unnamed grant line stale -> LEDGER" || ko "trailer/stale: class=$TURN_CLASS $(cat "$RUN/scan-1.txt" "$RUN/LEDGER-CHANGED" 2>&1)"
away "$GRANT"

echo "-- LT-10 the checker itself changed during the turn"
GC="$MAIN/.agents-v0/scripts/gate-checks.sh"; cp "$GC" "$SB/gc.orig"
fixgc(){ away "$GC"; cp "$SB/gc.orig" "$GC"; }
away "$TEST_ROOT/HALT"; setledger "FAIL docs check 1"
drive_run lt10 "$MAIN" "fake" onboard "onboard" 600 > /dev/null 2>&1
[ "${RUN_END:-}" = LEDGER ] && [ -s "$RUN/LEDGER-CHANGED" ] && [ "$(wc -l < "$RUN/turns.tsv")" = 1 ] && grep -q 'GRANT-USED line appended' "$RUN/LEDGER-CHANGED" \
  && ok "GRANT-USED + gate-checks.sh faked to exit 0 -> the snapshot catches it, RUN_END=LEDGER, one turn" || ko "fake: RUN_END=${RUN_END:-} $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
fixgc; away "$TEST_ROOT/HALT"
newrun; setledger "FAIL docs check 1"; turn 1 gcedit
islg && grep -q 'H10: the installed gate-checks.sh changed' "$RUN/LEDGER-CHANGED" && ok "gate-checks.sh edited, ledger unchanged -> LEDGER via H10" || ko "gcedit: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
fixgc
newrun; setledger "FAIL docs check 1"; turn 1 snapedit
islg && grep -q 'snapshot .* is missing or changed' "$RUN/LEDGER-CHANGED" && ok "the harness's snapshot changed -> LEDGER" || ko "snapedit: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"

echo "-- LT-11 the python3 the ledger checks run"
REALPY="$(readlink -f "$(command -v python3)")"; SAVE_PATH="$PATH" SAVE_HOME="$HOME"
pywrap(){ mkdir -p "$1"; printf '#!/bin/sh\nexec %s "$@"\n' "$REALPY" > "$1/python3"; chmod +x "$1/python3"; }
HOME="$SB/home"; mkdir -p "$HOME/.local/bin"; PATH="$HOME/.local/bin:$SAVE_PATH"
away "$TEST_ROOT/HALT"; setledger "FAIL docs check 1"
drive_run lt11 "$MAIN" "fakepy" onboard "onboard" 600 > /dev/null 2>&1
[ "${RUN_END:-}" = LEDGER ] && [ "$(wc -l < "$RUN/turns.tsv")" = 1 ] && grep -q 'GRANT-USED line appended' "$RUN/LEDGER-CHANGED" \
  && ok "fake ~/.local/bin/python3 + GRANT-USED -> the pinned python3 catches it, RUN_END=LEDGER, one turn" || ko "fakepy: RUN_END=${RUN_END:-} $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
away "$HOME/.local/bin/python3"; HOME="$SAVE_HOME"; away "$TEST_ROOT/HALT"
_LG_PY=""; pywrap "$MAIN/.lt-bin"; PATH="$MAIN/.lt-bin:$SAVE_PATH"
newrun; setledger; turn 1 noop
islg && [ ! -e "$RUN/stub-ran-1" ] && grep -q "python3 resolves to $MAIN/.lt-bin/python3, inside" "$RUN/LEDGER-CHANGED" \
  && ok "python3 inside the workspace -> refused before the turn" || ko "pyinside: class=$TURN_CLASS ran=$([ -e "$RUN/stub-ran-1" ] && echo yes) $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
_LG_PY=""; pywrap "$SB/pybin"; PATH="$SB/pybin:$SAVE_PATH"
newrun; setledger; turn 1 "pyswap:$SB/pybin/python3"
islg && grep -q "the pinned interpreter $SB/pybin/python3 is missing or changed" "$RUN/LEDGER-CHANGED" && ok "the pinned python3 changed during the turn -> LEDGER" \
  || ko "pyswap: class=$TURN_CLASS $(cat "$RUN/LEDGER-CHANGED" 2>&1)"
PATH="$SAVE_PATH"; _LG_PY=""

echo "== test-ledger-turn: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ]
