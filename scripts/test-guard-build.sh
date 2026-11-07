#!/bin/sh
# test-guard-build.sh — automated test suite for /v0-build guard (Design: DB1-DB8, DBA).
# Run: sh scripts/test-guard-build.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-build.XXXXXX")"
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
  words="${4:-Approved by user}"
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
for s in guard-common.sh guard-intake.sh guard-design.sh guard-build.sh secret_scan.py sync-feature-state.sh \
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

# 1. Slug validation & P0-A redirect (DB1)
expect_fail "check: missing feature slug is refused" "$r" sh .agents-v0/scripts/guard-build.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-build.sh check Orders-API
expect_fail "check: path traversal slug is refused" "$r" sh .agents-v0/scripts/guard-build.sh check "../orders"
expect_fail "check: p0-a slug is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-build.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

# 2. Branch & Intake/Design prerequisite checks (DB1)
expect_fail "check: refuses on main when no feature/orders branch exists" "$r" sh .agents-v0/scripts/guard-build.sh check orders
expect_out "check: refusal names /v0-intake orders" "/v0-intake orders"

# Complete intake for 'orders' via guard-intake.sh + PTY
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
expect_fail "check: refuses on main when feature/orders worktree exists elsewhere" "$r" sh .agents-v0/scripts/guard-build.sh check orders
expect_out "check: refusal points to worktree folder" "repo-orders"

expect_fail "check: refuses in worktree when design is not approved" "$wt" sh .agents-v0/scripts/guard-build.sh check orders
expect_out "check: refusal names /v0-design orders" "/v0-design orders"

# Complete design for 'orders' in worktree
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

# 3. Check, Start, Block & Helper-brief deduplication (DB1, DB2)
expect_pass "check: passes inside feature/orders worktree after design commit" "$wt" sh .agents-v0/scripts/guard-build.sh check orders
expect_pass "start: seeds plan.md and build-report.md and sets in_progress" "$wt" sh .agents-v0/scripts/guard-build.sh start orders
[ -f "$wt/docs/agents-v0/build/orders/plan.md" ] && pass "start: seeded docs/agents-v0/build/orders/plan.md" || fail "start: missing plan.md"
[ -f "$wt/docs/agents-v0/build/orders/build-report.md" ] && pass "start: seeded docs/agents-v0/build/orders/build-report.md" || fail "start: missing build-report.md"
grep -Fq '"activeStatus": "in_progress"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state is in_progress" || fail "start: state not in_progress"
grep -Fq '"buildGuardManaged": true' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: sets buildGuardManaged=true" || fail "start: missing buildGuardManaged=true"

cat > "$wt/docs/agents-v0/build/orders/helper-brief.md" <<'EOF'
helper: schema-author
ask: Clarify sku field length
EOF
expect_pass "block: first helper brief is recorded and sets blocked" "$wt" \
  sh .agents-v0/scripts/guard-build.sh block orders "Waiting on schema-author"
expect_fail "block: identical repeat helper brief is refused" "$wt" \
  sh .agents-v0/scripts/guard-build.sh block orders "Waiting on schema-author again"
expect_out "block: duplicate brief refusal message" "identical brief"
rm -f "$wt/docs/agents-v0/build/orders/helper-brief.md"
expect_pass "start: resumes build after helper brief removed" "$wt" sh .agents-v0/scripts/guard-build.sh start orders

# 4. Ready deterministic validation (DB3)
expect_fail "ready: refuses when build-output.txt is missing" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names missing build-output.txt" "build-output.txt"

printf 'BUILD SUCCESS\n' > "$wt/docs/agents-v0/build/orders/build-output.txt"

expect_fail "ready: refuses when plan.md rows are still pending" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names pending AC row in plan.md" "Status 'pending'"

