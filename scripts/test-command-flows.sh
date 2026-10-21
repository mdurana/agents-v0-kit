#!/bin/sh
# test-command-flows.sh — test the command state flows, install.sh --git-hooks,
# the --update in-flight guard, program.state.json, and feature state transitions.
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
}
expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then fail "$desc (expected non-zero)"; sed 's/^/    /' "$tmp/out.txt" >&2; else pass "$desc"; fi
}
expect_out() {
  if grep -Eq "$2" "$tmp/out.txt"; then pass "$1"; else fail "$1 (output lacks: $2)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi
}
commit() {
  (cd "$1" && git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$2")
}

new_repo() {
  d="$1"; shift
  mkdir -p "$d"
  git -C "$d" init -q -b main
  (cd "$d" && sh "$KIT/scripts/install.sh" "$@" "$d" >/dev/null 2>&1) || { fail "install.sh $* into $d"; return 1; }
  git -C "$d" add -A
  commit "$d" base
}

# ---------------------------------------------------------------------------------------------
# install.sh --git-hooks, AGENTS.md seeding, and the --update in-flight guard
# ---------------------------------------------------------------------------------------------
plain="$tmp/plain"
new_repo "$plain"
[ -f "$plain/AGENTS.md" ] && [ -x "$plain/.agents-v0/scripts/sync-feature-state.sh" ] && [ -x "$plain/.agents-v0/hooks/pre-push" ] \
  && pass "install seeds AGENTS.md, sync-feature-state.sh, and an executable pre-push hook" \
  || fail "install seeds AGENTS.md, sync-feature-state.sh, and an executable pre-push hook"
[ -z "$(git -C "$plain" config --get core.hooksPath || true)" ] \
  && pass "install without --git-hooks leaves core.hooksPath unset" \
  || fail "install without --git-hooks leaves core.hooksPath unset"

r="$tmp/r"
new_repo "$r" --git-hooks
[ "$(git -C "$r" config --get core.hooksPath)" = ".agents-v0/hooks" ] \
  && pass "install --git-hooks sets core.hooksPath=.agents-v0/hooks" \
  || fail "install --git-hooks sets core.hooksPath=.agents-v0/hooks"

mkdir -p "$plain/docs/agents-v0/requirements"
printf '{"activePhase":"build","activeStatus":"in_progress"}\n' > "$plain/docs/agents-v0/requirements/orders.state.json"
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --quick "$plain") >"$tmp/out.txt" 2>&1; then
  fail "install --update refuses while a story is in progress"
else
  pass "install --update refuses while a story is in progress"
  expect_out "the refusal names the story and the override" 'orders.state.json.*activePhase=build|allow-in-flight'
fi
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --quick --allow-in-flight "$plain") >"$tmp/out.txt" 2>&1; then
  pass "install --update --allow-in-flight updates anyway"
else
  fail "install --update --allow-in-flight updates anyway"; sed 's/^/    /' "$tmp/out.txt" >&2
fi
printf '{"activePhase":"","activeStatus":""}\n' > "$plain/docs/agents-v0/requirements/orders.state.json"
if (cd "$KIT" && KIT_VALIDATING=1 sh scripts/install.sh --update --quick "$plain") >"$tmp/out.txt" 2>&1; then
  pass "install --update proceeds once no story is in progress"
else
  fail "install --update proceeds once no story is in progress"; sed 's/^/    /' "$tmp/out.txt" >&2
fi

# --no-verify is refused by the shell policy.
act="$(HOOK_CMD='git commit --no-verify -m skip' python3 "$KIT/core/common/hooks/hook-policy.py" shell)"
case "$act" in *'"block"'*) pass "an agent cannot skip git hooks with --no-verify" ;; *) fail "an agent cannot skip git hooks with --no-verify ($act)" ;; esac

# ---------------------------------------------------------------------------------------------
# /v0-roadmap -> /v0-architecture -> /v0-plan program state flow
# ---------------------------------------------------------------------------------------------
mkdir -p "$r/docs/agents-v0/roadmap" "$r/docs/agents-v0/milestones"
printf '# Roadmap: claims\n' > "$r/docs/agents-v0/roadmap/claims.md"
expect_pass "roadmap: sync-feature-state approves roadmap in program.state.json" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/roadmap/claims.md --approve roadmap --clear-active
grep -Fq '"lastApprovedPhase": "roadmap"' "$r/docs/agents-v0/program.state.json" \
  && pass "program.state.json records lastApprovedPhase=roadmap" \
  || fail "program.state.json records lastApprovedPhase=roadmap"

expect_pass "architecture: sync-feature-state approves architecture in program.state.json" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/architecture.md --approve architecture --clear-active
grep -Fq '"lastApprovedPhase": "architecture"' "$r/docs/agents-v0/program.state.json" \
  && pass "program.state.json records lastApprovedPhase=architecture" \
  || fail "program.state.json records lastApprovedPhase=architecture"

printf '# Milestone: P1\n' > "$r/docs/agents-v0/milestones/p1.md"
expect_pass "plan: sync-feature-state approves plan in program.state.json" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/milestones/p1.md --approve plan --clear-active
grep -Fq '"lastApprovedPhase": "plan"' "$r/docs/agents-v0/program.state.json" \
  && pass "program.state.json records lastApprovedPhase=plan" \
  || fail "program.state.json records lastApprovedPhase=plan"

# ---------------------------------------------------------------------------------------------
# /v0-intake -> /v0-design -> /v0-build -> /v0-verify feature state flow
# ---------------------------------------------------------------------------------------------
mkdir -p "$r/docs/agents-v0/requirements"
ORD="docs/agents-v0/requirements/orders.md"
printf '# Orders\nAs a clerk, I want to place an order, so that stock is reserved.\n' > "$r/$ORD"
expect_pass "intake: sync-feature-state approves intake" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --approve intake --clear-active
grep -Fq '"lastApprovedPhase": "intake"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "orders.state.json records lastApprovedPhase=intake" \
  || fail "orders.state.json records lastApprovedPhase=intake"

expect_pass "verify: sync-feature-state approves verify and sets verifyPassed=true" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --approve design --approve build --approve verify --verify-passed true --clear-active
grep -Fq '"verifyPassed": true' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "orders.state.json records verifyPassed=true" \
  || fail "orders.state.json records verifyPassed=true"

if [ "$status" -ne 0 ]; then
  echo "test-command-flows: FAILED" >&2
  exit 1
fi
echo "test-command-flows: OK"
