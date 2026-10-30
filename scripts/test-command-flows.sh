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

expect_out "intake: --approve intake names the branch step as the next turn (kitfix-20261031-branch-guard)" \
  'Next: ask the user to authorise branch feature/orders'

# kitfix-20261031-branch-guard: after Intake, a feature story works only on feature/<feature>.
expect_fail "branch guard: --active-phase design in_progress is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_out "branch guard: the refusal names feature/orders and the branch step" \
  'FAIL: design for orders runs only on feature/orders \(current: main\)'
expect_out "branch guard: with no branch yet, the refusal points at /v0-intake" 'No feature/orders branch exists'
expect_fail "branch guard: --active-phase build awaiting_approval is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase build --status awaiting_approval
expect_fail "branch guard: --active-phase verify in_progress is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase verify --status in_progress
expect_fail "branch guard: --active-phase release in_progress is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase release --status in_progress
expect_fail "branch guard: --approve build is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --approve build
expect_fail "branch guard: --verify-passed is refused on main" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --verify-passed true
expect_pass "branch guard: recording blocked on main is allowed" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase build --status blocked --reason "Dependency P1-A not verified"
expect_pass "branch guard: AGENTS_V0_SKIP_BRANCH_GUARD=1 skips the check (fixtures only)" "$r" \
  env AGENTS_V0_SKIP_BRANCH_GUARD=1 sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_pass "branch guard: clear the fixture's active phase" "$r" \
  env AGENTS_V0_SKIP_BRANCH_GUARD=1 sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --clear-active
git -C "$r" checkout -q -b feature/other
expect_fail "branch guard: a different story branch is refused" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_out "branch guard: an existing-but-elsewhere message is not printed for a missing branch" 'No feature/orders branch exists'
git -C "$r" checkout -q main
git -C "$r" branch -q feature/orders
expect_fail "branch guard: still refused on main once feature/orders exists" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_out "branch guard: with the branch present, the refusal points at its worktree" 'Open the feature/orders worktree'
git -C "$r" checkout -q feature/orders
# kitfix-20261031-gate-commit: the next phase does not start until the last approved gate is committed.
expect_fail "gate commit: design in_progress is refused while the intake gate is uncommitted" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_out "gate commit: the refusal names the gate and the commit to make" \
  'FAIL: intake was approved for orders, but its work is not committed'
expect_out "gate commit: the refusal prints the gate commit command" 'git commit -m "orders: intake approved"'
git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@example.invalid commit -qm "orders: intake approved"
expect_pass "branch guard: --active-phase design in_progress is allowed on feature/orders" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@example.invalid commit -qm "orders: design in progress (fixture)"
P0="docs/agents-v0/requirements/p0-a-platform-skeleton.md"
printf '# P0-A\nStory: P0-A\nMilestone: P0\n' > "$r/$P0"
expect_fail "branch guard: P0-A verify is refused off the integration branch" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$P0" --active-phase verify --status in_progress
expect_out "branch guard: the P0-A refusal names the integration branch" 'P0-A verify runs only on the integration branch main'
git -C "$r" checkout -q main
expect_pass "branch guard: P0-A verify is allowed on the integration branch" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$P0" --active-phase verify --status in_progress
mv "$r/$P0" "$tmp/p0-a.md.moved"; mv "$r/docs/agents-v0/requirements/p0-a-platform-skeleton.state.json" "$tmp/p0-a.state.moved"
git -C "$r" checkout -q feature/orders
expect_fail "design evidence: --approve design is refused without design/orders/design.md (kitfix-20261031-skeleton)" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh "$ORD" --approve design
expect_out "design evidence: the refusal names the missing design.md" 'FAIL: --approve design needs docs/agents-v0/design/orders/design.md'

mkdir -p "$r/docs/agents-v0/verify/orders" && printf '# Quality gate: orders\nCritical: 0\n' > "$r/docs/agents-v0/verify/orders/quality-gate.md"
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