# Attempt budget check (8 failed attempts)
cat > "$wt/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build Report: orders

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| mvn test | 1 | 1 | T1 | OrderTest.java:10 |
| mvn test | 1 | 2 | T2 | OrderTest.java:10 |
| mvn test | 1 | 3 | T3 | OrderTest.java:10 |
| mvn test | 1 | 4 | T4 | OrderTest.java:10 |
| mvn test | 1 | 5 | T5 | OrderTest.java:10 |
| mvn test | 1 | 6 | T6 | OrderTest.java:10 |
| mvn test | 1 | 7 | T7 | OrderTest.java:10 |
| mvn test | 1 | 8 | T8 | OrderTest.java:10 |
EOF
expect_fail "ready: refuses when attempt budget (8 failed attempts) is spent" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names attempt budget spent" "attempt budget spent"

# 2nd red for same test without failure-brief.md
cat > "$wt/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build Report: orders

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| mvn test | 1 | 1 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
| mvn test | 1 | 2 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
EOF
expect_fail "ready: refuses on 2nd red for same test without failure-brief.md" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names missing failure-brief.md" "failure-brief.md missing"

# 3rd failure for same test even with failure-brief.md
cat > "$wt/docs/agents-v0/build/orders/failure-brief.md" <<'EOF'
helper: debug-investigator
outputs: docs/agents-v0/build/orders/failure-brief.md
return: root cause and minimal fix
ask: Why does OrderControllerTest#createOrder fail at OrderControllerTest.java:42?
EOF
cat > "$wt/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build Report: orders

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| mvn test | 1 | 1 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
| mvn test | 1 | 2 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
| mvn test | 1 | 3 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
EOF
expect_fail "ready: refuses when same test fails 3 times (3rd red cap)" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names third failure cap exceeded" "third failure cap exceeded"

# Plan done, but openapi.yaml not merged into repo openapi/ catalog
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
| mvn test | 1 | 1 | OrderControllerTest#createOrder | OrderControllerTest.java:42 |
| mvn test | 0 | 2 | - | - |

## Final Verify Summary
- Status: PASS (`./mvnw -B clean verify`)

## Per-Criterion Evidence
- AC-1: `app/backend/src/main/java/com/example/OrderController.java:25`, `app/backend/src/test/java/com/example/OrderControllerTest.java:42`
- AC-2: `app/backend/src/main/java/com/example/SecurityConfig.java:18`, `app/backend/src/test/java/com/example/OrderControllerTest.java:60`
EOF
expect_fail "ready: refuses when openapi.yaml is not merged into repo openapi/ catalog" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names missing openapi/ catalog merge" "openapi/"

mkdir -p "$wt/openapi"
cp "$wt/docs/agents-v0/design/orders/openapi.yaml" "$wt/openapi/api-v1.yaml"

# T4/T5 traceability check (no code under app/ yet)
expect_fail "ready: refuses when T4/T5 traceability fails (no code under app/)" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names T4-endpoint-has-code" "T4-endpoint-has-code"

mkdir -p "$wt/app/backend/src/main/java/com/example" "$wt/app/backend/src/test/java/com/example"
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

# Missing per-AC file:line citation in build-report.md
sed -i '/AC-2:/d' "$wt/docs/agents-v0/build/orders/build-report.md"
expect_fail "ready: refuses when build-report.md is missing AC-2 file:line citation" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_out "ready: names missing AC-2 citation" "AC-2"

printf -- '- AC-2: app/backend/src/main/java/com/example/SecurityConfig.java:18\n' >> "$wt/docs/agents-v0/build/orders/build-report.md"

# Ready passes when all checks succeed
expect_pass "ready: passes when plan, budget, catalog, T4/T5 traceability, and evidence are valid" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: state is awaiting_approval" || fail "ready: state not awaiting_approval"

# 5. Self-approval block (DBA) & External PTY Approval + Commit (DB5)
expect_fail "self-approval blocked: sync-feature-state.sh --approve build refuses without external approval record" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve build docs/agents-v0/requirements/orders.md
expect_out "self-approval refusal names guard-common.sh approve build orders" "guard-common.sh approve build orders"

expect_fail "commit: refuses before the user approves build" "$wt" sh .agents-v0/scripts/guard-build.sh commit orders

expect_pass "approve: the user approves build orders via PTY" "$wt" pty_approve "$wt" build orders "Approve build orders"
grep -Fq '"lastApprovedPhase": "build"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "approve: orders.state.json records lastApprovedPhase=build" || fail "approve: lastApprovedPhase!=build"

