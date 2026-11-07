#!/bin/sh
# Fast step-drift and contract checks for /v0-export and /v0-deck (Step 5.2, Design: DEX8).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf '  PASS: %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL: %s\n' "$1" >&2; }

printf '=== test-export-deck-steps.sh ===\n'

# 1. Step generators match v0-export.md and v0-deck.md byte for byte
if sh scripts/generate-export-steps.sh --check >/dev/null 2>&1; then
  ok "v0-export.md step block matches guard-export.sh steps"
else
  bad "v0-export.md step block drifted from guard-export.sh steps"
fi

if sh scripts/generate-deck-steps.sh --check >/dev/null 2>&1; then
  ok "v0-deck.md step block matches guard-deck.sh steps"
else
  bad "v0-deck.md step block drifted from guard-deck.sh steps"
fi

# 2. Subagent and skill routing in v0-export.md and v0-deck.md
if grep -Fq 'docs-author' core/common/commands/v0-export.md && grep -Fq 'jira-export' core/common/commands/v0-export.md; then
  ok "v0-export.md routes to docs-author and jira-export"
else
  bad "v0-export.md missing docs-author or jira-export routing"
fi

if grep -Fq 'docs-author' core/common/commands/v0-deck.md && grep -Fq 'leadership-deck' core/common/commands/v0-deck.md; then
  ok "v0-deck.md routes to docs-author and leadership-deck"
else
  bad "v0-deck.md missing docs-author or leadership-deck routing"
fi

if grep -Eq 'product-analyst|(^|[^-])architect([^a-z-]|$)' core/common/commands/v0-export.md core/common/commands/v0-deck.md; then
  bad "v0-export.md or v0-deck.md still references legacy product-analyst or architect"
else
  ok "v0-export.md and v0-deck.md contain no stale legacy agent names"
fi

# 3. docs-author is shell-less
if grep -Fxq 'shell: false' core/common/agents/docs-author.md && ! grep -Eq '^[[:space:]]*-[[:space:]]*shell$' core/common/agents/docs-author.md; then
  ok "core/common/agents/docs-author.md enforces shell: false"
else
  bad "core/common/agents/docs-author.md missing shell: false"
fi

# 4. gate-rules has export and deck rules
if grep -Fq 'export commit.message v0(export): regenerate tickets.csv' templates/.agents-v0/gate-rules && \
   grep -Fq 'deck commit.message v0(deck): write <stem> briefing' templates/.agents-v0/gate-rules; then
  ok "templates/.agents-v0/gate-rules defines export and deck rules"
else
  bad "templates/.agents-v0/gate-rules missing export or deck rules"
fi

# 5. No internal state writers or git add -A leaked into v0-export.md or v0-deck.md
leak=0
for internal in sync-feature-state.sh check-gate-commit.sh check-traceability.sh check-attempt-budget.sh check-failure-brief.sh \
  secret_scan.py GUARD_COMMON_LIB gc_ 'guard-common.sh scan' 'git add -A'; do
  if grep -Fq -- "$internal" core/common/commands/v0-export.md || grep -Fq -- "$internal" core/common/commands/v0-deck.md; then
    bad "v0-export.md or v0-deck.md leaks internal '$internal'"
    leak=1
  fi
done
[ "$leak" -eq 0 ] && ok "v0-export.md and v0-deck.md leak no internal state writers or git add -A"

printf '=== test-export-deck-steps.sh: %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
