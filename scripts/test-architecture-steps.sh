#!/bin/sh
# test-architecture-steps.sh (architecture redo, Design: DA8): the /v0-architecture step block is generated from
# `guard-architecture.sh steps` and matches it byte for byte; a hand edit is caught by --check; the prose keeps no old
# state writer or `git add -A`; solution-architect and design-reviewer have no shell.
# Run: sh scripts/test-architecture-steps.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
passed=0; failed=0
ok() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
bad() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2" "${3:-}"; fi; }
DOC="$ROOT/core/common/commands/v0-architecture.md"
AG1="$ROOT/core/common/agents/solution-architect.md"
AG2="$ROOT/core/common/agents/design-reviewer.md"
SK="$ROOT/core/common/skills/program-architecture/SKILL.md"

out="$(sh "$ROOT/scripts/generate-architecture-steps.sh" --check 2>&1)"; check $? "generator --check: the block matches guard-architecture.sh steps" "$out"
steps="$(sh "$ROOT/templates/.agents-v0/scripts/guard-architecture.sh" steps)"
block="$(sed -n '/^<!-- BEGIN generated:/,/^<!-- END generated -->$/p' "$DOC" | sed '1d;$d')"
[ -n "$steps" ] && [ "$block" = "$steps" ]; check $? "block: byte for byte the guard's steps output"
for s in check start block ready commit; do
  printf '%s' "$block" | grep -qF "sh .agents-v0/scripts/guard-architecture.sh $s"; check $? "block: names guard-architecture.sh $s"
done
printf '%s' "$block" | grep -qF 'guard-common.sh approve architecture'; check $? "block: names the user's approve step"

# A hand edit inside the block is caught (on a temp copy of the kit files the generator reads).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-architecture-steps.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/scripts" "$tmp/core/common/commands" "$tmp/templates/.agents-v0/scripts"
cp "$ROOT/scripts/generate-architecture-steps.sh" "$tmp/scripts/" && cp "$DOC" "$tmp/core/common/commands/"
cp "$ROOT/templates/.agents-v0/scripts/guard-architecture.sh" "$ROOT/templates/.agents-v0/scripts/guard-common.sh" "$tmp/templates/.agents-v0/scripts/"
cp "$ROOT/templates/.agents-v0/gate-rules" "$tmp/templates/.agents-v0/"
sed -i 's/^2\. Run/2. Execute/' "$tmp/core/common/commands/v0-architecture.md"
out="$(sh "$tmp/scripts/generate-architecture-steps.sh" --check 2>&1)"; rc=$?
[ $rc = 1 ] && printf '%s' "$out" | grep -q '^FAIL: the v0-architecture.md step block differs'; check $? "generator --check: a hand edit in the block fails" "$out"
out="$(sh "$tmp/scripts/generate-architecture-steps.sh" 2>&1)" && out="$(sh "$tmp/scripts/generate-architecture-steps.sh" --check 2>&1)"
check $? "generator: rewriting the block makes --check pass again" "$out"

# The prose and the subagents: no old state writer, no git add -A, no shell.
! grep -q 'sync-feature-state.sh\|git add -A' "$DOC"; check $? "v0-architecture.md: no sync-feature-state.sh or git add -A" "$(grep -n 'sync-feature-state.sh\|git add -A' "$DOC" || true)"
grep -qF 'kitfix-20261031-gate-commit' "$DOC"; check $? "v0-architecture.md: keeps the gate-commit marker"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG1"; check $? "solution-architect: no shell tool"
! awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^[[:space:]]*-[[:space:]]*shell$/{x=1} END{exit !x}' "$AG2"; check $? "design-reviewer: no shell tool"
! grep -q 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG1" "$AG2" "$SK"; check $? "solution-architect, design-reviewer, and skill: run no kit script" "$(grep -n 'sync-feature-state.sh\|sh \.agents-v0/scripts' "$AG1" "$AG2" "$SK" || true)"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
