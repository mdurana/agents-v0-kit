#!/bin/sh
# test-guard-commit.sh: the normal path of the onboard commit step (onboard redo, Design: D4).
# start, discovery docs, ready, the user's approve (driven on a pseudo-terminal), then `guard-onboard.sh commit` makes one
# commit of the onboard paths and tags onboard-v1, leaving a clean tree. Refusals covered: commit before approve, a
# record without the approved state, and a staged fake secret (FAKE value built at run time).
# Test-only: the kit test copy (install.sh --test-overrides) reads AGENTS_V0_APPROVALS_DIR, so the record goes to a
# temp folder, never to the real ~/.agents-v0-approvals.
# Run: sh scripts/test-guard-commit.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-commit.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi
export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(json.dumps(v) if isinstance(v,(list,dict)) else v)' "$1" "$2" 2>&1; }

proj="$tmp/proj"; mkdir -p "$proj"
git -C "$proj" init -q -b main && printf 'x\n' > "$proj/README.md" && git -C "$proj" add README.md && git -C "$proj" commit -q -m init
out="$(KIT_VALIDATING=1 sh "$ROOT/scripts/install.sh" --test-overrides "$proj" 2>&1)"; check $? "install: kit test copy (--test-overrides)" "$(printf '%s' "$out" | tail -20)"
# The kit install is the user's own commit, before onboarding (outside the onboard commit).
git -C "$proj" add -A && git -C "$proj" commit -q -m "install agents-v0"; check $? "setup: kit install committed"
G="$proj/.agents-v0/scripts"; S="$proj/docs/agents-v0/onboarding/state.json"
lib() { (cd "$proj" && GC_HERE="$G" GUARD_COMMON_LIB=1 && . "$G/guard-common.sh" && "$@"); }
commit() { (cd "$proj" && sh "$G/guard-onboard.sh" commit) 2>&1; }

out="$(cd "$proj" && sh "$G/guard-onboard.sh" start 2>&1)"; check $? "setup: start" "$out"
head="$(git -C "$proj" rev-parse HEAD)"
printf '# Onboarding report\n\ncommit: %s\n\nThe app entry point is `README.md:1`.\n' "$head" > "$proj/docs/agents-v0/onboarding/report.md"
for d in architecture.md network.md; do
  [ ! -f "$proj/docs/agents-v0/$d" ] || printf '# %s\n\nOne module, no network calls (`README.md:1`).\n' "$d" > "$proj/docs/agents-v0/$d"
done
out="$(cd "$proj" && sh "$G/guard-onboard.sh" ready 2>&1)"; check $? "setup: ready" "$out"

# --- refused before the user approves ---------------------------------------------------------------------------------
out="$(commit)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED commit: onboarding is not approved'; check $? "commit: refused before approve" "$out"
[ "$(git -C "$proj" rev-parse HEAD)" = "$head" ]; check $? "commit refused: no commit made"

# --- the user's approve (pty), then a record without the approved state is still refused -------------------------------
pty_approve() {
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
out="$(pty_approve "Approved, the onboarding docs are right" 2>&1)"; check $? "approve: approver's words on the terminal (exit 0)" "$out"
cp "$S" "$tmp/state-approved.json"
# a stray record: the record is there but the state does not show onboard approved (state edited by the test only)
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["approvedPhases"]=[]; json.dump(d, open(p,"w"), indent=2)' "$S"
out="$(commit)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED commit: onboarding is not approved'; check $? "commit: a record alone (state not approved) is refused" "$out"
cp "$tmp/state-approved.json" "$S"

# --- a staged fake secret inside the onboard paths is refused by the staged scan ------------------------------------
fake="AKIA""QZ7X3B5N8M2K4J6H"
printf 'key = %s\n' "$fake" > "$proj/docs/agents-v0/onboarding/leak.md"
out="$(commit)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED scan-staged'; check $? "commit: a staged fake AWS key is refused by the scan" "$out"
[ "$(git -C "$proj" rev-parse HEAD)" = "$head" ]; check $? "scan refused: no commit made"
git -C "$proj" restore --staged docs/agents-v0/onboarding/leak.md && mkdir -p "$tmp/trash" && mv "$proj/docs/agents-v0/onboarding/leak.md" "$tmp/trash/"

# --- a path staged outside the onboard paths is refused -------------------------------------------------------------
printf 'y\n' > "$proj/other.txt" && git -C "$proj" add other.txt
out="$(commit)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED commit: the index already holds paths outside the onboard commit paths: other.txt'
check $? "commit: refuses when the index holds a path outside the onboard paths" "$out"
git -C "$proj" restore --staged other.txt && mv "$proj/other.txt" "$tmp/trash/"

# --- the normal path ----------------------------------------------------------------------------------------------
out="$(commit)"; rc=$?
check $rc "commit: exits 0 after the user's approve" "$out"
printf '%s' "$out" | grep -q '^OK approval:' && printf '%s' "$out" | grep -q '^OK scan-staged' && printf '%s' "$out" | grep -q '^OK commit: onboard committed on main as .*, tagged onboard-v1'
check $? "commit: prints OK approval, OK scan-staged and OK commit with the tag" "$out"
nexta="$(sed -n 's/^onboard approved\.next //p' "$proj/.agents-v0/gate-rules")"
printf '%s' "$out" | grep -qF "Next: $nexta"; check $? "commit: prints the approved next step" "$out"
[ "$(git -C "$proj" rev-parse HEAD~1)" = "$head" ]; check $? "commit: exactly one new commit"
[ "$(git -C "$proj" log -1 --format=%s)" = "onboarding: onboard approved" ]; check $? "commit: message from gate-rules"
[ "$(git -C "$proj" rev-parse onboard-v1^{commit})" = "$(git -C "$proj" rev-parse HEAD)" ] && [ "$(git -C "$proj" cat-file -t onboard-v1)" = tag ]
check $? "commit: annotated tag onboard-v1 on the commit"
files="$(git -C "$proj" diff --name-only HEAD~1 HEAD)"
printf '%s\n' "$files" | grep -qx docs/agents-v0/onboarding/report.md && printf '%s\n' "$files" | grep -qx docs/agents-v0/onboarding/state.json \
  && printf '%s\n' "$files" | grep -qx docs/agents-v0/discovery/baseline-audit.txt
check $? "commit: holds the report, the approved state and the baseline record" "$files"
! printf '%s\n' "$files" | grep -v '^docs/agents-v0/' | grep -q .; check $? "commit: only onboard paths" "$files"
[ -z "$(git -C "$proj" status --porcelain --untracked-files=all | grep -v '\.lock$')" ]; check $? "commit: the tree is clean after" "$(git -C "$proj" status --porcelain)"
[ "$(js "$S" approvedPhases)" = '["onboard"]' ]; check $? "commit: the committed state shows onboard approved" "$(js "$S" approvedPhases)"

# --- the onboarding gate message points to the guard ----------------------------------------------------------------
out="$(cd "$proj" && sh .agents-v0/scripts/check-gate-commit.sh --message onboard docs/agents-v0/onboarding/report.md 2>&1)"
printf '%s' "$out" | grep -qx 'sh .agents-v0/scripts/guard-onboard.sh commit'; check $? "check-gate-commit: onboarding message is the guard's commit step" "$out"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
