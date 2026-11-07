#!/bin/sh
# test-guard-onboard.sh: the normal path of guard-onboard.sh start, block (onboard redo, Design: D2) and ready (D3).
# A fresh repository gets the kit; `start` sets the onboard state (docs/agents-v0/onboarding/state.json) and `block`
# records the plain reason and the next step. Every write goes through guard-common.sh gc_state_set.
# Run: sh scripts/test-guard-onboard.sh   (KEEP_TEST_TMP=1 keeps the temp dir)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }

# git identity of its own; no GIT_* from the caller leaks in.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-onboard.XXXXXX")"
if [ "${KEEP_TEST_TMP:-}" = 1 ]; then printf 'temp dir kept: %s\n' "$tmp"; else trap 'rm -rf "$tmp"' EXIT; fi

js() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], "<missing>"); print(v)' "$1" "$2" 2>&1; }

# --- a fresh repository with the kit ---------------------------------------------------------------------------
proj="$tmp/proj"
mkdir -p "$proj" && git -C "$proj" init -q -b main && printf 'x\n' > "$proj/README.md" \
  && git -C "$proj" add README.md && git -C "$proj" commit -q -m init
head="$(git -C "$proj" rev-parse HEAD)"
out="$(KIT_VALIDATING=1 sh "$ROOT/scripts/install.sh" "$proj" 2>&1)"; check $? "install: kit installs into a fresh repository" "$(printf '%s' "$out" | tail -20)"
G="$proj/.agents-v0/scripts/guard-onboard.sh"
[ -f "$G" ]; check $? "install seeds .agents-v0/scripts/guard-onboard.sh"
[ -f "$proj/.agents-v0/gate-rules" ]; check $? "install seeds .agents-v0/gate-rules"
out="$(sh "$ROOT/scripts/check-installed-kit.sh" "$proj" 2>&1)"; rc=$?
[ $rc = 0 ] && printf '%s' "$out" | grep -q HASH-OK; check $? "check-installed-kit: HASH-OK with guard-onboard.sh" "$(printf '%s' "$out" | grep -v '^OK' | tail -20)"
S="$proj/docs/agents-v0/onboarding/state.json"
[ ! -f "$S" ]; check $? "fresh repository: no onboard state yet"

# --- start: sets the onboard state -----------------------------------------------------------------------------
mkdir -p "$proj/src"
out="$(cd "$proj/src" && sh "$G" start 2>&1)"; rc=$?
check $rc "start: exits 0 on a fresh repository (run from a subdirectory)" "$out"
printf '%s' "$out" | grep -q '^OK start: onboard state is in_progress'; check $? "start: prints OK start with the state" "$out"
printf '%s' "$out" | grep -q '^Next: '; check $? "start: prints the next step" "$out"
[ -f "$S" ]; check $? "start: writes docs/agents-v0/onboarding/state.json"
[ "$(js "$S" activePhase)" = onboard ]; check $? "start: activePhase is onboard" "$(js "$S" activePhase)"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "start: activeStatus is in_progress" "$(js "$S" activeStatus)"
[ "$(js "$S" feature)" = onboarding ]; check $? "start: feature is onboarding"
[ "$(js "$S" blockedReason)" = "" ]; check $? "start: blockedReason is empty"
[ "$(js "$S" artifact)" = docs/agents-v0/onboarding/report.md ]; check $? "start: artifact is the onboarding report"
[ "$(js "$S" baseCommit)" = "$head" ]; check $? "start: baseCommit is HEAD" "$(js "$S" baseCommit) vs $head"
[ "$(js "$S" approvedPhases)" = "[]" ]; check $? "start: approvedPhases starts empty (sync-feature-state keys kept)"
[ -f "$proj/docs/agents-v0/onboarding/report.md" ]; check $? "start: copies the report template to report.md"

