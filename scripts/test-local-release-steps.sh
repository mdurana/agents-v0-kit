#!/bin/sh
# test-local-release-steps.sh (local-release redo, Design: DLR8): the /v0-local-release step block is generated from
# `guard-local-release.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; release-manager has no shell; /v0-release and release-pr are removed.
# Run: sh scripts/test-local-release-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-local-release.md"

out="$(sh "$ROOT/scripts/generate-local-release-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-local-release.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-local-release.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-local-release.sh $s"; check $? "block: names guard-local-release.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve local-release <feature>'; check $? "block: names the user's parameterized approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-local-release-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-local-release-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-local-release.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. Run/2. Execute/' "$tmp/core/common/commands/v0-local-release.md"
out="$(sh "$tmp/scripts/generate-local-release-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-local-release.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-local-release-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-local-release-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and release-manager subagent: no old state writer, no git add -A, no shell, and removed /v0-release & release-pr.
! grep -q 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC"
check $? "v0-local-release.md: no internal state writer or git add -A" "$(grep -n 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-branch-guard' "$DOC"; check $? "v0-local-release.md: keeps the branch-guard marker"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-local-release.md: keeps the gate-commit marker"
grep -qF 'kitfix-20261031-keep-branches' "$DOC"; check $? "v0-local-release.md: keeps the keep-branches marker"
grep -qF 'kitfix-20261029-step4-p1e' "$DOC"; check $? "v0-local-release.md: keeps the step4-p1e marker"
grep -qF 'check-tests-ran.sh' "$DOC"; check $? "v0-local-release.md: keeps the check-tests-ran.sh marker"
grep -qF 'check-lessons.sh' "$DOC"; check $? "v0-local-release.md: keeps the check-lessons.sh marker"
grep -qF 'git merge --squash feature/<feature>' "$DOC"; check $? "v0-local-release.md: keeps the squash-merge marker"

AG="$ROOT/core/common/agents/release-manager.md"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"
check $? "release-manager: no shell tool"

[ ! -e "$ROOT/core/common/commands/v0-release.md" ]; check $? "v0-release.md is removed"
[ ! -e "$ROOT/core/common/skills/release-pr/SKILL.md" ]; check $? "release-pr/SKILL.md is removed"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
