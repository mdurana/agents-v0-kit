#!/bin/sh
# test-guard-deliver.sh — automated test suite for /v0-deliver phase dispatcher guard (Design: DDL1-DDL8, DDLA).
# Run: sh scripts/test-guard-deliver.sh
set -u
export PYTHONDONTWRITEBYTECODE=1

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-deliver.XXXXXX")"
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
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0/design" "$r/docs/agents-v0/maintain"
git -C "$r" init -q -b main
git -C "$r" config user.name "Test"
git -C "$r" config user.email "test@example.com"
git -C "$r" config commit.gpgsign false

cp "$KIT"/templates/.agents-v0/gate-rules "$r/.agents-v0/gate-rules"
cp "$KIT"/templates/.agents-v0/secret-allowlist.json "$r/.agents-v0/secret-allowlist.json"
cp "$KIT"/templates/docs/agents-v0/design/_design.template.md "$r/docs/agents-v0/design/_design.template.md"
cp "$KIT"/templates/docs/agents-v0/maintain/_note.template.md "$r/docs/agents-v0/maintain/_note.template.md"
cp "$KIT"/templates/docs/agents-v0/lessons.md "$r/docs/agents-v0/lessons.md"
cp "$KIT"/templates/docs/agents-v0/lessons-archive.md "$r/docs/agents-v0/lessons-archive.md"
for s in guard-common.sh guard-onboard.sh guard-intake.sh guard-design.sh guard-build.sh guard-verify.sh \
         guard-local-release.sh guard-maintain.sh guard-deliver.sh \
         secret_scan.py sync-feature-state.sh resolve-integration-branch.sh feature-worktree.sh \
         check-gate-commit.sh check-traceability.sh check-story-dependencies.sh check-attempt-budget.sh \
         check-failure-brief.sh check-tests-ran.sh check-lessons.sh check-release-evidence.sh check-onboarding-docs.sh; do
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

# 1. Slug validation, P0-A block, and tier routing (DDL1)
expect_fail "check: missing slug is refused" "$r" sh .agents-v0/scripts/guard-deliver.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-deliver.sh check Orders-API
expect_fail "check: invalid chars in slug are refused" "$r" sh .agents-v0/scripts/guard-deliver.sh check "orders/api"
expect_fail "check: p0-a slug is refused and routed to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-deliver.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"
expect_fail "check: --tier trivial is refused and routed to /v0-triage" "$r" sh .agents-v0/scripts/guard-deliver.sh check fix-typo --tier trivial
expect_out "check: --tier trivial refusal names /v0-triage" "/v0-triage"
expect_fail "check: --tier emergency without --maintain is refused and routed to /v0-maintain" "$r" sh .agents-v0/scripts/guard-deliver.sh check hotfix-1 --tier emergency
expect_out "check: --tier emergency refusal names /v0-maintain" "/v0-maintain"

# 2. Brownfield onboard prerequisite check (DDL1)
mkdir -p "$r/docs/agents-v0/onboarding"
printf '{"activePhase":"onboard","activeStatus":"in_progress","approvedPhases":[]}\n' > "$r/docs/agents-v0/onboarding/state.json"
expect_fail "check: refuses on brownfield repo when onboard is not approved" "$r" sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: brownfield refusal names /v0-onboard" "/v0-onboard"
rm -rf "$r/docs/agents-v0/onboarding"

# 3. Cross-story collision check (DDL1)
mkdir -p "$r/docs/agents-v0/requirements"
printf '# Other story\n' > "$r/docs/agents-v0/requirements/other-story.md"
expect_fail "check: refuses when another story has uncommitted files" "$r" sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: collision refusal names other-story.md" "other-story.md"
rm -f "$r/docs/agents-v0/requirements/other-story.md"

# 4. Phase 1: Intake via guard-deliver.sh (DDL1, DDL2, DDL3, DDLA)
expect_pass "check: routes new feature 'orders' to intake" "$r" sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: output names phase 'intake'" "routed to phase 'intake'"

expect_pass "start: starts intake for 'orders' and sets deliverGuardManaged" "$r" sh .agents-v0/scripts/guard-deliver.sh start orders
grep -Fq '"activePhase": "intake"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && grep -Fq '"deliverGuardManaged": true' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state has activePhase=intake and deliverGuardManaged=true" \
  || fail "start: missing activePhase=intake or deliverGuardManaged=true"