expect_pass "commit: appends Build row, runs traceability, indexes artifacts, scans secrets, and commits" "$wt" \
  sh .agents-v0/scripts/guard-build.sh commit orders
expect_out "commit: prints orders: build approved" "orders: build approved"

grep -Eq '^\|[[:space:]]*Build[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt/docs/agents-v0/requirements/orders.md" \
  && pass "commit: appended Approved Build row to Delivery approvals" || fail "commit: missing Approved Build row"
grep -Fq "status: approved" "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "commit: updated orders.phase-result.md status to approved" || fail "commit: phase-result not approved"
grep -Fq '"build":' "$wt/docs/agents-v0/requirements/orders.trace.json" \
  && pass "commit: recorded build entry in orders.trace.json" || fail "commit: missing build entry in orders.trace.json"
[ "$(git -C "$wt" log -1 --pretty=%s)" = "orders: build approved" ] \
  && pass "commit: HEAD commit subject on feature/orders is 'orders: build approved'" \
  || fail "commit: unexpected commit subject $(git -C "$wt" log -1 --pretty=%s)"

# 6. Reopen flow (--reopen) & Verify handoff (DB7)
expect_fail "start without --reopen refuses already-approved build" "$wt" sh .agents-v0/scripts/guard-build.sh start orders
expect_pass "check --reopen: allows reopening approved build" "$wt" sh .agents-v0/scripts/guard-build.sh check orders --reopen
expect_pass "start --reopen: increments reopenCount and withdraws build from approvedPhases" "$wt" sh .agents-v0/scripts/guard-build.sh start orders --reopen
grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start --reopen: reopenCount is 1" || fail "start --reopen: reopenCount not 1"

printf '// reopened build comment\n' >> "$wt/app/backend/src/main/java/com/example/OrderController.java"
expect_pass "ready after reopen" "$wt" sh .agents-v0/scripts/guard-build.sh ready orders
expect_pass "approve after reopen via PTY" "$wt" pty_approve "$wt" build orders "Re-approve build orders"
expect_pass "commit after reopen" "$wt" sh .agents-v0/scripts/guard-build.sh commit orders

# Verify handoff (DB7)
expect_pass "verify handoff: sync-feature-state allows verify in_progress when external build approval exists" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status in_progress docs/agents-v0/requirements/orders.md

