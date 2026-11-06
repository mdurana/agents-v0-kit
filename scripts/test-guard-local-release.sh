#!/bin/sh
# test-guard-local-release.sh — automated test suite for /v0-local-release guard (Design: DLR1-DLR8, DLRA).
# Run: sh scripts/test-guard-local-release.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-local-release.XXXXXX")"
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
buf, sent, end = time.time(), False, time.time() + 15
buf = b""
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
cp "$KIT"/templates/docs/agents-v0/lessons.md "$r/docs/agents-v0/lessons.md"
cp "$KIT"/templates/docs/agents-v0/lessons-archive.md "$r/docs/agents-v0/lessons-archive.md"
for s in guard-common.sh guard-intake.sh guard-design.sh guard-build.sh guard-verify.sh guard-local-release.sh \
         secret_scan.py sync-feature-state.sh resolve-integration-branch.sh feature-worktree.sh \
         check-gate-commit.sh check-traceability.sh check-story-dependencies.sh check-attempt-budget.sh \
         check-failure-brief.sh check-tests-ran.sh check-lessons.sh check-release-evidence.sh; do
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

# 1. Slug validation & P0-A redirect (DLR1)
expect_fail "check: missing feature slug is refused" "$r" sh .agents-v0/scripts/guard-local-release.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-local-release.sh check Orders-API
expect_fail "check: path traversal slug is refused" "$r" sh .agents-v0/scripts/guard-local-release.sh check "../orders"
expect_fail "check: p0-a slug is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-local-release.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

# 2. Branch & Intake/Design/Build/Verify prerequisite checks (DLR1)
expect_fail "check: refuses on main when no feature/orders branch exists" "$r" sh .agents-v0/scripts/guard-local-release.sh check orders
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
expect_fail "check: refuses on main when feature/orders worktree exists elsewhere" "$r" sh .agents-v0/scripts/guard-local-release.sh check orders
expect_out "check: refusal points to worktree folder" "repo-orders"

expect_fail "check: refuses in worktree when verify is not approved" "$wt" sh .agents-v0/scripts/guard-local-release.sh check orders
expect_out "check: refusal names /v0-verify orders" "/v0-verify orders"

# Complete design + build + verify for 'orders' in worktree
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

expect_pass "setup: start verify orders" "$wt" sh .agents-v0/scripts/guard-verify.sh start orders
printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/verify/orders/verify-output.txt"
head_sha="$(git -C "$wt" rev-parse HEAD)"
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
| 1 | Nit | Add javadoc to createOrder | OrderController.java:5 | java-style | Resolved |
EOF
expect_pass "setup: ready verify orders" "$wt" sh .agents-v0/scripts/guard-verify.sh ready orders
expect_pass "setup: approve verify orders via PTY" "$wt" pty_approve "$wt" verify orders "Approve verify orders"
expect_pass "setup: commit verify orders" "$wt" sh .agents-v0/scripts/guard-verify.sh commit orders

# 3. Post-Verify non-doc drift bounce (DLR2)
printf '// non-doc drift\n' >> "$wt/app/backend/src/main/java/com/example/OrderController.java"
expect_fail "start: bounces back to /v0-verify when non-doc file changed since verify gate commit" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh start orders
expect_out "start bounce: prints BOUNCED and routes back to /v0-verify orders" "BOUNCED.*v0-verify orders"
grep -Fq '"verifyPassed": false' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start bounce: sets verifyPassed=false" || fail "start bounce: verifyPassed not false"
grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start bounce: increments reopenCount to 1" || fail "start bounce: reopenCount not 1"
grep -Fq '"lastApprovedPhase": "build"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start bounce: withdraws verify from approvedPhases" || fail "start bounce: verify still in approvedPhases"

# Restore clean Verify gate commit state
git -C "$wt" checkout -- app/backend/src/main/java/com/example/OrderController.java \
  docs/agents-v0/requirements/orders.state.json docs/agents-v0/requirements/orders.phase-result.md

