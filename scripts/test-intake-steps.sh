#!/bin/sh
# test-intake-steps.sh (intake redo, Design: DI8): the /v0-intake step block is generated from
# `guard-intake.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; requirements-analyst has no shell.
# Run: sh scripts/test-intake-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-intake.md"
AG="$ROOT/core/common/agents/requirements-analyst.md"

out="$(sh "$ROOT/scripts/generate-intake-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-intake.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-intake.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-intake.sh $s"; check $? "block: names guard-intake.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve intake <feature>'; check $? "block: names the user's parameterized approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-intake-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-intake-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-intake.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. Run/2. Execute/' "$tmp/core/common/commands/v0-intake.md"
out="$(sh "$tmp/scripts/generate-intake-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-intake.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-intake-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-intake-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and the requirements-analyst: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|git add -A' "$DOC"; check $? "v0-intake.md: no sync-feature-state.sh or git add -A" "$(grep -n 'sync-feature-state.sh\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-intake.md: keeps the gate-commit marker"
grep -qF 'Do not run the script in the same turn as the Intake approval' "$DOC"; check $? "v0-intake.md: keeps the branch-authorisation turn marker"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"; check $? "requirements-analyst: no shell tool"
! grep -q 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG"; check $? "requirements-analyst: runs no kit script" "$(grep -n 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG" || true)"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
