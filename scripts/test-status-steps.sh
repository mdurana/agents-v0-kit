#!/bin/sh
# test-status-steps.sh (triage-status redo, Design: DST8): the /v0-status step block is generated from
# `stories-status.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`, and retains required MEM-01 and check-release-evidence.sh markers.
# Run: sh scripts/test-status-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-status.md"

out="$(sh "$ROOT/scripts/generate-status-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches stories-status.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/stories-status.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte stories-status.sh steps output"
printf '%s' "$block" | grep -qF 'sh .agents-v0/scripts/stories-status.sh'; check $? "block: names stories-status.sh"
printf '%s' "$block" | grep -qF 'sh .agents-v0/scripts/stories-status.sh --story <slug>'; check $? "block: names stories-status.sh --story <slug>"
printf '%s' "$block" | grep -qF 'sh .agents-v0/scripts/check-release-evidence.sh'; check $? "block: names check-release-evidence.sh"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-status-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-status-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/stories-status.sh" "$tmp/templates/.agents-v0/scripts/"
sed -i 's/^2\. \*\*Select/2. **Pick/' "$tmp/core/common/commands/v0-status.md"
out="$(sh "$tmp/scripts/generate-status-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-status.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-status-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-status-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose: no internal state writer or git add -A, keeps MEM-01 and check-release-evidence.sh.
! grep -q 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC"
check $? "v0-status.md: no internal state writer or git add -A" "$(grep -n 'sync-feature-state.sh\|check-gate-commit.sh\|check-traceability.sh\|check-attempt-budget.sh\|check-failure-brief.sh\|secret_scan.py\|GUARD_COMMON_LIB\|gc_\|guard-common.sh scan\|git add -A' "$DOC" || true)"
grep -qF 'MEM-01' "$DOC"; check $? "v0-status.md: keeps MEM-01 marker"
grep -qF 'stories-status.sh' "$DOC"; check $? "v0-status.md: keeps stories-status.sh marker"
grep -qF 'check-release-evidence.sh' "$DOC"; check $? "v0-status.md: keeps check-release-evidence.sh marker"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
