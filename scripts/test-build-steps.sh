#!/bin/sh
# test-build-steps.sh (build redo, Design: DB8): the /v0-build step block is generated from
# `guard-build.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; all 12 Build subagent files (frontend-engineer, debug-investigator, and backend/bff-engineer across all 5 packs) have no shell.
# Run: sh scripts/test-build-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-build.md"

out="$(sh "$ROOT/scripts/generate-build-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-build.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-build.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-build.sh $s"; check $? "block: names guard-build.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve build <feature>'; check $? "block: names the user's parameterized approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-build-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-build-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-build.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. Run/2. Execute/' "$tmp/core/common/commands/v0-build.md"
out="$(sh "$tmp/scripts/generate-build-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-build.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-build-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-build-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and all Build subagents: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|git add -A' "$DOC"; check $? "v0-build.md: no sync-feature-state.sh or git add -A" "$(grep -n 'sync-feature-state.sh\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-build.md: keeps the gate-commit marker"
grep -qF 'kitfix-20261031-traceability' "$DOC"; check $? "v0-build.md: keeps the traceability marker"
grep -qF 'check-tests-ran.sh' "$DOC"; check $? "v0-build.md: keeps the check-tests-ran.sh marker"
for ag_name in frontend-engineer debug-investigator; do
  AG="$ROOT/core/common/agents/${ag_name}.md"
  ! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"
  check $? "$ag_name: no shell tool"
done
for pack in java dotnet node python go; do
  for ag_name in backend-engineer bff-engineer; do
    AG="$ROOT/core/$pack/agents/${ag_name}.md"
    ! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"
    check $? "$pack/$ag_name: no shell tool"
  done
done

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
