#!/bin/sh
# test-guard-design.sh — automated test suite for /v0-design guard (Design: DD1-DD8, DDA).
# Run: sh scripts/test-guard-design.sh
set -u

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/test-guard-design.XXXXXX")"
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
for s in guard-common.sh guard-intake.sh guard-design.sh secret_scan.py sync-feature-state.sh \
         resolve-integration-branch.sh feature-worktree.sh check-gate-commit.sh check-traceability.sh \
         check-story-dependencies.sh; do
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

# 1. Slug validation & P0-A redirection (DD1, FD5)
expect_fail "check: missing feature slug is refused" "$r" sh .agents-v0/scripts/guard-design.sh check
expect_fail "check: uppercase slug is refused" "$r" sh .agents-v0/scripts/guard-design.sh check Orders-API
expect_fail "check: path traversal slug is refused" "$r" sh .agents-v0/scripts/guard-design.sh check "../orders"
expect_fail "check: p0-a slug is refused and redirected to /v0-scaffold" "$r" sh .agents-v0/scripts/guard-design.sh check p0-a-platform-skeleton
expect_out "check: p0-a refusal names /v0-scaffold" "/v0-scaffold"

# 2. Branch & Intake prerequisite checks (DD1, FD5)
expect_fail "check: refuses on main when no feature/orders branch exists" "$r" sh .agents-v0/scripts/guard-design.sh check orders
expect_out "check: refusal names /v0-intake orders" "/v0-intake orders"

# Complete intake for 'orders' via guard-intake.sh + PTY
expect_pass "setup: start intake orders" "$r" sh .agents-v0/scripts/guard-intake.sh start orders
cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Feature Requirements: orders

As a clerk, I want to place and view orders, so that stock is reserved and visible.

Surfaces: backend, frontend
Vertical slice: yes

## Preconditions
- Stock catalog is loaded.

## Desk check
Material: no
- POST /api/v1/orders returns 201; GET /api/v1/orders/{id} returns 200.

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

### AC-3 — view order by id (BOLA)
Kind: edge
Given a signed-in clerk who does not own order 99
When the clerk requests GET /api/v1/orders/99
Then the request is rejected with HTTP 403 Forbidden

## Out of scope
- Refunds

## Non-functional requirements
- Latency: p95 < 200ms

## Applicable regulations
- GDPR

## Security-review triggers
- Auth / RBAC changes: yes

## UX requirements
- WCAG 2.1 AA compliance
- Desktop and mobile responsive breakpoints

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
expect_fail "check: refuses on main when feature/orders worktree exists elsewhere" "$r" sh .agents-v0/scripts/guard-design.sh check orders
expect_out "check: refusal points to worktree folder" "repo-orders"

expect_pass "check: passes inside feature/orders worktree" "$wt" sh .agents-v0/scripts/guard-design.sh check orders

# 3. Start, Block & Helper-brief deduplication (DD2, FD6)
expect_pass "start: seeds design.md and sets in_progress" "$wt" sh .agents-v0/scripts/guard-design.sh start orders
[ -f "$wt/docs/agents-v0/design/orders/design.md" ] && pass "start: seeded docs/agents-v0/design/orders/design.md" || fail "start: missing design.md"
grep -Fq '"activeStatus": "in_progress"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start: state is in_progress" || fail "start: state not in_progress"

cat > "$wt/docs/agents-v0/design/orders/helper-brief.md" <<'EOF'
helper: docs-author
outputs: docs/agents-v0/design/orders/ux-spec.md
return: paths
ask: Draft UX spec component table
EOF
expect_pass "block: first helper brief is recorded and sets blocked" "$wt" \
  sh .agents-v0/scripts/guard-design.sh block orders "Waiting on docs-author"
expect_fail "block: identical repeat helper brief is refused" "$wt" \
  sh .agents-v0/scripts/guard-design.sh block orders "Waiting on docs-author again"
expect_out "block: duplicate brief refusal message" "duplicate helper brief"
rm -f "$wt/docs/agents-v0/design/orders/helper-brief.md"
expect_pass "start: resumes design after helper brief removed" "$wt" sh .agents-v0/scripts/guard-design.sh start orders

# 4. Ready deterministic validation (DD3, FD3)
expect_fail "ready: refuses template design.md with <!-- TEMPLATE: comments" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names unresolved TEMPLATE lines" "TEMPLATE:"

