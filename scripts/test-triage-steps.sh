#!/bin/sh
# test-triage-steps.sh (triage-status redo, Design: DST8): the /v0-triage step block is generated from
# `guard-triage.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; maintenance-engineer has no shell.
# Run: sh scripts/test-triage-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-triage.md"

out="$(sh "$ROOT/scripts/generate-triage-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-triage.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-triage.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-triage.sh $s"; check $? "block: names guard-triage.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve triage <id>'; check $? "block: names the user's approve triage <id> alias"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-triage-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-triage-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-triage.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. \*\*Start/2. **Begin/' "$tmp/core/common/commands/v0-triage.md"
out="$(sh "$tmp/scripts/generate-triage-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-triage.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-triage-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-triage-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and maintenance-engineer subagent: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC"
check $? "v0-triage.md: no internal state writer or git add -A" "$(grep -n 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-triage.md: keeps the gate-commit marker"
grep -qF 'docs/agents-v0/lessons.md' "$DOC"; check $? "v0-triage.md: keeps the lessons.md marker"
grep -Eqi 'external.*approval|approval.*external' "$DOC"; check $? "v0-triage.md: keeps external approval wording"

AG="$ROOT/core/common/agents/maintenance-engineer.md"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"
check $? "maintenance-engineer: no shell tool"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
