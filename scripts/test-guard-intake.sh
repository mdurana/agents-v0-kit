#!/bin/sh
# test-guard-intake.sh — automated test suite for /v0-intake guard (Design: DI1-DI8, DIA).
# Run: sh scripts/test-guard-intake.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-intake.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

passed=0
failed=0
pass() { passed=$((passed + 1)); printf 'PASS %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf 'FAIL %s\n' "$1" >&2; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /' >&2; }

expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if out="$(cd "$dir" && "$@" 2>&1)"; then
    pass "$desc"
  else
    fail "$desc (expected exit 0)" "$out"
  fi
}

expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if out="$(cd "$dir" && "$@" 2>&1)"; then
    fail "$desc (expected non-zero)" "$out"
  else
    pass "$desc"
  fi
}

expect_out() {
  desc="$1"; pat="$2"
  if printf '%s\n' "$out" | grep -Eq "$pat"; then
    pass "$desc"
  else
    fail "$desc (missing pattern: $pat)" "$out"
  fi
}

pty_approve() {
  repo_dir="$1"
  phase_cmd="$2"
  feature_arg="${3:-}"
  words="${4:-Approved by Sensei}"
  python3 - "$repo_dir" "$phase_cmd" "$feature_arg" "$words" <<'PY'
import os, pty, sys, time
repo, phase, feature, words = sys.argv[1:5]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(repo)
    argv = ["sh", ".agents-v0/scripts/guard-common.sh", "approve", phase]
    if feature:
        argv.append(feature)
    os.execvp("sh", argv)
buf, sent, end = b"", False, time.time() + 15
while time.time() < end:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    if not sent and b"Type your approval words" in buf:
        os.write(fd, words.encode("utf-8") + b"\r")
        sent = True
try:
    os.close(fd)
except OSError:
    pass
_, status = os.waitpid(pid, 0)
sys.stdout.write(buf.decode("utf-8", "replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

export AGENTS_V0_APPROVALS_DIR="$tmp/approvals"
mkdir -p "$AGENTS_V0_APPROVALS_DIR"

r="$tmp/repo"
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0/milestones"
git -C "$r" init -q -b main
git -C "$r" config user.name "Test"
git -C "$r" config user.email "test@example.com"
git -C "$r" config commit.gpgsign false

cp "$KIT"/templates/.agents-v0/gate-rules "$r/.agents-v0/gate-rules"
cp "$KIT"/templates/.agents-v0/secret-allowlist.json "$r/.agents-v0/secret-allowlist.json"
for s in guard-common.sh guard-intake.sh guard-plan.sh guard-scaffold.sh secret_scan.py sync-feature-state.sh \
         resolve-integration-branch.sh feature-worktree.sh check-gate-commit.sh check-traceability.sh; do
  cp "$KIT/templates/.agents-v0/scripts/$s" "$r/.agents-v0/scripts/$s"
  chmod +x "$r/.agents-v0/scripts/$s"
done

cat > "$r/docs/agents-v0/project-profile.md" <<'EOF'
# Project Profile
## Stack
| Field | Value |
|---|---|
| Pack | java |
EOF
git -C "$r" add -A
git -C "$r" commit -qm "initial base"

# 1. Slug validation & P0-A redirection (DI1, Jiraiya Rec 1)
expect_fail "check: missing feature slug is refused" "$r" sh .agents-v0/scripts/guard-intake.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-intake.sh check Orders-API
expect_fail "check: path traversal slug is refused" "$r" sh .agents-v0/scripts/guard-intake.sh check "../orders"
expect_fail "check: p0-a slug is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-intake.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

# 2. Change-tier routing (DI1, FI6)
expect_fail "check: --tier trivial is refused and routed to /v0-triage" "$r" sh .agents-v0/scripts/guard-intake.sh check orders --tier trivial
expect_out "check: trivial tier names /v0-triage" "/v0-triage"
expect_fail "check: --tier emergency is refused and routed to /v0-maintain" "$r" sh .agents-v0/scripts/guard-intake.sh check orders --tier emergency
expect_out "check: emergency tier names /v0-maintain" "/v0-maintain"
[ ! -e "$r/docs/agents-v0/requirements/orders.md" ] && pass "check: tier routing creates no files on disk" || fail "check: tier routing created files"

# 3. Integration branch check (DI1)
git -C "$r" checkout -qb other-branch
expect_fail "check: refuses on non-integration branch" "$r" sh .agents-v0/scripts/guard-intake.sh check orders
expect_out "check: branch refusal names integration branch main" "integration branch \(main\)"
git -C "$r" checkout -q main

# 4. Upstream program / plan / scaffold prerequisite checks (DI1, FI5)
cat > "$r/docs/agents-v0/milestones/plan.md" <<'EOF'
# Plan
EOF
cat > "$r/docs/agents-v0/milestones/p0-platform-skeleton.md" <<'EOF'
# Milestone P0
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P0-A | As a developer, I want a skeleton, so that we can build. | docs/agents-v0/milestones/p0-platform-skeleton.md | released | — | vertical slice | 4 |
EOF
cat > "$r/docs/agents-v0/milestones/p1-core.md" <<'EOF'
# Milestone P1
| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|---|---|---|---|---|---|---|
| P1-A | As a clerk, I want to place an order, so that stock is reserved. | docs/agents-v0/requirements/orders.md | planned | P0-A | backend | 2 |
EOF
git -C "$r" add -A && git -C "$r" commit -qm "add milestone files"

expect_fail "check: refuses when plan.md exists but plan is not approved" "$r" sh .agents-v0/scripts/guard-intake.sh check orders
expect_out "check: refusal names /v0-plan" "/v0-plan"

# Approve plan and scaffold via guard-common.sh + PTY
(cd "$r" && GC_HERE="$r/.agents-v0/scripts" GUARD_COMMON_LIB=1 . "$r/.agents-v0/scripts/guard-common.sh" && \
  gc_state_set docs/agents-v0/program.state.json program docs/agents-v0/milestones/plan.md \
    "approvePhase=roadmap" "approvePhase=architecture" "activePhase=plan" "activeStatus=awaiting_approval")
expect_pass "setup: Sensei approves plan via PTY" "$r" pty_approve "$r" plan "" "Approve plan"

expect_fail "check: refuses greenfield when p0-platform-skeleton.md exists but scaffold is not approved" "$r" sh .agents-v0/scripts/guard-intake.sh check orders
expect_out "check: refusal names /v0-scaffold" "/v0-scaffold"

(cd "$r" && GC_HERE="$r/.agents-v0/scripts" GUARD_COMMON_LIB=1 . "$r/.agents-v0/scripts/guard-common.sh" && \
  gc_state_set docs/agents-v0/program.state.json program docs/agents-v0/milestones/p0-platform-skeleton.md \
    "activePhase=scaffold" "activeStatus=awaiting_approval")
expect_pass "setup: Sensei approves scaffold via PTY" "$r" pty_approve "$r" scaffold "" "Approve scaffold"
git -C "$r" add docs/agents-v0/program.state.json && git -C "$r" commit -qm "program: plan and scaffold approved"

expect_pass "check: passes once plan and scaffold are approved on main" "$r" sh .agents-v0/scripts/guard-intake.sh check orders --tier standard

# 5. Start & Block & Helper-brief deduplication (DI2, FI6)
expect_pass "start: seeds orders.md and sets in_progress" "$r" sh .agents-v0/scripts/guard-intake.sh start orders
[ -f "$r/docs/agents-v0/requirements/orders.md" ] && pass "start: created orders.md skeleton" || fail "start: missing orders.md"
grep -Fq '"activeStatus": "in_progress"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state is in_progress" || fail "start: state not in_progress"

cat > "$r/docs/agents-v0/requirements/orders.helper-brief.md" <<'EOF'
helper: explore-researcher
ask: What is the order table schema?
EOF
expect_pass "block: first helper brief is recorded and sets blocked" "$r" \
  sh .agents-v0/scripts/guard-intake.sh block orders "Waiting on explore-researcher"
expect_fail "block: identical repeat helper brief is refused" "$r" \
  sh .agents-v0/scripts/guard-intake.sh block orders "Waiting on explore-researcher again"
expect_out "block: duplicate brief refusal message" "duplicate helper brief"
rm -f "$r/docs/agents-v0/requirements/orders.helper-brief.md"
expect_pass "start: resumes intake after helper brief removed" "$r" sh .agents-v0/scripts/guard-intake.sh start orders

# 6. Ready deterministic validation (DI3, FI3)
expect_fail "ready: refuses unauthored skeleton with <...> placeholders" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_out "ready: names unresolved placeholders" "unresolved placeholders"

cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Feature Requirements: orders

Story: P1-A
As a clerk, I want to place an order, so that stock is reserved.

Surfaces: backend, frontend
Vertical slice: no

## Preconditions
- Stock catalog is loaded.

## Desk check
Material: no
- POST /api/v1/orders returns 201.

## Acceptance criteria

### AC-1 — place order
Kind: happy
Given a valid clerk session
When the clerk submits an order
Then it works as expected

## Out of scope
- Refunds

## Non-functional requirements
- p95 < 200ms

## Applicable regulations
- GDPR

## Security-review triggers
- Auth / RBAC changes: yes

## Open questions
Open questions: none

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
EOF

expect_fail "ready: refuses multiple surfaces without Vertical slice: yes" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_out "ready: names multiple surfaces" "multiple surfaces"

sed -i 's/^Surfaces: backend, frontend$/Surfaces: backend/' "$r/docs/agents-v0/requirements/orders.md"
expect_fail "ready: refuses vague Then clause ('works as expected')" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_out "ready: names vague Then clause" "vague Then clause"

sed -i 's/Then it works as expected/Then HTTP 201 is returned and the order row is persisted/' "$r/docs/agents-v0/requirements/orders.md"
expect_fail "ready: refuses active security trigger without a refusing Kind: negative AC" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_out "ready: names refusing Kind: negative requirement" "active security-review triggers"

cat >> "$r/docs/agents-v0/requirements/orders.md" <<'EOF'

## Proposed split
| Story | Surface |
|---|---|
EOF
expect_fail "ready: refuses story with ## Proposed split" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_out "ready: directs Proposed split to guard-intake.sh block" "Proposed split"

# Write a clean, complete requirements artifact with AC-1 (happy) and AC-2 (negative refusal)
cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Feature Requirements: orders

Story: P1-A
As a clerk, I want to place an order, so that stock is reserved.

Surfaces: backend
Vertical slice: no

## Preconditions

- Stock catalog is loaded with SKU-1.

## Desk check

Material: no
- POST /api/v1/orders with SKU-1 returns HTTP 201.

## Acceptance criteria

### AC-1 — place valid order
Kind: happy
Given a signed-in clerk and available SKU-1 stock
When the clerk submits POST /api/v1/orders for SKU-1
Then HTTP 201 is returned and the order is saved with status RESERVED

### AC-2 — reject unauthenticated order request
Kind: negative
Given an unauthenticated caller
When the caller submits POST /api/v1/orders
Then the request is rejected with HTTP 401 Unauthorized

## Out of scope

- Payment settlement

## Non-functional requirements

- Latency: p95 < 200ms

## Applicable regulations

- GDPR

## Security-review triggers

- Auth / RBAC changes: yes

## Open questions

Open questions: none

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
EOF

expect_pass "ready: passes on valid requirements artifact and writes phase-result" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
[ -f "$r/docs/agents-v0/requirements/orders.phase-result.md" ] && pass "ready: wrote orders.phase-result.md" || fail "ready: missing orders.phase-result.md"
grep -Fq '"activeStatus": "awaiting_approval"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: state is awaiting_approval" || fail "ready: state not awaiting_approval"

# 7. Self-approval defense & Parameterized External Approval (DIA, FI1)
expect_fail "self-approval blocked: sync-feature-state.sh --approve intake refuses without external approval record" "$r" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve intake docs/agents-v0/requirements/orders.md
expect_out "self-approval refusal names guard-common.sh approve intake orders" "guard-common.sh approve intake orders"

expect_fail "commit: refuses before Sensei approves" "$r" sh .agents-v0/scripts/guard-intake.sh commit orders
expect_fail "approve: refuses intake without <feature> argument" "$r" pty_approve "$r" intake "" "Approve intake"

expect_pass "approve: Sensei approves intake orders via PTY" "$r" pty_approve "$r" intake orders "LGTM orders intake"
grep -Fq '"lastApprovedPhase": "intake"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "approve: orders.state.json records lastApprovedPhase=intake" || fail "approve: lastApprovedPhase!=intake"

# 8. Commit with worktree handoff, explicit staging, and secret scan (DI5, FI2)
expect_pass "commit: creates feature/orders worktree, relocates files, stages 3 paths, scans secrets, and commits" "$r" \
  sh .agents-v0/scripts/guard-intake.sh commit orders
expect_out "commit: prints P1-A: intake approved commit on feature/orders" 'P1-A: intake approved'

wt="$tmp/repo-orders"
[ -d "$wt" ] && pass "commit: created worktree ../repo-orders" || fail "commit: worktree ../repo-orders missing"
[ ! -e "$r/docs/agents-v0/requirements/orders.md" ] && pass "commit: untracked intake files moved out of main checkout" || fail "commit: orders.md still on main"
[ -f "$wt/docs/agents-v0/requirements/orders.md" ] && pass "commit: orders.md is in feature/orders worktree" || fail "commit: orders.md missing in worktree"
grep -Eq '\|[[:space:]]*Intake[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt/docs/agents-v0/requirements/orders.md" \
  && pass "commit: appended Approved Intake row to Delivery approvals" || fail "commit: missing Approved Intake row"
grep -Fq -- '- status: approved' "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "commit: updated orders.phase-result.md status to approved" || fail "commit: phase-result status not approved"
[ "$(git -C "$wt" log -1 --format=%s)" = "P1-A: intake approved" ] \
  && pass "commit: HEAD commit subject on feature/orders is 'P1-A: intake approved'" || fail "commit: unexpected commit subject"

# 9. /v0-design handoff check (DI7, FI8)
expect_pass "design handoff: sync-feature-state allows design in_progress in feature/orders worktree" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase design --status in_progress

# Reset activePhase and test that removing the external approval record blocks design entry
(cd "$wt" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --clear-active >/dev/null)
git -C "$wt" checkout -q -- docs/agents-v0/requirements/orders.state.json
rec_file="$(find "$AGENTS_V0_APPROVALS_DIR" -name 'intake-orders.json' | head -n 1)"
mv "$rec_file" "${rec_file}.bak"
expect_fail "design handoff: refuses design in_progress when external intake approval record is missing" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase design --status in_progress
expect_out "design handoff: refusal names external intake approval record" "external intake approval record"
mv "${rec_file}.bak" "$rec_file"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