# Test block and helper-brief SHA-256 deduplication via guard-deliver.sh block (DDL2)
cat > "$r/docs/agents-v0/requirements/orders.helper-brief.md" <<'EOF'
helper: explore-researcher
question: Where is stock reservation implemented?
EOF
expect_pass "block: delegates intake block and records helper-brief hash" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh block orders "Waiting on explore-researcher"
grep -Fq '"activeStatus": "blocked"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "block: sets activeStatus=blocked" || fail "block: activeStatus not blocked"
expect_fail "block: refuses duplicate identical helper-brief" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh block orders "Waiting on explore-researcher again"
expect_out "block: duplicate refusal mentions duplicate helper brief" "duplicate helper brief"
rm -f "$r/docs/agents-v0/requirements/orders.helper-brief.md"

expect_pass "start: resumes intake after block" "$r" sh .agents-v0/scripts/guard-deliver.sh start orders

cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Feature Requirements: orders

As a clerk, I want to place orders, so that stock is reserved.

Surfaces: backend
Vertical slice: no

## Preconditions
- Stock catalog is loaded.

## Desk check
Material: no
- Internal service calculation passes.

## Acceptance criteria

### AC-1 — calculate order total
Kind: happy
Given a signed-in clerk and available SKU-1 stock
When the order service computes the total
Then the total equals unit price times quantity

### AC-2 — reject negative quantity
Kind: negative
Given a signed-in clerk
When the order service receives a negative quantity
Then the request is rejected with IllegalArgumentException

## Out of scope
- Refunds

## Non-functional requirements
- Latency: p95 < 200ms

## Applicable regulations
- GDPR

## Security-review triggers
- Auth / RBAC changes: no

## Open questions
Open questions: none

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
EOF

expect_pass "ready: validates intake requirements and sets awaiting_approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_out "ready: prints approve deliver orders command" "approve deliver orders"

# Verify check and start refuse while awaiting_approval without external approval record (DDL1, DDL2)
expect_fail "check: refuses while intake is awaiting_approval without external approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: refusal names guard-common.sh approve" "guard-common.sh approve"
expect_fail "start: refuses while intake is awaiting_approval without external approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders

# Approve via `guard-common.sh approve deliver orders` in PTY (DDLA)
expect_pass "approve: approve deliver orders resolves intake and writes external record" "$r" \
  pty_approve "$r" deliver orders "Approve intake via deliver alias"
expect_pass "gc_approval_ok: deliver orders verifies external intake approval" "$r" \
  sh -c 'GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_ok deliver orders'

# 5. Seamless Resume (FDL2 / DDL2): `guard-deliver.sh start orders` auto-commits intake, creates worktree, and starts design!
expect_pass "check: detects externally approved intake ready to commit and advance to design" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: mentions intake is approved and ready to commit" "intake for orders is approved and ready to commit"

expect_pass "start: auto-commits intake (provisioning feature/orders worktree) and starts design" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders
expect_out "start: output confirms intake committed and design started" "started phase 'design'"

wt="$tmp/repo-orders"
[ -d "$wt" ] && pass "start: provisioned feature/orders worktree at $wt" || fail "start: missing worktree $wt"
grep -Fq '"activePhase": "design"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: worktree state is activePhase=design" || fail "start: worktree state not design"

# 6. Phase 2: Design with Contract: None auto-advance (FDL6 / DDL3)
cat > "$wt/docs/agents-v0/design/orders/design.md" <<'EOF'
# Design: orders

Contract: None
ADR: N/A: no product decision

## Traceability
| Requirement | Satisfied by | Notes |
|---|---|---|
| AC-1 | OrderCalculator#computeTotal | internal calculation |
| AC-2 | OrderCalculator#computeTotal | rejects negative quantity |

## Data model
No schema changes; in-memory calculation only.

## Authorization
N/A: no /api/v1 operation

## Events
N/A: no event contract

## Failure modes
- AC-2: negative quantity throws IllegalArgumentException.

## Observability
Emit `orders.calculated` metric counter.

## Rollout
No feature flag required.
EOF

expect_pass "ready: Contract: None design is verified and auto-committed by guard-deliver.sh ready" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_out "ready: output confirms Contract: None auto-committed and routes to build" "Contract: None.*proceed directly to build"
git -C "$wt" log -1 --pretty=%B | grep -Fq "design (Contract: None)" \
  && pass "ready: git log on feature/orders has Contract: None commit" \
  || fail "ready: missing Contract: None commit on feature/orders"

# 7. Phase 3: Build via guard-deliver.sh (invoked from main repo, dispatching into worktree!)
expect_pass "start: starts build inside feature/orders worktree after Contract: None design" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders
expect_out "start: output confirms build started" "started phase 'build'"

