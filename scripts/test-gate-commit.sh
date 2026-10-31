#!/bin/sh
# test-gate-commit.sh — one commit per approved gate, squash release, and gate-to-gate traceability
# (kitfix-20261031-gate-commit, kitfix-20261031-traceability). Run by validate-kit.sh. Needs git, python3.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0
pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
expect_pass() { desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi; }
expect_fail() { desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then fail "$desc (expected non-zero)"; sed 's/^/    /' "$tmp/out.txt" >&2; else pass "$desc"; fi; }
expect_out() { if grep -Eq -- "$2" "$tmp/out.txt"; then pass "$1"; else fail "$1 (output lacks: $2)"; sed 's/^/    /' "$tmp/out.txt" >&2; fi; }
G() { d="$1"; shift; git -C "$d" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
S=".agents-v0/scripts"
export AGENTS_V0_TZ=Asia/Manila

r="$tmp/portal"; mkdir -p "$r"; git -C "$r" init -q -b main
(cd "$r" && sh "$KIT/scripts/install.sh" --test-overrides "$r" >/dev/null 2>&1) || fail "install.sh"   # kit test copy: keeps the AGENTS_V0_* overrides
G "$r" add -A; G "$r" commit -qm base

# ---- project phases: commit to main, one commit each, tagged -----------------------------------
mkdir -p "$r/docs/agents-v0/roadmap"; printf '# Roadmap\n' > "$r/docs/agents-v0/roadmap/claims.md"
expect_pass "roadmap: approve" "$r" sh $S/sync-feature-state.sh docs/agents-v0/roadmap/claims.md --approve roadmap --clear-active
expect_out "roadmap: the approval prints the commit and the tag" 'git commit -m "program: roadmap approved" && git tag -a roadmap-v<n>'
expect_fail "architecture in_progress is refused while the roadmap gate is uncommitted" "$r" \
  sh $S/sync-feature-state.sh docs/agents-v0/architecture.md --active-phase architecture --status in_progress
expect_out "the refusal names the roadmap gate" 'FAIL: roadmap was approved for .*, but its work is not committed'
G "$r" add docs/agents-v0/roadmap docs/agents-v0/program.state.json; G "$r" commit -qm "program: roadmap approved"; G "$r" tag -a roadmap-v1 -m "roadmap approved"
expect_pass "architecture starts once the roadmap gate is committed and tagged" "$r" \
  sh $S/sync-feature-state.sh docs/agents-v0/architecture.md --active-phase architecture --status in_progress
expect_pass "architecture: approve" "$r" sh $S/sync-feature-state.sh docs/agents-v0/architecture.md --approve architecture --clear-active
G "$r" add -A; G "$r" commit -qm "program: architecture approved"; G "$r" tag -a architecture-v1 -m "architecture approved"

# ---- feature story: intake on main, branch turn commits intake in the worktree -------------------
ORD="docs/agents-v0/requirements/orders.md"; mkdir -p "$r/docs/agents-v0/requirements" "$r/docs/agents-v0/milestones"
printf '# Milestone P1\n\n| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |\n|---|---|---|---|---|---|---|\n| P1-A | As a clerk, I want orders, so that stock is reserved. | docs/agents-v0/requirements/orders.md | planned | — | backend | 3 |\n' > "$r/docs/agents-v0/milestones/p1-core.md"
G "$r" add -A; G "$r" commit -qm "plan fixture"
printf '# Orders\nAs a clerk, I want to place an order, so that stock is reserved.\n\n### AC-1 — place\nKind: happy\n\n### AC-2 — refuse\nKind: negative\n' > "$r/$ORD"
expect_pass "intake: in_progress (nothing approved yet for orders)" "$r" sh $S/sync-feature-state.sh "$ORD" --active-phase intake --status in_progress
expect_pass "intake: approve on main" "$r" sh $S/sync-feature-state.sh "$ORD" --approve intake --clear-active
expect_out "intake: the gate commit is made in the branch turn, with the milestone story id" \
  'Commit the Intake gate in the branch turn, in the new worktree after feature-worktree.sh: git add -A && git commit -m "P1-A: intake approved"'
expect_pass "branch turn: feature-worktree.sh" "$r" sh $S/feature-worktree.sh orders
w="$tmp/portal-orders"
[ -f "$w/$ORD" ] && [ ! -e "$r/$ORD" ] && pass "the untracked intake files moved into the worktree" || fail "intake files did not move"
expect_fail "design in_progress is refused until the intake gate is committed" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase design --status in_progress
expect_out "the refusal prints the intake gate commit" 'git add -A && git commit -m "P1-A: intake approved"'
G "$w" add -A; G "$w" commit -qm "P1-A: intake approved"
expect_pass "design in_progress once the intake gate is committed" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase design --status in_progress

# ---- traceability at the design gate (warn first) ----------------------------------------------
mkdir -p "$w/docs/agents-v0/design/orders"
printf '# Design: orders\n\n## Traceability\n\n| Requirement | Satisfied by |\n|---|---|\n| AC-1 | createOrder |\n| AC-9 | ? |\n' > "$w/docs/agents-v0/design/orders/design.md"
cat > "$w/docs/agents-v0/design/orders/openapi.yaml" <<'YEOF'
openapi: 3.0.3
paths:
  /api/v1/orders:
    post:
      operationId: createOrder
  /api/v1/orders/{id}:
    get:
      operationId: getOrder
YEOF
expect_pass "design: approve (traceability warns, D8)" "$w" sh $S/sync-feature-state.sh "$ORD" --approve design --clear-active
expect_out "T1: AC-2 missing from design.md, blamed on design" 'TRACE WARN T1-design-covers-acs gate=design earliest_bad_phase=design .*AC-2'
expect_out "T3: AC-9 is not a requirement" 'TRACE WARN T3-design-no-unknown-acs .*AC-9'
expect_out "T2: 2 ACs vs plan Size 3, blamed on intake" 'TRACE WARN T2-ac-count-vs-plan gate=design earliest_bad_phase=intake'
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["design"]["earliestBadPhase"]=="intake", d' "$w/docs/agents-v0/requirements/orders.trace.json" \
  && pass "trace.json records the earliest bad phase (intake)" || fail "trace.json earliest bad phase"
expect_out "design: prints the gate commit" 'Next: commit this gate \(one commit, never amend\): git add -A && git commit -m "P1-A: design approved"'
G "$w" add -A; G "$w" commit -qm "P1-A: design approved"
printf '| AC-2 | getOrder |\n' >> "$w/docs/agents-v0/design/orders/design.md"
expect_fail "AGENTS_V0_TRACE_MODE=fail refuses an approval with a failing check" "$w" \
  env AGENTS_V0_TRACE_MODE=fail sh $S/check-traceability.sh design "$ORD"
expect_out "fail mode names the earliest bad phase" 'earliest bad phase: intake'
G "$w" add -A; G "$w" commit -qm "P1-A: design amended (new commit)"

# ---- build: endpoints need code and a test ----------------------------------------------------
expect_pass "build in_progress" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase build --status in_progress
mkdir -p "$w/app/backend/src/main/java/a" "$w/app/backend/src/test/java/a"
printf 'class OrderController { @PostMapping("/api/v1/orders") void createOrder() {} }\n' > "$w/app/backend/src/main/java/a/OrderController.java"
printf 'class OrderControllerTest { void t() { post("/api/v1/orders"); } // AC-1\n}\n' > "$w/app/backend/src/test/java/a/OrderControllerTest.java"
expect_pass "build: approve (warns)" "$w" sh $S/sync-feature-state.sh "$ORD" --approve build --clear-active
expect_out "T4: getOrder has no code" 'TRACE WARN T4-endpoint-has-code gate=build earliest_bad_phase=build .*getOrder'
printf 'class OrderQuery { @GetMapping("/api/v1/orders/{id}") void getOrder() {} }\n' > "$w/app/backend/src/main/java/a/OrderQuery.java"
expect_pass "T5 alone: code without a test" "$w" sh $S/check-traceability.sh build "$ORD"
expect_out "T5: getOrder has no test" 'TRACE WARN T5-endpoint-has-test .*getOrder'
printf 'class OrderQueryTest { void t() { get("/api/v1/orders/42"); } }\n' > "$w/app/backend/src/test/java/a/OrderQueryTest.java"
expect_pass "build checks pass with code and tests for both endpoints" "$w" sh $S/check-traceability.sh build "$ORD"
expect_out "TRACE OK at build" 'TRACE OK gate=build'
G "$w" add -A; G "$w" commit -qm "P1-A: build approved"

# ---- verify: every AC has a passing row ---------------------------------------------------------
expect_pass "verify in_progress" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase verify --status in_progress
mkdir -p "$w/docs/agents-v0/verify/orders"
printf '# Quality gate: orders\nCritical: 0\n\n| AC | Test | Result |\n|---|---|---|\n| AC-1 | OrderControllerTest | PASS |\n| AC-2 | OrderQueryTest | FAIL |\n' > "$w/docs/agents-v0/verify/orders/quality-gate.md"
expect_pass "T6 runs in warn mode" "$w" sh $S/check-traceability.sh verify "$ORD"
expect_out "T6: AC-2 fails, no test names it -> blamed on build" 'TRACE WARN T6-ac-has-passing-test gate=verify earliest_bad_phase=build .*AC-2'
sed -i.bak 's/| AC-2 | OrderQueryTest | FAIL |/| AC-2 | OrderQueryTest | PASS |/' "$w/docs/agents-v0/verify/orders/quality-gate.md"; mv "$w/docs/agents-v0/verify/orders/quality-gate.md.bak" "$tmp/"
expect_pass "verify: approve + verifyPassed" "$w" sh $S/sync-feature-state.sh "$ORD" --approve verify --verify-passed true --clear-active
expect_out "verify: TRACE OK" 'TRACE OK gate=verify'
G "$w" add -A; G "$w" commit -qm "P1-A: verify approved"

# ---- release: commit on the branch, squash into main, one release commit ----------------------
expect_pass "release in_progress in the worktree" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase release --status in_progress
expect_pass "release awaiting approval" "$w" sh $S/sync-feature-state.sh "$ORD" --active-phase release --status awaiting_approval
G "$r" merge -q --squash feature/orders >/dev/null 2>&1 || true
expect_fail "--approve release is refused when the branch's release preparation is not committed" "$r" sh $S/sync-feature-state.sh "$ORD" --approve release
expect_out "the refusal says the release preparation is not committed on the branch" 'release preparation is not committed on the branch'
G "$r" reset -q --hard HEAD   # fixture only: undo the early squash
G "$w" add -A; G "$w" commit -qm "P1-A: release approved"
G "$r" merge -q --squash feature/orders >/dev/null 2>&1 || true
printf 'x\n' > "$w/late.txt"; G "$w" add -A; G "$w" commit -qm "fixture: a branch commit after the squash was staged"
expect_fail "--approve release is refused when the index does not hold the branch tip" "$r" sh $S/sync-feature-state.sh "$ORD" --approve release
expect_out "the refusal asks for git merge --squash" 'run `git merge --squash feature/orders`'
G "$r" merge -q --squash feature/orders >/dev/null 2>&1 || true
expect_pass "--approve release after the squash" "$r" sh $S/sync-feature-state.sh "$ORD" --approve release --clear-active
expect_out "release prints git commit -F with the trailer file" 'Next: commit this gate .*git commit -F .*agents-v0-gate-msg.txt'
msg="$(git -C "$r" rev-parse --git-path agents-v0-gate-msg.txt)"; case "$msg" in /*) ;; *) msg="$r/$msg";; esac
grep -q '^Story-Branch: feature/orders$' "$msg" && grep -Eq "^Story-Tip: $(git -C "$r" rev-parse feature/orders)$" "$msg" \
  && pass "the squash message carries Story-Branch and Story-Tip" || fail "squash message trailers"
printf 'phase: release\nstatus: approved\n' > "$r/docs/agents-v0/requirements/orders.phase-result.md"
G "$r" add -A; G "$r" commit -q -F "$msg"
[ "$(git -C "$r" log -1 --format=%P | wc -w | tr -d ' ')" = 1 ] && pass "the release is one squash commit (one parent)" || fail "release commit is a merge"
expect_pass "check-release-evidence accepts the squash release" "$r" sh $S/check-release-evidence.sh "$ORD"
expect_out "it names the squash commit" 'squash-merged at'
expect_fail "feature-worktree.sh refuses a squash-released branch" "$r" sh $S/feature-worktree.sh orders
expect_out "the refusal says it was squash-merged" 'already squash-merged'
G "$w" commit -q --allow-empty -m "late commit after release"
expect_fail "check-release-evidence fails when the branch moved after the squash" "$r" sh $S/check-release-evidence.sh "$ORD"
expect_out "it lists the commit after the squash" 'late commit after release'
# kitfix-20261031-keep-branches: a deleted story branch only WARNs (the cross-check cannot run); branches are kept
G "$r" branch -m feature/orders keep-orders-ref
expect_pass "check-release-evidence still passes when feature/orders is gone" "$r" sh $S/check-release-evidence.sh "$ORD"
expect_out "but warns that the branch is missing and must be kept" 'WARN: feature/orders not found: the squash/merge cross-check was skipped'
G "$r" branch -m keep-orders-ref feature/orders

# ---- secrets are named, never suggested for a commit ---------------------------------------------
s="$tmp/sec"; mkdir -p "$s/docs/agents-v0/roadmap"; git -C "$s" init -q -b main
cp -R "$r/.agents-v0" "$s/"; printf '# R\n' > "$s/docs/agents-v0/roadmap/r.md"
G "$s" add -A; G "$s" commit -qm base
(cd "$s" && sh $S/sync-feature-state.sh docs/agents-v0/roadmap/r.md --approve roadmap --clear-active >/dev/null 2>&1)
G "$s" add -A; G "$s" commit -qm "program: roadmap approved"
printf 'X=1\n' > "$s/.env"
expect_fail "an untracked .env blocks the next phase" "$s" sh $S/check-gate-commit.sh docs/agents-v0/roadmap/r.md
expect_out "and is named as a secret not to commit" 'look like secrets; never commit them'
expect_pass "AGENTS_V0_SKIP_COMMIT_CHECK=1 skips (fixtures only)" "$s" env AGENTS_V0_SKIP_COMMIT_CHECK=1 sh $S/check-gate-commit.sh docs/agents-v0/roadmap/r.md

[ "$status" -eq 0 ] && echo "test-gate-commit: OK" || { echo "test-gate-commit: FAILED" >&2; exit 1; }
