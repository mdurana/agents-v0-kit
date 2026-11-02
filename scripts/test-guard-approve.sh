#!/bin/sh
# test-guard-approve.sh: the normal path of the DA approve step (onboard redo, Design: DA).
# Sensei's `guard-common.sh approve onboard` reads his words from the terminal (driven here through a
# pseudo-terminal), writes the approval record outside the repo and marks onboard approved in the state;
# gc_approval_ok (for D4) passes only on a record for this repo and command that matches the state's baseCommit;
# the Cursor hook denies an agent touching the approval folder or running approve.
# Test-only: the kit test copy (install.sh --test-overrides) reads AGENTS_V0_APPROVALS_DIR, so the record goes to a
# temp folder, never to the real ~/.agents-v0-approvals. A normal install strips that override (checked below).
# Run: sh scripts/test-guard-approve.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-approve.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi
export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(json.dumps(v) if isinstance(v,(list,dict)) else v)' "$1" "$2" 2>&1; }
new_repo() { mkdir -p "$1" && git -C "$1" init -q -b main && printf 'x\n' > "$1/README.md" && git -C "$1" add README.md && git -C "$1" commit -q -m init; }

# --- installs: the test copy keeps the folder override, a normal install does not --------------------------------
plain="$tmp/plain"; new_repo "$plain"
out="$(KIT_VALIDATING=1 sh "$ROOT/scripts/install.sh" "$plain" 2>&1)"; check $? "install: normal install" "$(printf '%s' "$out" | tail -20)"
! grep -q 'AGENTS_V0_APPROVALS_DIR:-' "$plain/.agents-v0/scripts/guard-common.sh"
check $? "install: an installed guard-common.sh never reads AGENTS_V0_APPROVALS_DIR (override stripped)"
out="$(sh "$ROOT/scripts/check-installed-kit.sh" "$plain" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s' "$out" | grep -q HASH-OK; check $? "check-installed-kit: HASH-OK with the DA guard-common.sh" "$(printf '%s' "$out" | grep -v '^OK' | tail -20)"

proj="$tmp/proj"; new_repo "$proj"
out="$(KIT_VALIDATING=1 sh "$ROOT/scripts/install.sh" --test-overrides "$proj" 2>&1)"; check $? "install: kit test copy (--test-overrides)" "$(printf '%s' "$out" | tail -20)"
G="$proj/.agents-v0/scripts"
S="$proj/docs/agents-v0/onboarding/state.json"
lib() { (cd "$proj" && GC_HERE="$G" GUARD_COMMON_LIB=1 && . "$G/guard-common.sh" && "$@"); }
approval_ok() { (cd "$proj" && GC_HERE="$G" GUARD_COMMON_LIB=1 && . "$G/guard-common.sh" && gc_approval_ok onboard) 2>&1; }

# onboarding started (D2) and ready for approval (set through the state writer, so this test does not depend on D3 `ready`).
out="$(cd "$proj" && sh "$G/guard-onboard.sh" start 2>&1)"; check $? "setup: guard-onboard.sh start" "$out"
out="$(lib gc_state_set docs/agents-v0/onboarding/state.json onboarding docs/agents-v0/onboarding/report.md activeStatus=awaiting_approval 2>&1)"
check $? "setup: state set to awaiting_approval through gc_state_set" "$out"
base="$(js "$S" baseCommit)"; head="$(git -C "$proj" rev-parse HEAD)"

# --- gc_approval_ok before any approval --------------------------------------------------------------------------
out="$(approval_ok)"; rc=$?
[ $rc != 0 ] && printf '%s' "$out" | grep -q '^REFUSED approval: no approval record'; check $? "gc_approval_ok: refuses with no record" "$out"