# 4. Clean check, start, and block (DLR1, DLR2)
expect_pass "check: passes inside feature/orders worktree after clean verify commit" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh check orders
expect_pass "start: creates docs/agents-v0/release/orders/ and sets activePhase=release, activeStatus=in_progress" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh start orders
[ -d "$wt/docs/agents-v0/release/orders" ] && pass "start: created docs/agents-v0/release/orders/" || fail "start: missing release dir"
grep -Fq '"activePhase": "release"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && grep -Fq '"activeStatus": "in_progress"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state is release / in_progress" || fail "start: state not release / in_progress"
grep -Fq '"releaseGuardManaged": true' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: sets releaseGuardManaged=true" || fail "start: missing releaseGuardManaged=true"

expect_pass "block: sets activeStatus=blocked and blockedReason" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh block orders "Native build failed on integration check"
grep -Fq '"activeStatus": "blocked"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "block: state is blocked" || fail "block: state not blocked"
expect_pass "start: resumes release after block" "$wt" sh .agents-v0/scripts/guard-local-release.sh start orders

# 5. Ready deterministic validation (DLR3)
expect_fail "ready: refuses when release-output.txt is missing" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh ready orders
expect_out "ready: names missing release-output.txt" "release-output.txt"

printf 'BUILD FAILURE\n' > "$wt/docs/agents-v0/release/orders/release-output.txt"
expect_fail "ready: refuses when release-output.txt contains BUILD FAILURE" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh ready orders
expect_out "ready: names failure marker in release-output.txt" "BUILD FAILURE"

printf 'BUILD SUCCESS\nTests run: 4, Failures: 0, Errors: 0, Skipped: 0\n' > "$wt/docs/agents-v0/release/orders/release-output.txt"

# Modify docs/agents-v0/lessons.md on story branch -> ready must refuse
printf '\n<!-- story branch edit -->\n' >> "$wt/docs/agents-v0/lessons.md"
expect_fail "ready: refuses when docs/agents-v0/lessons.md was modified on story branch" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh ready orders
expect_out "ready: names check-lessons.sh unchanged-since failure" "lessons.md"
git -C "$wt" checkout -- docs/agents-v0/lessons.md

# Add a release lesson candidate to orders.phase-result.md
cat >> "$wt/docs/agents-v0/requirements/orders.phase-result.md" <<'EOF'

### release
- Trigger: verify-fail · What happened: Missing Idempotency-Key header in smoke test caused 400 · Do instead: Include Idempotency-Key header in all POST /api/v1/orders requests · Scope: pack:java
EOF

expect_pass "ready: passes with green release-output.txt and normalizes ## Proposed lessons" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh ready orders
grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: state is awaiting_approval" || fail "ready: state not awaiting_approval"
grep -Fq -- "- P-1 · pending · release · Trigger: verify-fail" "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "ready: collected P-1 pending entry into ## Proposed lessons" || fail "ready: missing P-1 pending entry"

# 6. Self-approval block (DLRA) & Two-Step Commit (DLR5)
expect_fail "self-approval blocked: sync-feature-state.sh --approve release refuses without external approval record" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/requirements/orders.md
expect_out "self-approval refusal names guard-common.sh approve local-release orders" "guard-common.sh approve local-release orders"

expect_fail "commit: refuses before Sensei approves local-release" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh commit orders

expect_pass "approve: Sensei approves local-release orders via PTY with lesson decision" "$wt" \
  pty_approve "$wt" local-release orders "Approved, accept P-1"
grep -Fq '"activePhase": "release"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "approve: preserves story-branch activePhase=release and activeStatus=awaiting_approval for two-step commit" \
  || fail "approve: story-branch state was mutated prematurely"

expect_pass "commit: executes Step A on feature/orders and Step B squash-merge on main" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh commit orders
expect_out "commit: prints squash-merge subject" "orders: release approved \\(squash-merge of feature/orders\\)"

# Verify Step A on feature/orders
[ "$(git -C "$wt" log -1 --pretty=%s)" = "orders: release approved" ] \
  && pass "commit Step A: feature/orders HEAD is 'orders: release approved'" \
  || fail "commit Step A: unexpected feature/orders HEAD $(git -C "$wt" log -1 --pretty=%s)"