# --- block: records the reason and the next step ---------------------------------------------------------------
reason="the staging database is unreachable from this machine"
out="$(cd "$proj" && sh "$G" block "$reason" 2>&1)"; rc=$?
check $rc "block: exits 0" "$out"
printf '%s' "$out" | grep -qF "OK block: onboard state is blocked: $reason"; check $? "block: prints OK block with the reason" "$out"
next="$(sed -n 's/^onboard block\.next //p' "$proj/.agents-v0/gate-rules")"
printf '%s' "$out" | grep -qF "Next: $next"; check $? "block: prints the next step from gate-rules" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "block: activeStatus is blocked" "$(js "$S" activeStatus)"
[ "$(js "$S" activePhase)" = onboard ]; check $? "block: activePhase stays onboard"
[ "$(js "$S" blockedReason)" = "$reason" ]; check $? "block: blockedReason is the plain reason" "$(js "$S" blockedReason)"
[ -n "$next" ] && [ "$(js "$S" nextStep)" = "$next" ]; check $? "block: nextStep is recorded (gate-rules default)" "$(js "$S" nextStep)"
[ "$(js "$S" baseCommit)" = "$head" ]; check $? "block: keeps the other keys (baseCommit)"
out="$(cd "$proj" && sh "$G" block "waiting for the API key" --next "Ask the user for the API key" 2>&1)"; rc=$?
[ $rc = 0 ] && [ "$(js "$S" nextStep)" = "Ask the user for the API key" ] && [ "$(js "$S" blockedReason)" = "waiting for the API key" ]
check $? "block --next: records the given next step" "$out"

# --- ready (Design: D3): baseline record, docs check, awaiting_approval ---------------------------------------
B="$proj/docs/agents-v0/discovery/baseline-audit.txt"
out="$(cd "$proj" && sh "$G" ready 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED ready: onboarding is not in progress (state: blocked)'
check $? "ready: refused while onboarding is blocked (run start first)" "$out"
[ "$(js "$S" activeStatus)" = blocked ]; check $? "ready refused: the state is unchanged"
out="$(cd "$proj" && sh "$G" start 2>&1)"; check $? "start: resumes a blocked onboarding" "$out"
out="$(cd "$proj" && sh "$G" ready 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED ready: the onboarding docs check failed'
check $? "ready: refused while the onboarding docs still fail the docs check (template report)" "$out"
[ "$(js "$S" activeStatus)" = in_progress ]; check $? "ready refused on docs: the state stays in_progress"
# discovery's part: the report and the docs the kit seeded, with their sample rows replaced.
printf '# Onboarding report\n\ncommit: %s\n\nThe app entry point is `README.md:1`.\n' "$head" > "$proj/docs/agents-v0/onboarding/report.md"
for d in architecture.md network.md; do
  [ ! -f "$proj/docs/agents-v0/$d" ] || printf '# %s\n\nOne module, no network calls (`README.md:1`).\n' "$d" > "$proj/docs/agents-v0/$d"
done
out="$(cd "$proj/src" && sh "$G" ready 2>&1)"; rc=$?
check $rc "ready: exits 0 after discovery (run from a subdirectory)" "$out"
printf '%s' "$out" | grep -q '^OK ready: onboard state is awaiting_approval (baseline NO-BUILD, docs/agents-v0/discovery/baseline-audit.txt)'
check $? "ready: prints OK ready with the state and the baseline result" "$out"
nextr="$(sed -n 's/^onboard ready\.next //p' "$proj/.agents-v0/gate-rules")"
[ -n "$nextr" ] && printf '%s' "$out" | grep -qF "Next: $nextr"; check $? "ready: prints the next step (the user's approve) from gate-rules" "$out"
[ -f "$B" ] && grep -q '^result: NO-BUILD$' "$B" && grep -q "^commit: $head\$" "$B"
check $? "ready: the baseline audit --record wrote docs/agents-v0/discovery/baseline-audit.txt" "$(cat "$B" 2>&1)"
[ "$(js "$S" activeStatus)" = awaiting_approval ]; check $? "ready: activeStatus is awaiting_approval" "$(js "$S" activeStatus)"
[ "$(js "$S" nextStep)" = "$nextr" ]; check $? "ready: nextStep is the user's approve step" "$(js "$S" nextStep)"
[ "$(js "$S" blockedReason)" = "" ]; check $? "ready: blockedReason is cleared"
[ "$(js "$S" baseCommit)" = "$head" ]; check $? "ready: keeps the other keys (baseCommit)"
out="$(cd "$proj" && sh "$G" start 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^REFUSED start: onboarding is awaiting'
check $? "start: refused once ready set awaiting_approval" "$out"

# --- the split: guard-onboard.sh never writes the state file itself --------------------------------------------
write_re='json\.dump|os\.replace|open\(|>>?[[:space:]]*"?\$\{?go_state|state\.json'
hits="$(grep -nv '^[[:space:]]*#' "$G" | grep -E "$write_re")"
[ -f "$G" ] && [ -z "$hits" ]; check $? "guard-onboard.sh has no state write of its own (gc_state_set in guard-common.sh is the writer)" "$hits"
grep -q 'gc_state_set' "$G"; check $? "guard-onboard.sh calls gc_state_set"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