mkdir -p "$wt/app/backend/src/main/java/com/example" "$wt/app/backend/src/test/java/com/example"
cat > "$wt/app/backend/src/main/java/com/example/OrderCalculator.java" <<'EOF'
package com.example;
public class OrderCalculator {
    public int computeTotal(int price, int qty) {
        if (qty < 0) throw new IllegalArgumentException("negative qty");
        return price * qty;
    }
}
EOF
cat > "$wt/app/backend/src/test/java/com/example/OrderCalculatorTest.java" <<'EOF'
package com.example;
public class OrderCalculatorTest {
    public void testComputeTotal() {}
    public void testRejectNegative() {}
}
EOF
cat > "$wt/docs/agents-v0/build/orders/plan.md" <<'EOF'
# Build Plan: orders

| AC | Status | Test | Risk |
| --- | --- | --- | --- |
| AC-1 | done | OrderCalculatorTest#testComputeTotal | standard |
| AC-2 | done | OrderCalculatorTest#testRejectNegative | standard |
EOF
cat > "$wt/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build Report: orders

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| mvn test | 0 | 1 | - | - |

## Final Verify Summary
- Status: PASS (`./mvnw -B clean verify`)

## Per-Criterion Evidence
- AC-1: `app/backend/src/main/java/com/example/OrderCalculator.java:4`, `app/backend/src/test/java/com/example/OrderCalculatorTest.java:3`
- AC-2: `app/backend/src/main/java/com/example/OrderCalculator.java:5`, `app/backend/src/test/java/com/example/OrderCalculatorTest.java:4`
EOF
printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/build/orders/build-output.txt"

expect_pass "ready: validates build evidence in worktree and sets awaiting_approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_pass "approve: approve deliver orders approves build across worktrees" "$r" \
  pty_approve "$r" deliver orders "Approve build via deliver"
expect_pass "commit: guard-deliver.sh commit orders commits build in worktree" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh commit orders
expect_out "commit: output routes to verify" "next phase is 'verify'"

# 8. Phase 4: Verify with Critical bounce & recovery via guard-deliver.sh (DDL3)
expect_pass "start: starts verify in feature/orders worktree" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders
printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/verify/orders/verify-output.txt"
head_sha="$(git -C "$wt" rev-parse HEAD)"
cat > "$wt/docs/agents-v0/verify/orders/quality-gate.md" <<EOF
commit: $head_sha
agent: test-engineer

# Quality Gate: orders

## Summary
- Build status: PASS
- Changed-line coverage: 90%
- Backend line coverage: 85%
- Frontend line coverage: N/A
- Unsuppressed HIGH/CRITICAL CVEs: 0

## AC Traceability
| AC | Test | Status | Evidence |
| --- | --- | --- | --- |
| AC-1 | OrderCalculatorTest#testComputeTotal | PASS | OrderCalculatorTest.java:3 |
| AC-2 | OrderCalculatorTest#testRejectNegative | PASS | OrderCalculatorTest.java:4 |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
cat > "$wt/docs/agents-v0/verify/orders/vapt-checklist.md" <<EOF
commit: $head_sha
agent: security-reviewer

# VAPT Checklist: orders

| Finding | Control | Status | Evidence | Retest |
| --- | --- | --- | --- | --- |
| F1 | Endpoint RBAC | PASS | OrderCalculator.java:4 | PASS |
| F4 | Access control enforced server-side | PASS | OrderCalculator.java:4 | PASS |
| F8 | Same-role peer {id} access -> 403/404 | PASS | OrderCalculator.java:4 | PASS |
| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PASS | OrderCalculator.java:4 | PASS |
| F10 | Audit events recorded without raw token | PASS | OrderCalculator.java:4 | PASS |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
cat > "$wt/docs/agents-v0/verify/orders/code-review.md" <<EOF
commit: $head_sha
agent: code-reviewer

# Code Review: orders

| ID | Label | Finding | Evidence | Rule Clause | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Critical | Missing overflow check | OrderCalculator.java:6 | java-safety | Open |
EOF

expect_fail "ready: Verify with Open Critical auto-bounces to build via guard-deliver.sh" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_out "ready: bounce output names reopen build" "reopen build|Critical"
grep -Fq '"activePhase": "build"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready bounce: state reopened to build" || fail "ready bounce: state not reopened to build"

# Resolve the Critical finding, re-approve build, and pass verify
rm -rf "$wt/docs/agents-v0/verify/orders"
expect_pass "ready: re-ready build after Critical bounce" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_pass "approve: re-approve build via deliver alias" "$r" \
  pty_approve "$r" deliver orders "Approve build after fix"
