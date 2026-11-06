#!/bin/sh
# test-guard-verify.sh — automated test suite for /v0-verify guard (Design: DV1-DV8, DVA).
# Run: sh scripts/test-guard-verify.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-verify.XXXXXX")"
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
mkdir -p "$r/.agents-v0/scripts" "$r/docs/agents-v0/design"
git -C "$r" init -q -b main
git -C "$r" config user.name "Test"
git -C "$r" config user.email "test@example.com"
git -C "$r" config commit.gpgsign false

cp "$KIT"/templates/.agents-v0/gate-rules "$r/.agents-v0/gate-rules"
cp "$KIT"/templates/.agents-v0/secret-allowlist.json "$r/.agents-v0/secret-allowlist.json"
cp "$KIT"/templates/docs/agents-v0/design/_design.template.md "$r/docs/agents-v0/design/_design.template.md"
for s in guard-common.sh guard-intake.sh guard-design.sh guard-build.sh guard-verify.sh secret_scan.py sync-feature-state.sh \
         resolve-integration-branch.sh feature-worktree.sh check-gate-commit.sh check-traceability.sh \
         check-story-dependencies.sh check-attempt-budget.sh check-failure-brief.sh check-tests-ran.sh; do
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

# 1. Slug validation & P0-A redirect (DV1)
expect_fail "check: missing feature slug is refused" "$r" sh .agents-v0/scripts/guard-verify.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-verify.sh check Orders-API
expect_fail "check: path traversal slug is refused" "$r" sh .agents-v0/scripts/guard-verify.sh check "../orders"
expect_fail "check: p0-a slug is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-verify.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

# 2. Branch & Intake/Design/Build prerequisite checks (DV1)
expect_fail "check: refuses on main when no feature/orders branch exists" "$r" sh .agents-v0/scripts/guard-verify.sh check orders
expect_out "check: refusal names /v0-intake orders" "/v0-intake orders"

# Complete intake for 'orders'
expect_pass "setup: start intake orders" "$r" sh .agents-v0/scripts/guard-intake.sh start orders
cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Feature Requirements: orders

As a clerk, I want to place orders, so that stock is reserved.

Surfaces: backend
Vertical slice: no

## Preconditions
- Stock catalog is loaded.

## Desk check
Material: no
- POST /api/v1/orders returns 201.

## Acceptance criteria

### AC-1 — create order
Kind: happy
Given a signed-in clerk and available SKU-1 stock
When the clerk submits POST /api/v1/orders
Then HTTP 201 is returned with the created order id

### AC-2 — reject invalid order payload
Kind: negative
Given a signed-in clerk
When the clerk submits POST /api/v1/orders with an unknown field
Then the request is rejected with HTTP 400 Bad Request

## Out of scope
- Refunds

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

expect_pass "setup: ready intake orders" "$r" sh .agents-v0/scripts/guard-intake.sh ready orders
expect_pass "setup: approve intake orders via PTY" "$r" pty_approve "$r" intake orders "Approve intake orders"
expect_pass "setup: commit intake orders and create worktree" "$r" sh .agents-v0/scripts/guard-intake.sh commit orders

wt="$tmp/repo-orders"
expect_fail "check: refuses on main when feature/orders worktree exists elsewhere" "$r" sh .agents-v0/scripts/guard-verify.sh check orders
expect_out "check: refusal points to worktree folder" "repo-orders"

expect_fail "check: refuses in worktree when build is not approved" "$wt" sh .agents-v0/scripts/guard-verify.sh check orders
expect_out "check: refusal names /v0-build orders" "/v0-build orders"

# Complete design + build for 'orders' in worktree
expect_pass "setup: start design orders" "$wt" sh .agents-v0/scripts/guard-design.sh start orders
cat > "$wt/docs/agents-v0/design/orders/design.md" <<'EOF'
# Design: orders

ADR: docs/agents-v0/adr/01-orders.md

## Traceability
| Requirement | Satisfied by | Notes |
|---|---|---|
| AC-1 | createOrder | POST /api/v1/orders |
| AC-2 | createOrder | additionalProperties: false |

## Data model
Table `orders` (id UUID PK, clerk_id UUID indexed, sku VARCHAR).