# Test repo-wide OpenAPI catalog modification refusal (Jiraiya Rec 3)
mkdir -p "$wt/openapi"
printf 'openapi: 3.0.3\n' > "$wt/openapi/api-v1.yaml"
expect_fail "ready: refuses when repo-wide openapi/ catalog is modified during Design" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names repo-wide OpenAPI catalog" "repo-wide OpenAPI catalog"
rm -rf "$wt/openapi"

# Write design.md missing AC-3 in Failure modes
cat > "$wt/docs/agents-v0/design/orders/design.md" <<'EOF'
# Design: orders

ADR: docs/agents-v0/adr/01-orders.md

## Traceability
| Requirement | Satisfied by | Notes |
|---|---|---|
| AC-1 | createOrder | POST /api/v1/orders |
| AC-2 | createOrder | additionalProperties: false |
| AC-3 | getOrder | BOLA ownership check |

## Data model
Table `orders` (id UUID PK, clerk_id UUID indexed, sku VARCHAR).

## Authorization
| operationId | Roles or scopes | Resource rule | Notes |
|---|---|---|---|
| createOrder | ROLE_CLERK | caller is authenticated clerk | |
| getOrder | ROLE_CLERK | — | |

## Events
N/A: no event contract

## Failure modes
- AC-2: invalid payload returns 400 RFC 7807 problem detail.

## Observability
Metrics: orders_created_total.

## Rollout
Feature flag `orders.enabled`.
EOF

expect_fail "ready: refuses when Failure modes misses Kind: edge AC-3" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names missing AC-3 in Failure modes" "AC-3"

# Add AC-3 to Failure modes section
sed -i '/^- AC-2:/a - AC-3: non-owner clerk request returns 403 Forbidden.' "$wt/docs/agents-v0/design/orders/design.md"

# Write openapi.yaml with /api/v1/orders/{id} first so BOLA check triggers first
cat > "$wt/docs/agents-v0/design/orders/openapi.yaml" <<'EOF'
openapi: 3.0.3
info:
  title: Orders Draft
  version: "1.0.0"
paths:
  /api/v1/orders/{id}:
    get:
      operationId: getOrder
      responses:
        "200":
          description: OK
  /api/v1/orders:
    post:
      operationId: createOrder
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                sku:
                  type: string
      responses:
        "201":
          description: Created
EOF

expect_fail "ready: refuses parameterized {id} operation without BOLA Resource rule in Authorization" "$wt" \
  sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names BOLA Resource rule for getOrder" "BOLA Resource rule"

# Fix BOLA Resource rule in design.md
sed -i 's/| getOrder | ROLE_CLERK | — | |/| getOrder | ROLE_CLERK | order.clerkId == principal.id (verified as same-role peer) | |/' "$wt/docs/agents-v0/design/orders/design.md"

expect_fail "ready: refuses POST operation without Idempotency-Key header" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names Idempotency-Key" "Idempotency-Key"

# Add Idempotency-Key but still omit additionalProperties: false
cat > "$wt/docs/agents-v0/design/orders/openapi.yaml" <<'EOF'
openapi: 3.0.3
info:
  title: Orders Draft
  version: "1.0.0"
paths:
  /api/v1/orders/{id}:
    get:
      operationId: getOrder
      responses:
        "200":
          description: OK
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
              properties:
                sku:
                  type: string
      responses:
        "201":
          description: Created
EOF

expect_fail "ready: refuses write operation without additionalProperties: false" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names additionalProperties: false" "additionalProperties: false"

# Add additionalProperties: false
sed -i '/type: object/a\              additionalProperties: false' "$wt/docs/agents-v0/design/orders/openapi.yaml"

# UX spec and mockups checks (since frontend is in Surfaces)
expect_fail "ready: refuses when frontend surface is in scope but ux-spec.md is missing" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names missing ux-spec.md" "ux-spec.md"

mkdir -p "$wt/docs/agents-v0/design/orders/mockups"
cat > "$wt/docs/agents-v0/design/orders/ux-spec.md" <<'EOF'
# UX Spec: orders

## State matrix
- loading: skeleton spinner
- error: inline banner
- empty: empty state illustration
- success: order table

## Component defaults
| Component | Screen | Mockup | Operation | Default behavior | Override |
|---|---|---|---|---|---|
| SubmitOrderButton | OrderScreen | mockups/order-form.html | createOrder | Submits order | |

## Accessibility
Conforms to WCAG 2.1 AA keyboard and contrast rules.
EOF

cat > "$wt/docs/agents-v0/design/orders/mockups/order-form.html" <<'EOF'
<!DOCTYPE html>
<html>
<body>
  <button data-component="UnlistedButton">Place Order</button>
