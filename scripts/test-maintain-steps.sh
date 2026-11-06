#!/bin/sh
# test-maintain-steps.sh (maintain redo, Design: DM8): the /v0-maintain step block is generated from
# `guard-maintain.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; maintenance-engineer has no shell; v0-triage.md routes through guard-maintain.sh.
# Run: sh scripts/test-maintain-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-maintain.md"
TRIAGE="$ROOT/core/common/commands/v0-triage.md"

out="$(sh "$ROOT/scripts/generate-maintain-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-maintain.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-maintain.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-maintain.sh $s"; check $? "block: names guard-maintain.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve maintain <id>'; check $? "block: names Sensei's parameterized approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-maintain-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-maintain-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-maintain.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. After/2. Once/' "$tmp/core/common/commands/v0-maintain.md"
out="$(sh "$tmp/scripts/generate-maintain-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-maintain.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-maintain-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-maintain-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and maintenance-engineer subagent: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC"
check $? "v0-maintain.md: no internal state writer or git add -A" "$(grep -n 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-maintain.md: keeps the gate-commit marker"
grep -qF 'docs/agents-v0/lessons.md' "$DOC"; check $? "v0-maintain.md: keeps the lessons.md marker"
grep -qF 'check-tests-ran.sh' "$DOC"; check $? "v0-maintain.md: keeps the check-tests-ran.sh marker"
grep -Eqi 'explicit.*approval|approval.*explicit' "$DOC"; check $? "v0-maintain.md: keeps explicit approval wording"

! grep -q 'sync-feature-state.sh' "$TRIAGE"; check $? "v0-triage.md: does not call sync-feature-state.sh directly"
grep -qF 'guard-maintain.sh start <id> --tier trivial' "$TRIAGE"; check $? "v0-triage.md: routes trivial lane through guard-maintain.sh start <id> --tier trivial"

AG="$ROOT/core/common/agents/maintenance-engineer.md"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"
check $? "maintenance-engineer: no shell tool"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