rm -f "$AGENTS_V0_APPROVALS_DIR"/*/build-orders.json
git -C "$wt" checkout -- docs/agents-v0/requirements/orders.state.json
expect_fail "verify handoff: refuses verify in_progress when external build approval record is missing" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status in_progress docs/agents-v0/requirements/orders.md
expect_out "verify handoff: refusal names external build approval record" "external build approval record"

# Restore external approval record for orders
pty_approve "$wt" build orders "Restore build approval" >/dev/null 2>&1 || true
git -C "$wt" checkout -- docs/agents-v0/requirements/orders.state.json

# 7. Contract: None shortcut story through Build (Design backfill check)
expect_pass "setup: start intake cleanup-job on main" "$r" sh .agents-v0/scripts/guard-intake.sh start cleanup-job
cat > "$r/docs/agents-v0/requirements/cleanup-job.md" <<'EOF'
# Feature Requirements: cleanup-job

As an operator, I want stale temp files purged nightly, so that disk usage stays bounded.

Surfaces: backend
Vertical slice: no

## Preconditions
- Temp directory exists.

## Desk check
Material: no
- Internal cron purges files older than 24h.

## Acceptance criteria

### AC-1 — purge old temp files
Kind: happy
Given temp files older than 24h
When the nightly purge job runs
Then files older than 24h are deleted and count is logged

### AC-2 — skip locked temp files
Kind: negative
Given a temp file with an active lock
When the nightly purge job runs
Then the locked file is skipped and an error metric is incremented

## Out of scope
- Archiving to S3

## Non-functional requirements
- Runs in < 5s

## Applicable regulations
- none

## Security-review triggers
- none

## Open questions
Open questions: none

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
EOF
expect_pass "setup: ready intake cleanup-job" "$r" sh .agents-v0/scripts/guard-intake.sh ready cleanup-job
expect_pass "setup: approve intake cleanup-job" "$r" pty_approve "$r" intake cleanup-job "Approve intake cleanup-job"
expect_pass "setup: commit intake cleanup-job" "$r" sh .agents-v0/scripts/guard-intake.sh commit cleanup-job

wt_cn="$tmp/repo-cleanup-job"
expect_pass "contract-none: start design cleanup-job" "$wt_cn" sh .agents-v0/scripts/guard-design.sh start cleanup-job
cat > "$wt_cn/docs/agents-v0/design/cleanup-job/design.md" <<'EOF'
# Design: cleanup-job

ADR: N/A: no product decision

## Traceability
| Requirement | Satisfied by | Notes |
|---|---|---|
| AC-1 | TempPurgeJob | internal scheduled task |
| AC-2 | TempPurgeJob | lock check |

## Data model
No schema changes.

## Authorization
Internal cron job only; N/A: no /api/v1 operation.

## Events
N/A: no event contract

## Failure modes
- AC-2: locked file is skipped and increments `cleanup.skipped` counter.

## Observability
 Structured log on completion.

## Rollout
Enabled by default.
EOF
expect_pass "contract-none: ready design cleanup-job" "$wt_cn" sh .agents-v0/scripts/guard-design.sh ready cleanup-job
expect_pass "contract-none: commit design cleanup-job" "$wt_cn" sh .agents-v0/scripts/guard-design.sh commit cleanup-job

expect_pass "contract-none: guard-build check passes without external design approval" "$wt_cn" sh .agents-v0/scripts/guard-build.sh check cleanup-job
expect_pass "contract-none: guard-build start passes" "$wt_cn" sh .agents-v0/scripts/guard-build.sh start cleanup-job
cat > "$wt_cn/docs/agents-v0/build/cleanup-job/plan.md" <<'EOF'
# Build Plan: cleanup-job

| AC | Status | Test | Risk |
| --- | --- | --- | --- |
| AC-1 | done | CleanupJobTest#purgesOldFiles | standard |
| AC-2 | done | CleanupJobTest#skipsLockedFiles | standard |
EOF
cat > "$wt_cn/docs/agents-v0/build/cleanup-job/build-report.md" <<'EOF'
# Build Report: cleanup-job

## Attempt Cards
| Command | Exit | Attempt | Failing test | Location |
| --- | --- | --- | --- | --- |
| mvn test | 1 | 1 | CleanupJobTest#purgesOldFiles | CleanupJobTest.java:15 |
| mvn test | 0 | 2 | - | - |

## Final Verify Summary
- Status: PASS

## Per-Criterion Evidence
- AC-1: `app/backend/src/main/java/com/example/CleanupJob.java:12`
- AC-2: `app/backend/src/main/java/com/example/CleanupJob.java:18`
EOF
printf 'BUILD SUCCESS\n' > "$wt_cn/docs/agents-v0/build/cleanup-job/build-output.txt"
expect_pass "contract-none: guard-build ready passes" "$wt_cn" sh .agents-v0/scripts/guard-build.sh ready cleanup-job
expect_pass "contract-none: approve build cleanup-job via PTY" "$wt_cn" pty_approve "$wt_cn" build cleanup-job "Approve build cleanup-job"
expect_pass "contract-none: commit build cleanup-job backfills Design and Build rows" "$wt_cn" sh .agents-v0/scripts/guard-build.sh commit cleanup-job
grep -Eq '^\|[[:space:]]*Design[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt_cn/docs/agents-v0/requirements/cleanup-job.md" \
  && pass "contract-none: backfilled Approved Design row in cleanup-job.md" || fail "contract-none: missing Design row"
grep -Eq '^\|[[:space:]]*Build[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt_cn/docs/agents-v0/requirements/cleanup-job.md" \
  && pass "contract-none: appended Approved Build row in cleanup-job.md" || fail "contract-none: missing Build row"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