</body>
</html>
EOF

expect_fail "ready: refuses mockup data-component not listed in ux-spec.md" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names UnlistedButton" "UnlistedButton"

sed -i 's/UnlistedButton/SubmitOrderButton/' "$wt/docs/agents-v0/design/orders/mockups/order-form.html"

# ADR and review.md checks
mkdir -p "$wt/docs/agents-v0/adr"
cat > "$wt/docs/agents-v0/adr/01-orders.md" <<'EOF'
# ADR 01: Synchronous Order Reservation

Status: Proposed

## Options
### Option 1: Synchronous reservation
### Option 2: Async queue reservation
EOF

expect_fail "ready: refuses when review.md is missing" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names missing review.md" "review.md"

cat > "$wt/docs/agents-v0/design/orders/review.md" <<'EOF'
agent: design-reviewer

| # | Label | Finding | Evidence | Status |
|---|---|---|---|---|
| 1 | Critical | Missing rate limit note | design.md:10 | Open |
EOF

expect_fail "ready: refuses when review.md has an Open Critical finding" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_out "ready: names Open Critical finding" "Open Critical"

sed -i 's/| Open |/| Resolved |/' "$wt/docs/agents-v0/design/orders/review.md"

expect_pass "ready: passes when all contracts, traceability, UX mockups, ADR, and review.md are valid" "$wt" \
  sh .agents-v0/scripts/guard-design.sh ready orders
grep -Fq '"activeStatus": "awaiting_approval"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "ready: state is awaiting_approval" || fail "ready: state not awaiting_approval"

# 5. Self-approval defense & Parameterized External Approval (DDA, FD1)
expect_fail "self-approval blocked: sync-feature-state.sh --approve design refuses without external approval record" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/orders.md
expect_out "self-approval refusal names guard-common.sh approve design orders" "guard-common.sh approve design orders"

expect_fail "commit: refuses before the user approves design" "$wt" sh .agents-v0/scripts/guard-design.sh commit orders

expect_pass "approve: the user approves design orders via PTY" "$wt" pty_approve "$wt" design orders "LGTM orders design"
grep -Fq '"lastApprovedPhase": "design"' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "approve: orders.state.json records lastApprovedPhase=design" || fail "approve: lastApprovedPhase!=design"

# 6. Commit with ADR promotion, traceability, safe staging, and secret scan (DD5, FD2)
expect_pass "commit: promotes ADR to Accepted, writes Design row, runs traceability, scans secrets, and commits" "$wt" \
  sh .agents-v0/scripts/guard-design.sh commit orders
expect_out "commit: prints orders: design approved" "orders: design approved"

grep -Fq "Status: Accepted" "$wt/docs/agents-v0/adr/01-orders.md" \
  && pass "commit: promoted ADR 01-orders.md to Status: Accepted" || fail "commit: ADR not promoted to Accepted"
grep -Eq '\|[[:space:]]*Design[[:space:]]*\|.*\|[[:space:]]*Approved[[:space:]]*\|' "$wt/docs/agents-v0/requirements/orders.md" \
  && pass "commit: appended Approved Design row to Delivery approvals" || fail "commit: missing Approved Design row"
grep -Fq -- '- status: approved' "$wt/docs/agents-v0/requirements/orders.phase-result.md" \
  && pass "commit: updated orders.phase-result.md status to approved" || fail "commit: phase-result status not approved"
[ -f "$wt/docs/agents-v0/requirements/orders.trace.json" ] \
  && pass "commit: wrote orders.trace.json via check-traceability.sh" || fail "commit: missing orders.trace.json"
[ "$(git -C "$wt" log -1 --format=%s)" = "orders: design approved" ] \
  && pass "commit: HEAD commit subject on feature/orders is 'orders: design approved'" || fail "commit: unexpected commit subject"

# 7. Reopen (--reopen) support & bounce cap (DD1, DD2, FD6)
expect_fail "start without --reopen refuses already-approved design" "$wt" sh .agents-v0/scripts/guard-design.sh start orders
expect_pass "check --reopen: allows reopening approved design" "$wt" sh .agents-v0/scripts/guard-design.sh check orders --reopen
expect_pass "start --reopen: increments reopenCount and withdraws design from approvedPhases" "$wt" sh .agents-v0/scripts/guard-design.sh start orders --reopen
grep -Fq '"reopenCount": 1' "$wt/docs/agents-v0/requirements/orders.state.json" \
  && pass "start --reopen: reopenCount is 1" || fail "start --reopen: reopenCount!=1"