## Authorization
| operationId | Roles or scopes | Resource rule | Notes |
|---|---|---|---|
| createOrder | ROLE_CLERK | caller is authenticated clerk | |

## Events
N/A: no event contract

## Failure modes
- AC-2: invalid payload returns 400 RFC 7807 problem detail.

## Observability
Emit `orders.created` counter and structured audit log.

## Rollout
No feature flag required; additive table migration.
EOF
cat > "$wt/docs/agents-v0/design/orders/openapi.yaml" <<'EOF'
openapi: 3.0.3
info:
  title: Orders API
  version: 1.0.0
paths:
  /api/v1/orders:
    post:
      operationId: createOrder
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              additionalProperties: false
              properties:
                sku:
                  type: string
      responses:
        '201':
          description: Created
EOF
mkdir -p "$wt/docs/agents-v0/adr"
cat > "$wt/docs/agents-v0/adr/01-orders.md" <<'EOF'
# ADR 01: Order Reservation Strategy

Status: Proposed

## Options
### Option 1: Synchronous DB transaction with row lock
### Option 2: Asynchronous reservation queue

## Decision
Use Option 1 (synchronous DB transaction) for simplicity and p95 < 200ms.
EOF
cat > "$wt/docs/agents-v0/design/orders/review.md" <<'EOF'
agent: design-reviewer

| # | Label | Finding | Evidence | Status |
|---|---|---|---|---|
| 1 | Suggestion | Added index on clerk_id | design.md:10 | Resolved |
EOF
expect_pass "setup: ready design orders" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_pass "setup: approve design orders via PTY" "$wt" pty_approve "$wt" design orders "Approve design orders"
expect_pass "setup: commit design orders" "$wt" sh .agents-v0/scripts/guard-design.sh commit orders

expect_pass "setup: start build orders" "$wt" sh .agents-v0/scripts/guard-build.sh start orders
mkdir -p "$wt/openapi" "$wt/app/backend/src/main/java/com/example" "$wt/app/backend/src/test/java/com/example"
cp "$wt/docs/agents-v0/design/orders/openapi.yaml" "$wt/openapi/api-v1.yaml"
cat > "$wt/app/backend/src/main/java/com/example/OrderController.java" <<'EOF'
package com.example;
public class OrderController {
    // POST /api/v1/orders
    public void createOrder() {}
}
EOF
cat > "$wt/app/backend/src/test/java/com/example/OrderControllerTest.java" <<'EOF'
package com.example;
public class OrderControllerTest {
    // Tests createOrder on /api/v1/orders for AC-1 and AC-2
    public void testCreateOrder() {}
}
EOF
cat > "$wt/docs/agents-v0/build/orders/plan.md" <<'EOF'
# Build Plan: orders

| AC | Status | Test | Risk |
| --- | --- | --- | --- |
| AC-1 | done | OrderControllerTest#createOrder | critical |
| AC-2 | done | OrderControllerTest#rejectUnauthenticated | critical |
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
- AC-1: `app/backend/src/main/java/com/example/OrderController.java:25`, `app/backend/src/test/java/com/example/OrderControllerTest.java:42`
- AC-2: `app/backend/src/main/java/com/example/SecurityConfig.java:18`, `app/backend/src/test/java/com/example/OrderControllerTest.java:60`
EOF
printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/build/orders/build-output.txt"
expect_pass "setup: ready build orders" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_pass "setup: approve build orders via PTY" "$wt" pty_approve "$wt" build orders "Approve build orders"
expect_pass "setup: commit build orders" "$wt" sh .agents-v0/scripts/guard-build.sh commit orders

# 3. Check, Start, Block & Helper-brief deduplication (DV1, DV2)
expect_pass "check: passes inside feature/orders worktree after build commit" "$wt" sh .agents-v0/scripts/guard-verify.sh check orders
expect_pass "start: seeds quality-gate.md, vapt-checklist.md, code-review.md and sets in_progress" "$wt" sh .agents-v0/scripts/guard-verify.sh start orders
[ -f "$wt/docs/agents-v0/verify/orders/quality-gate.md" ] && pass "start: seeded quality-gate.md" || fail "start: missing quality-gate.md"
[ -f "$wt/docs/agents-v0/verify/orders/vapt-checklist.md" ] && pass "start: seeded vapt-checklist.md" || fail "start: missing vapt-checklist.md"
[ -f "$wt/docs/agents-v0/verify/orders/code-review.md" ] && pass "start: seeded code-review.md" || fail "start: missing code-review.md"
grep -Fq '"activeStatus": "in_progress"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state is in_progress" || fail "start: state not in_progress"
grep -Fq '"verifyGuardManaged": true' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: sets verifyGuardManaged=true" || fail "start: missing verifyGuardManaged=true"