# --- approve needs a terminal and words --------------------------------------------------------------------------
if command -v setsid >/dev/null 2>&1; then
  out="$(cd "$proj" && setsid sh "$G/guard-common.sh" approve onboard </dev/null 2>&1)"; rc=$?
  [ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED approve: .*no terminal found'; check $? "approve: refuses without a terminal (words on stdin are not read)" "$out"
fi
pty_approve() {  # pty_approve <words>: run approve onboard on a pseudo-terminal, type <words> + Enter
  python3 - "$proj" "$G/guard-common.sh" "$1" <<'PY'
import os, pty, sys, time
proj, script, words = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(proj)
    os.execvp("sh", ["sh", script, "approve", "onboard"])
buf, sent, end = b"", False, time.time() + 60
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if not sent and b"Type your approval words" in buf:
        os.write(fd, words.encode() + b"\r")
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
}
out="$(pty_approve "   " 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q 'REFUSED approve: no approval words typed'; check $? "approve: refuses empty words" "$out"
rec="$(lib gc_approval_file onboard)"
[ ! -e "$rec" ]; check $? "approve: no record after a refusal" "$rec"

words="Approved, the onboarding docs are right - Sensei"
out="$(pty_approve "$words" 2>&1)"; rc=$?
check $rc "approve: Sensei's words on the terminal approve onboard (exit 0)" "$out"
printf '%s' "$out" | grep -q 'OK approve: onboard approved at baseCommit'; check $? "approve: prints OK approve" "$out"
printf '%s' "$out" | grep -q "baseCommit: $base"; check $? "approve: shows the baseCommit before asking" "$out"

# --- the record -------------------------------------------------------------------------------------------------
id="$(lib gc_repo_id)"
[ "$rec" = "$AGENTS_V0_APPROVALS_DIR/$id/onboard.json" ] && [ -f "$rec" ]; check $? "record: written at <approvals>/<repo id>/onboard.json" "$rec"
case "$id" in proj-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) r=0 ;; *) r=1 ;; esac
check $r "record: repo id is <folder>-<12 hex>" "$id"
[ "$(js "$rec" command)" = onboard ] && [ "$(js "$rec" phase)" = onboard ]; check $? "record: command and phase are onboard"
[ "$(js "$rec" repo)" = "$(cd "$proj" && pwd)" ] && [ "$(js "$rec" repoId)" = "$id" ]; check $? "record: names the repo" "$(js "$rec" repo)"
[ "$(js "$rec" head)" = "$head" ]; check $? "record: head is HEAD" "$(js "$rec" head)"
[ "$(js "$rec" baseCommit)" = "$base" ] && [ -n "$base" ]; check $? "record: baseCommit is the state's baseCommit" "$(js "$rec" baseCommit)"
[ "$(js "$rec" words)" = "$words" ]; check $? "record: holds the words exactly as typed" "$(js "$rec" words)"
printf '%s' "$(js "$rec" approvedAt)" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$'; check $? "record: approvedAt is a local time with offset" "$(js "$rec" approvedAt)"
[ "$(stat -c %a "$rec")" = 600 ] && [ "$(stat -c %a "$(dirname "$rec")")" = 700 ]; check $? "record: file 600, folder 700" "$(stat -c '%a %n' "$rec" "$(dirname "$rec")")"

# --- the state shows the approval --------------------------------------------------------------------------------
[ "$(js "$S" approvedPhases)" = '["onboard"]' ] && [ "$(js "$S" lastApprovedPhase)" = onboard ]; check $? "state: approvedPhases and lastApprovedPhase show onboard" "$(js "$S" approvedPhases) $(js "$S" lastApprovedPhase)"
[ "$(js "$S" activeStatus)" = "" ] && [ "$(js "$S" activePhase)" = "" ]; check $? "state: active phase cleared (as sync-feature-state --approve)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["phaseDates"].get("onboard") and d["phaseTimes"].get("onboard")' "$S" 2>/dev/null
check $? "state: phaseDates and phaseTimes have onboard"
[ "$(js "$S" baseCommit)" = "$base" ]; check $? "state: baseCommit unchanged"

# --- gc_approval_ok -----------------------------------------------------------------------------------------------
out="$(approval_ok)"; check $? "gc_approval_ok: passes on the matching record" "$out"
printf '%s' "$out" | grep -q '^OK approval: onboard approved'; check $? "gc_approval_ok: prints OK approval" "$out"
cp "$S" "$tmp/state.saved"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["baseCommit"]="0"*40; json.dump(d, open(sys.argv[1],"w"), indent=2)' "$S"
out="$(approval_ok)"; rc=$?
[ $rc != 0 ] && printf '%s' "$out" | grep -q '^REFUSED approval: the approval record approves baseCommit'; check $? "gc_approval_ok: refuses when the state's baseCommit differs" "$out"
cp "$tmp/state.saved" "$S"
out="$(approval_ok)"; check $? "gc_approval_ok: passes again with the state restored" "$out"
out="$(cd "$proj" && sh "$G/guard-onboard.sh" start 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q 'already approved'; check $? "guard-onboard.sh start: refuses after the approval" "$out"

# --- the hook (installed copy): no agent access to the folder, no agent approve --------------------------------------
H="$proj/.cursor/hooks/hook-policy.py"
out="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$H" "$id" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("hp", sys.argv[1]); hp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hp)
rid, home = sys.argv[2], os.path.expanduser("~")
cases = [
    ("path", f"{home}/.agents-v0-approvals/{rid}/onboard.json", "block"),
    ("path", f"~/.agents-v0-approvals/{rid}/onboard.json", "block"),
    ("shell", f"echo '{{}}' > ~/.agents-v0-approvals/{rid}/onboard.json", "block"),
    ("shell", f"echo '{{}}' > $HOME/.agents-v0-approvals/{rid}/onboard.json", "block"),
    ("shell", f"cp /tmp/r.json {home}/.agents-v0-approvals/{rid}/onboard.json", "block"),
    ("shell", "sh .agents-v0/scripts/guard-common.sh approve onboard", "block"),
    ("shell", "sh .agents-v0/scripts/guard-onboard.sh start", "allow"),
]
bad = 0
for kind, arg, want in cases:
    got = (hp.classify_path(arg) if kind == "path" else hp.classify_command(arg))[0]
    print(f"{'ok ' if got == want else 'BAD'} {kind} want={want} got={got}: {arg}")
    bad += got != want
sys.exit(1 if bad else 0)
PY
)"; check $? "hook: denies agent writes to the approval folder (~, \$HOME, expanded) and agent approve" "$out"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