expect_pass "ready after reopen" "$wt" sh .agents-v0/scripts/guard-design.sh ready orders
expect_pass "approve after reopen via PTY" "$wt" pty_approve "$wt" design orders "Approve amended design"
expect_pass "commit after reopen" "$wt" sh .agents-v0/scripts/guard-design.sh commit orders

# 8. /v0-build handoff check (DD7, FD8)
expect_pass "build handoff: sync-feature-state allows build in_progress when external design approval exists" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase build --status in_progress
(cd "$wt" && sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --clear-active >/dev/null)
git -C "$wt" checkout -q -- docs/agents-v0/requirements/orders.state.json
rec_file="$(find "$AGENTS_V0_APPROVALS_DIR" -name 'design-orders.json' | head -n 1)"
mv "$rec_file" "${rec_file}.bak"
expect_fail "build handoff: refuses build in_progress when external design approval record is missing" "$wt" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase build --status in_progress
expect_out "build handoff: refusal names external design approval record" "external design approval record"
mv "${rec_file}.bak" "$rec_file"

# 9. Contract: None shortcut flow (DD3, DD5, DD7, Jiraiya Rec 2)
expect_pass "setup: start intake cleanup-job on main" "$r" sh .agents-v0/scripts/guard-intake.sh start cleanup-job
cat > "$r/docs/agents-v0/requirements/cleanup-job.md" <<'EOF'
# Feature Requirements: cleanup-job

As an operator, I want expired temp files purged nightly, so that disk usage stays bounded.

Surfaces: backend
Vertical slice: no

## Preconditions
- Temp directory exists.

## Desk check
Material: no
- Internal cron purges files older than 24h.

## Acceptance criteria

### AC-1 — purge expired files
Kind: happy
Given temp files older than 24 hours
When the nightly cleanup job runs
Then files older than 24 hours are deleted and the count is logged

### AC-2 — skip locked files
Kind: edge
Given a temp file currently locked by an active worker
When the nightly cleanup job runs
Then the locked file is skipped without error and retried on the next run

## Out of scope
- Archiving to S3

## Non-functional requirements
- Finishes within 30s

## Applicable regulations
- None

## Security-review triggers
- State-changing endpoint: no
- Auth / RBAC changes: no

## Open questions
Open questions: none

## Delivery approvals
| Phase | Artifacts | Approver | Decision | Date |
|---|---|---|---|---|
EOF
expect_pass "setup: ready intake cleanup-job" "$r" sh .agents-v0/scripts/guard-intake.sh ready cleanup-job
expect_pass "setup: approve intake cleanup-job" "$r" pty_approve "$r" intake cleanup-job "Approve cleanup-job intake"
expect_pass "setup: commit intake cleanup-job" "$r" sh .agents-v0/scripts/guard-intake.sh commit cleanup-job

wt2="$tmp/repo-cleanup-job"
expect_pass "contract-none: start design in cleanup-job worktree" "$wt2" sh .agents-v0/scripts/guard-design.sh start cleanup-job
cat > "$wt2/docs/agents-v0/design/cleanup-job/design.md" <<'EOF'
# Design: cleanup-job

ADR: N/A: no product decision

## Traceability
| Requirement | Satisfied by | Notes |
|---|---|---|
| AC-1 | TempFileCleanupTask | Scheduled task |
| AC-2 | TempFileCleanupTask | Skips locked files |

## Data model
N/A: filesystem only, no database changes.

## Authorization
N/A: no /api/v1 operation

## Events
N/A: no event contract

## Failure modes
- AC-2: locked file is skipped and logged at DEBUG.

## Observability
Metric `cleanup_purged_files_total`.

## Rollout
Enabled by default.
EOF

expect_pass "contract-none: ready detects Contract: None shortcut without requiring review.md or ADR file" "$wt2" \
  sh .agents-v0/scripts/guard-design.sh ready cleanup-job
expect_out "contract-none: ready output mentions Contract: None shortcut" "Contract: None shortcut"
expect_pass "contract-none: commit commits Contract: None design without requiring external design approval" "$wt2" \
  sh .agents-v0/scripts/guard-design.sh commit cleanup-job
expect_out "contract-none: commit message is 'cleanup-job: design (Contract: None)'" "cleanup-job: design \(Contract: None\)"
expect_pass "contract-none: build in_progress is allowed immediately after Contract: None commit" "$wt2" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/cleanup-job.md --active-phase build --status in_progress

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