cat > "$wt/docs/agents-v0/verify/orders/helper-brief.md" <<'EOF'
helper: explore-researcher
ask: Confirm whether OrderController uses @PreAuthorize
EOF
expect_pass "block: first helper brief is recorded and sets blocked" "$wt" \
  sh .agents-v0/scripts/guard-verify.sh block orders "Waiting on explore-researcher"
expect_fail "block: identical repeat helper brief is refused" "$wt" \
  sh .agents-v0/scripts/guard-verify.sh block orders "Waiting on explore-researcher again"
expect_out "block: duplicate brief refusal message" "identical brief"
rm -f "$wt/docs/agents-v0/verify/orders/helper-brief.md"
expect_pass "start: resumes verify after helper brief removed" "$wt" sh .agents-v0/scripts/guard-verify.sh start orders

# 4. Ready deterministic validation (DV3)
expect_fail "ready: refuses when verify-output.txt is missing" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names missing verify-output.txt" "verify-output.txt"

printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/verify/orders/verify-output.txt"

expect_fail "ready: refuses when seeded reports still hold pending placeholders" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names PENDING or TBD placeholders" "PENDING or TBD"

head_sha="$(git -C "$wt" rev-parse HEAD)"

# Write valid VAPT and Code Review, but test quality-gate.md failures first
cat > "$wt/docs/agents-v0/verify/orders/vapt-checklist.md" <<EOF
commit: $head_sha
agent: security-reviewer

# VAPT Checklist: orders

| Finding | Control | Status | Evidence | Retest |
| --- | --- | --- | --- | --- |
| F1 | Endpoint RBAC | PASS | OrderController.java:12 | PASS |
| F4 | Access control enforced server-side | PASS | SecurityConfig.java:20 | PASS |
| F8 | Same-role peer {id} access -> 403/404 | PASS | OrderController.java:18 | PASS |
| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PASS | JwtConfig.java:18 | PASS |
| F10 | Audit events recorded without raw token | PASS | AuditFilter.java:30 | PASS |

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
| 1 | Nit | Add javadoc to createOrder | OrderController.java:5 | java-style | Resolved |
EOF

# Changed-line coverage < 80%
cat > "$wt/docs/agents-v0/verify/orders/quality-gate.md" <<EOF
commit: $head_sha
agent: test-engineer

# Quality Gate: orders

## Summary
- Build status: PASS
- Changed-line coverage: 75%
- Backend line coverage: 85%
- Frontend line coverage: N/A
- Unsuppressed HIGH/CRITICAL CVEs: 0

## AC Traceability
| AC | Test | Status | Evidence |
| --- | --- | --- | --- |
| AC-1 | OrderControllerTest#testCreateOrder | PASS | OrderControllerTest.java:10 |
| AC-2 | OrderControllerTest#testCreateOrder | PASS | OrderControllerTest.java:20 |

## Findings
| ID | Label | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
EOF
expect_fail "ready: refuses when Changed-line coverage < 80%" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names Changed-line coverage threshold" "Changed-line coverage"

# Backend line coverage < 80% without coverage_ratchet
sed -i 's/Changed-line coverage: 75%/Changed-line coverage: 88%/' "$wt/docs/agents-v0/verify/orders/quality-gate.md"
sed -i 's/Backend line coverage: 85%/Backend line coverage: 72%/' "$wt/docs/agents-v0/verify/orders/quality-gate.md"
expect_fail "ready: refuses when Backend line coverage < 80% without coverage_ratchet" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names Backend line coverage threshold" "Backend line coverage"

