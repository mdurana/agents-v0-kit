#!/bin/sh
# test-roadmap-steps.sh (roadmap redo, Design: DR8): the /v0-roadmap step block is generated from
# `guard-roadmap.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; roadmap-planner has no shell.
# Run: sh scripts/test-roadmap-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-roadmap.md"
AG="$ROOT/core/common/agents/roadmap-planner.md"
SK="$ROOT/core/common/skills/program-roadmap/SKILL.md"

out="$(sh "$ROOT/scripts/generate-roadmap-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-roadmap.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-roadmap.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check validate start ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-roadmap.sh $s"; check $? "block: names guard-roadmap.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve roadmap'; check $? "block: names the user's approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-roadmap-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-roadmap-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-roadmap.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^3\. Run/3. Execute/' "$tmp/core/common/commands/v0-roadmap.md"
out="$(sh "$tmp/scripts/generate-roadmap-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-roadmap.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-roadmap-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-roadmap-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and the roadmap-planner: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|git add -A' "$DOC"; check $? "v0-roadmap.md: no sync-feature-state.sh or git add -A" "$(grep -n 'sync-feature-state.sh\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-roadmap.md: keeps the gate-commit marker"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG"; check $? "roadmap-planner: no shell tool"
! grep -q 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG" "$SK"; check $? "roadmap-planner and skill: run no kit script" "$(grep -n 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG" "$SK" || true)"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