expect_pass "start: auto-commits build and starts verify" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders

head_sha="$(git -C "$wt" rev-parse HEAD)"
printf 'BUILD SUCCESS\nTests run: 2, Failures: 0, Errors: 0, Skipped: 0\n' > "$wt/docs/agents-v0/verify/orders/verify-output.txt"
cat > "$wt/docs/agents-v0/verify/orders/quality-gate.md" <<EOF
commit: $head_sha
agent: test-engineer

# Quality Gate: orders

## Summary
- Build status: PASS
- Changed-line coverage: 90%
- Backend line coverage: 85%
- Frontend line coverage: N/A
- Unsuppressed HIGH/CRITICAL CVEs: 0

## AC Traceability
| AC | Test | Status | Evidence |
| --- | --- | --- | --- |
| AC-1 | OrderCalculatorTest#testComputeTotal | PASS | OrderCalculatorTest.java:3 |
| AC-2 | OrderCalculatorTest#testRejectNegative | PASS | OrderCalculatorTest.java:4 |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
cat > "$wt/docs/agents-v0/verify/orders/vapt-checklist.md" <<EOF
commit: $head_sha
agent: security-reviewer

# VAPT Checklist: orders

| Finding | Control | Status | Evidence | Retest |
| --- | --- | --- | --- | --- |
| F1 | Endpoint RBAC | PASS | OrderCalculator.java:4 | PASS |
| F4 | Access control enforced server-side | PASS | OrderCalculator.java:4 | PASS |
| F8 | Same-role peer {id} access -> 403/404 | PASS | OrderCalculator.java:4 | PASS |
| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PASS | OrderCalculator.java:4 | PASS |
| F10 | Audit events recorded without raw token | PASS | OrderCalculator.java:4 | PASS |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
cat > "$wt/docs/agents-v0/verify/orders/code-review.md" <<EOF
commit: $head_sha
agent: code-reviewer

# Code Review: orders

| ID | Label | Finding | Evidence | Rule Clause | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Critical | Missing overflow check | OrderCalculator.java:6 | java-safety | Resolved |
EOF

expect_pass "ready: Verify with 0 Open Critical sets awaiting_approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_pass "approve: approve deliver orders approves verify" "$r" \
  pty_approve "$r" deliver orders "Approve verify via deliver"

# 9. Phase 5: Local-Release via guard-deliver.sh auto-commit on start + final commit (DDL2, DDL5)
expect_pass "start: auto-commits verify and starts local-release in worktree" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start orders
expect_out "start: output confirms local-release started" "started phase 'local-release'"

printf 'BUILD SUCCESS\nTests run: 2, Failures: 0, Errors: 0, Skipped: 0\n' > "$wt/docs/agents-v0/release/orders/release-output.txt"
cat >> "$wt/docs/agents-v0/requirements/orders.phase-result.md" <<'EOF'

## Proposed lessons
- none
EOF

expect_pass "ready: local-release ready sets awaiting_approval" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh ready orders
expect_pass "approve: approve deliver orders approves local-release" "$r" \
  pty_approve "$r" deliver orders "Approve local-release via deliver"
expect_pass "commit: guard-deliver.sh commit orders completes local-release squash-merge" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh commit orders
expect_out "commit: output confirms story delivery is COMPLETE" "COMPLETE"

# Verify re-running check or start on released story refuses
expect_fail "check: refuses when story 'orders' is already released" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh check orders
expect_out "check: refusal states story is already released" "already released"

# 10. --maintain dispatch via guard-deliver.sh (DDL1, DDL2)
expect_pass "check --maintain: routes new maintenance note 'fix-npe' to maintain" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh check fix-npe --maintain
expect_out "check --maintain: output names phase 'maintain'" "routed to phase 'maintain'"
expect_pass "start --maintain: provisions maintain/fix-npe worktree and starts maintain" "$r" \
  sh .agents-v0/scripts/guard-deliver.sh start fix-npe --maintain
mwt="$tmp/repo-maintain-fix-npe"
[ -d "$mwt" ] && pass "start --maintain: provisioned maintain/fix-npe worktree" || fail "start --maintain: missing maintain worktree"
grep -Fq '"deliverGuardManaged": true' "$mwt/docs/agents-v0/maintain/fix-npe/state.json" \
  && pass "start --maintain: records deliverGuardManaged=true in maintain state" \
  || fail "start --maintain: missing deliverGuardManaged=true in maintain state"

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" = 0 ]