# Unsuppressed HIGH/CRITICAL CVEs > 0
sed -i 's/Backend line coverage: 72%/Backend line coverage: 85%/' "$wt/docs/agents-v0/verify/orders/quality-gate.md"
sed -i 's/Unsuppressed HIGH\/CRITICAL CVEs: 0/Unsuppressed HIGH\/CRITICAL CVEs: 2/' "$wt/docs/agents-v0/verify/orders/quality-gate.md"
expect_fail "ready: refuses when Unsuppressed HIGH/CRITICAL CVEs > 0" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names unsuppressed HIGH/CRITICAL CVE(s)" "unsuppressed HIGH/CRITICAL CVE"

sed -i 's/Unsuppressed HIGH\/CRITICAL CVEs: 2/Unsuppressed HIGH\/CRITICAL CVEs: 0/' "$wt/docs/agents-v0/verify/orders/quality-gate.md"

# VAPT missing F9 or missing file:line evidence
sed -i '/| F9 |/d' "$wt/docs/agents-v0/verify/orders/vapt-checklist.md"
expect_fail "ready: refuses when VAPT always-on F9 row is missing" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names missing F9 row" "F9"

printf '| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PASS | no-line-ref | PASS |\n' >> "$wt/docs/agents-v0/verify/orders/vapt-checklist.md"
expect_fail "ready: refuses when VAPT PASS row lacks file:line evidence" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready: names file:line evidence requirement" "file:line"

sed -i 's/no-line-ref/JwtConfig.java:18/' "$wt/docs/agents-v0/verify/orders/vapt-checklist.md"

# 5. Automatic Bounce on Critical / FAIL findings (DV3)
cat > "$wt/docs/agents-v0/verify/orders/code-review.md" <<EOF
commit: $head_sha
agent: code-reviewer

# Code Review: orders

| ID | Label | Finding | Evidence | Rule Clause | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Critical | Missing transaction boundary on stock reservation | OrderController.java:15 | tx-rule | Open |
EOF
expect_fail "ready: bounces story back to build when code-review.md has an Open Critical finding" "$wt" \
  sh .agents-v0/scripts/guard-verify.sh ready orders
expect_out "ready bounce: prints automatically reopened build message" "automatically reopened 'build'"
grep -Fq '"lastApprovedPhase": "design"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && grep -Fq '"activePhase": "build"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready bounce: withdrew build from approvedPhases and reopened build" || fail "ready bounce: build still in approvedPhases"
grep -Fq '"verifyPassed": false' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready bounce: set verifyPassed=false" || fail "ready bounce: verifyPassed not false"
grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready bounce: incremented reopenCount to 1" || fail "ready bounce: reopenCount not 1"
grep -Fq "status: changes_requested" "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "ready bounce: wrote status: changes_requested to orders.phase-result.md" || fail "ready bounce: phase-result not changes_requested"

# Restore build state after bounce and re-start verify
git -C "$wt" clean -fd docs/agents-v0/verify/orders >/dev/null 2>&1 || true
git -C "$wt" checkout -- docs/agents-v0/requirements/orders.phase-result.md docs/agents-v0/requirements/orders.state.json
expect_pass "after bounce: start verify orders again" "$wt" sh .agents-v0/scripts/guard-verify.sh start orders
printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/verify/orders/verify-output.txt"
cat > "$wt/docs/agents-v0/verify/orders/quality-gate.md" <<EOF
commit: $head_sha
agent: test-engineer

# Quality Gate: orders

## Summary
- Build status: PASS
- Changed-line coverage: 88%
- Backend line coverage: 85%
- Frontend line coverage: N/A
- Unsuppressed HIGH/CRITICAL CVEs: 0

## AC Traceability
| AC | Test | Status | Evidence |
| --- | --- | --- | --- |
| AC-1 | OrderControllerTest#testCreateOrder | PASS | OrderControllerTest.java:10 |
| AC-2 | OrderControllerTest#testCreateOrder | PASS | OrderControllerTest.java:20 |

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
| F1 | Endpoint RBAC | PASS | OrderController.java:12 | PASS |
| F4 | Access control enforced server-side | PASS | SecurityConfig.java:20 | PASS |
| F8 | Same-role peer {id} access -> 403/404 | PASS | OrderController.java:18 | PASS |
| F9 | JWT alg/iss/aud/exp + fail-closed blacklist | PASS | JwtConfig.java:18 | PASS |
| F10 | Audit events recorded without raw token | PASS | AuditFilter.java:30 | PASS |

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
| 1 | Critical | Missing transaction boundary on stock reservation | OrderController.java:15 | tx-rule | Resolved |
EOF