# Verify Step B on main ($r)
[ "$(git -C "$r" log -1 --pretty=%s)" = "orders: release approved (squash-merge of feature/orders)" ] \
  && pass "commit Step B: main HEAD is 'orders: release approved (squash-merge of feature/orders)'" \
  || fail "commit Step B: unexpected main HEAD $(git -C "$r" log -1 --pretty=%s)"
git -C "$r" log -1 --pretty=%B | grep -Fq "Story-Branch: feature/orders" \
  && git -C "$r" log -1 --pretty=%B | grep -Fq "Story-Tip: $(git -C "$wt" rev-parse HEAD)" \
  && pass "commit Step B: squash commit carries Story-Branch and Story-Tip trailers" \
  || fail "commit Step B: missing Story-Branch / Story-Tip trailers"
grep -Fq '"lastApprovedPhase": "release"' "$r/docs/agents-v0/requirements/orders.state.json" \
  && pass "commit Step B: main orders.state.json records lastApprovedPhase=release" \
  || fail "commit Step B: main orders.state.json missing lastApprovedPhase=release"
grep -Fq -- "- P-1 · accepted · release ·" "$r/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "commit Step B: marked P-1 accepted in main orders.phase-result.md" \
  || fail "commit Step B: P-1 not marked accepted"
grep -Fq "### L-001 · " "$r/docs/agents-v0/lessons.md" \
  && pass "commit Step B: appended L-001 to docs/agents-v0/lessons.md on main" \
  || fail "commit Step B: missing L-001 in docs/agents-v0/lessons.md"
git -C "$r" show-ref --verify --quiet refs/heads/feature/orders \
  && pass "commit Step B: kept feature/orders branch intact" \
  || fail "commit Step B: feature/orders branch was deleted"
expect_pass "commit Step B: check-release-evidence.sh passes on main" "$r" \
  sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/orders.md

# 7. Already-released story check (DLR1) & install.sh stale cleanup (DLR7)
cp "$r/docs/agents-v0/requirements/orders.state.json" "$wt/docs/agents-v0/requirements/orders.state.json"
expect_fail "check: refuses already-released story and suggests /v0-maintain or /v0-intake" "$wt" \
  sh .agents-v0/scripts/guard-local-release.sh check orders
expect_out "check: already-released refusal names /v0-maintain" "/v0-maintain"

inst="$tmp/install-target"
mkdir -p "$inst/.cursor/commands" "$inst/.cursor/skills/release-pr" \
         "$inst/.agents/commands" "$inst/.agents/skills/v0-release" "$inst/.agents/skills/release-pr"
touch "$inst/.cursor/commands/v0-release.md" "$inst/.cursor/skills/release-pr/SKILL.md" \
      "$inst/.agents/commands/v0-release.md" "$inst/.agents/skills/v0-release/SKILL.md" "$inst/.agents/skills/release-pr/SKILL.md"
expect_pass "install.sh: installs cursor + antigravity targets and cleans stale v0-release & release-pr" "$KIT" \
  sh -c '
    sed -e "s|^KIT=.*|KIT=\"$1\"|" -e "s/\[ \"\$hp_uid\" = 0 \]/[ \"\$hp_uid\" = 0 ] || [ \"\$hp_uid\" = 65534 ]/" "$1/scripts/install.sh" > "$2.install.sh"
    sh "$2.install.sh" --pack java "$2"
  ' -- "$KIT" "$inst"
[ ! -e "$inst/.cursor/commands/v0-release.md" ] && [ ! -e "$inst/.cursor/skills/release-pr" ] \
  && [ ! -e "$inst/.agents/commands/v0-release.md" ] && [ ! -e "$inst/.agents/skills/v0-release" ] \
  && [ ! -e "$inst/.agents/skills/release-pr" ] \
  && pass "install.sh: removed stale v0-release and release-pr files across Cursor and Antigravity" \
  || fail "install.sh: stale v0-release or release-pr files remained"
[ -x "$inst/.agents-v0/scripts/guard-local-release.sh" ] \
  && pass "install.sh: installed executable .agents-v0/scripts/guard-local-release.sh" \
  || fail "install.sh: missing executable guard-local-release.sh"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