expect_pass "ready: passes when all 3 reports and T6 traceability are green" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: state is awaiting_approval" || fail "ready: state not awaiting_approval"
grep -Fq '"verifyPassed": true' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: sets verifyPassed=true" || fail "ready: verifyPassed not true"

# 6. Self-approval block (DVA) & External PTY Approval + Commit (DV5)
expect_fail "self-approval blocked: sync-feature-state.sh --approve verify refuses without external approval record" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve verify docs/agents-v0/requirements/orders.md
expect_out "self-approval refusal names guard-common.sh approve verify orders" "guard-common.sh approve verify orders"

expect_fail "commit: refuses before Sensei approves verify" "$wt" sh .agents-v0/scripts/guard-verify.sh commit orders

expect_pass "approve: Sensei approves verify orders via PTY" "$wt" pty_approve "$wt" verify orders "Approve verify orders"
grep -Fq '"lastApprovedPhase": "verify"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "approve: orders.state.json records lastApprovedPhase=verify" || fail "approve: lastApprovedPhase!=verify"

expect_pass "commit: appends Verify row, runs T6 traceability, indexes artifacts, scans secrets, and commits" "$wt" \
  sh .agents-v0/scripts/guard-verify.sh commit orders
expect_out "commit: prints orders: verify approved" "orders: verify approved"

grep -Eq '^\|[[:space:]]*Verify[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt/docs/agents-v0/requirements/orders.md" \
  && pass "commit: appended Approved Verify row to Delivery approvals" || fail "commit: missing Approved Verify row"
grep -Fq "status: approved" "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "commit: updated orders.phase-result.md status to approved" || fail "commit: phase-result not approved"
grep -Fq '"verify":' "$wt/docs/agents-v0/requirements/orders.trace.json" \
  && pass "commit: recorded verify entry in orders.trace.json" || fail "commit: missing verify entry in orders.trace.json"
[ "$(git -C "$wt" log -1 --pretty=%s)" = "orders: verify approved" ] \
  && pass "commit: HEAD commit subject on feature/orders is 'orders: verify approved'" \
  || fail "commit: unexpected commit subject $(git -C "$wt" log -1 --pretty=%s)"

# 7. Reopen flow (--reopen) & Local-Release handoff (DV7)
expect_fail "start without --reopen refuses already-approved verify" "$wt" sh .agents-v0/scripts/guard-verify.sh start orders
expect_pass "check --reopen: allows reopening approved verify" "$wt" sh .agents-v0/scripts/guard-verify.sh check orders --reopen
expect_pass "start --reopen: increments reopenCount, sets verifyPassed=false, and withdraws verify from approvedPhases" "$wt" \
  sh .agents-v0/scripts/guard-verify.sh start orders --reopen
grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start --reopen: reopenCount is 1" || fail "start --reopen: reopenCount not 1"
grep -Fq '"verifyPassed": false' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start --reopen: verifyPassed is false" || fail "start --reopen: verifyPassed not false"

new_sha="$(git -C "$wt" rev-parse HEAD)"
sed -i "s/^commit: .*/commit: $new_sha/" "$wt/docs/agents-v0/verify/orders/quality-gate.md" "$wt/docs/agents-v0/verify/orders/vapt-checklist.md" "$wt/docs/agents-v0/verify/orders/code-review.md"
expect_pass "ready after reopen" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_pass "approve after reopen via PTY" "$wt" pty_approve "$wt" verify orders "Re-approve verify orders"
expect_pass "commit after reopen" "$wt" sh .agents-v0/scripts/guard-verify.sh commit orders

# Release handoff (DV7)
expect_pass "release handoff: sync-feature-state allows release in_progress when external verify approval exists" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress docs/agents-v0/requirements/orders.md

rm -f "$AGENTS_V0_APPROVALS_DIR"/*/verify-orders.json
git -C "$wt" checkout -- docs/agents-v0/requirements/orders.state.json
expect_fail "release handoff: refuses release in_progress when external verify approval record is missing" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress docs/agents-v0/requirements/orders.md
expect_out "release handoff: refusal names external verify approval record" "external verify approval record"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
