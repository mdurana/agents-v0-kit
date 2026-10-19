#!/bin/sh
# test-ci-checks.sh — behavior tests for the template CI scripts (no network).
# Covers: resolve-layout.sh (Service roots), check-attempt-budget.sh, check-approvals.sh (plan),
# check-milestone.sh (story order, SLO waivers), check-event-schemas.sh, check-gate-metrics.sh.
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
CI="$KIT/templates/.agents-v0/ci"
SC="$KIT/templates/.agents-v0/scripts"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

# expect_pass <description> <dir> <command...>   expect_fail <description> <dir> <command...>
expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >/dev/null 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; fi
}
expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >/dev/null 2>&1; then fail "$desc (expected non-zero)"; else pass "$desc"; fi
}

sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

git_commit() {
  git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$1"
}

# write_pack <dir>: a complete, valid program architecture pack.
write_pack() {
  p="$1"
  mkdir -p "$p/docs/agents-v0/design/system/components" "$p/docs/agents-v0/adr"
  cat > "$p/docs/agents-v0/architecture.md" <<'EOF'
# Architecture

## C4 Context

```mermaid
flowchart TB
  Customer[Customer]
  subgraph orderPlatform [Order Platform]
    OrderApp[Order application]
  end
  Customer -->|HTTPS| OrderApp
```

## C4 Container

```mermaid
flowchart TB
  Customer[Customer]
  subgraph orderPlatform [Order Platform]
    WebApp[Web application]
    OrderService[Order service]
    MessageBus[Message bus]
  end
  Customer -->|HTTPS| WebApp
  WebApp -->|sync REST| OrderService
  OrderService -->|"async event"| MessageBus
```

## Data flow

```mermaid
flowchart TB
  Customer[Customer]
  subgraph orderPlatform [Order Platform]
    WebApp[Web application]
    OrderService[Order service]
    MessageBus[Message bus]
  end
  Customer -->|"HTTPS / HTML and JSON"| WebApp
  WebApp -->|"REST / JSON order request"| OrderService
  OrderService -->|"async / order-created event"| MessageBus
```

## Data models

### Conceptual

An Order belongs to one Customer.

### Logical

```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  CUSTOMER {
    id PK
    email
  }
  ORDER {
    id PK
    customer_id FK
    status
  }
```

### Physical

```mermaid
erDiagram
  CUSTOMER ||--o{ ORDER : places
  CUSTOMER {
    uuid id PK
    varchar_255 email
  }
  ORDER {
    uuid id PK
    uuid customer_id FK
    varchar_32 status
  }
```

## State machine

```mermaid
stateDiagram-v2
  [*] --> Draft
  Draft --> Submitted: POST /orders
  Submitted --> [*]
```

## Failure domains and degradation

| Dependency | Failure | Blast radius | Degraded behaviour | Validation |
|------------|---------|--------------|--------------------|------------|
| Message bus | unavailable | new orders accepted but not published | outbox retries; the order page shows pending | dependency-kill test in P4 |

## MVP and future state

One service and one bus now. A second service is split out when a second team owns checkout.
EOF
  cat > "$p/docs/agents-v0/network.md" <<'EOF'
# Network

## Target topology

```mermaid
flowchart LR
  subgraph publicZone [Public]
    Ingress[Ingress]
  end
  subgraph privateZone [Private]
    Workloads[Workloads]
  end
  Ingress -->|HTTPS| Workloads
```
EOF
  cat > "$p/docs/agents-v0/design/system/nfr-slo.md" <<'EOF'
# NFR / SLO budget

| Surface | Latency (p95) | Availability | Notes |
|---------|---------------|--------------|-------|
| checkout | 300ms | 99.9% | |
EOF
  cat > "$p/docs/agents-v0/design/system/threat-model.md" <<'EOF'
# Threat model

## Assets

- customer email

## Trust boundaries

- browser to ingress

## Top risks (STRIDE)

| Risk | Mitigation |
|------|------------|
| spoofed session | signed tokens |
EOF
  cat > "$p/docs/agents-v0/design/system/ops-readiness.md" <<'EOF'
# Operations readiness

## Build and run ownership

| Item | Value |
|------|-------|
| Owning team | orders |

## Error budget policy

When a budget is spent, feature releases stop until it recovers.

## Database maintenance and operation

N/A: the first release has no datastore of its own.

## Production readiness checklist

- [ ] On-call rotation and escalation path are defined.
EOF
  cat > "$p/docs/agents-v0/adr/01-pattern.md" <<'EOF'
# ADR 01: pattern

- **Status:** Proposed

Pack: java
EOF
  cat > "$p/docs/agents-v0/design/system/arc-record.md" <<'EOF'
# ARC record

## Options

docs/agents-v0/adr/01-pattern.md

## Fitness functions

| Principle | Check | Threshold | On failure |
|-----------|-------|-----------|------------|
| no module cycles | ArchUnit rule | zero cycles | block merge |
EOF
  cat > "$p/docs/agents-v0/design/system/context-map.md" <<'EOF'
# System context map

## Bounded contexts

| Context | Responsibility | Integrations | Service root | Contract | Sequence diagram | Component plan | Status |
|---------|----------------|--------------|--------------|----------|------------------|----------------|--------|
| orders | place orders | bus | . | openapi/api-v1.yaml | N/A: none yet | N/A: single service in this release | planned |
EOF
  cat > "$p/docs/agents-v0/design/system/architecture-review.md" <<'EOF'
agent: design-reviewer

| # | Label | Finding | Evidence | Status |
|---|-------|---------|----------|--------|
| 1 | Suggestion | name the retry budget | architecture.md | Resolved |
EOF
}

# --- resolve-layout.sh -------------------------------------------------------
d="$tmp/layout-auto"
mkdir -p "$d/services/order" "$d/services/inventory"
: > "$d/services/order/pom.xml"
: > "$d/services/inventory/pom.xml"
out="$(cd "$d" && sh "$CI/resolve-layout.sh")"
printf '%s' "$out" | grep -Fq "SERVICE_ROOTS='services/inventory services/order'" \
  && pass "resolve-layout detects services/*/ modules" || fail "resolve-layout detects services/*/ modules"

d="$tmp/layout-profile"
mkdir -p "$d/docs/agents-v0"
cat > "$d/docs/agents-v0/project-profile.md" <<'EOF'
| This repo | Value |
|-----------|--------|
| Profile | service |
| Backend root | n/a |
| Frontend root | n/a |
| BFF root | n/a |
| Service roots | services/a, services/b |
EOF
out="$(cd "$d" && sh "$CI/resolve-layout.sh")"
printf '%s' "$out" | grep -Fq "SERVICE_ROOTS='services/a services/b'" \
  && pass "resolve-layout reads the Service roots row" || fail "resolve-layout reads the Service roots row"
printf '%s' "$out" | grep -Fq "BACKEND_ROOT=''" \
  && pass "resolve-layout leaves Backend root empty with Service roots" || fail "resolve-layout leaves Backend root empty with Service roots"
sed 's|services/a, services/b|../escape|' "$d/docs/agents-v0/project-profile.md" > "$d/docs/bad.md"
expect_fail "resolve-layout rejects a Service root outside the repo" "$d" sh "$CI/resolve-layout.sh" docs/bad.md

# --- check-attempt-budget.sh -------------------------------------------------
d="$tmp/budget"
mkdir -p "$d"
cat > "$d/build-report.md" <<'EOF'
# Build report

| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| mvn verify | 1 | 1 | FooTest | Foo.java:10 |
| mvn verify | 1 | 2 | BarTest | Bar.java:5 |
| mvn verify | 0 | 3 | | |

| Metric | Exit |
|--------|------|
| other table | 7 |
EOF
expect_pass "attempt budget: 2 failed of 3 allows another attempt" "$d" sh "$SC/check-attempt-budget.sh" build-report.md 3
expect_fail "attempt budget: 2 failed of 2 is spent" "$d" sh "$SC/check-attempt-budget.sh" build-report.md 2

# --- check-approvals.sh plan + check-milestone.sh order ---------------------
d="$tmp/milestone"
mkdir -p "$d/docs/agents-v0/milestones" "$d/docs/agents-v0/requirements"
cat > "$d/docs/agents-v0/milestones/m.md" <<'EOF'
# Milestone: M

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| M-A | As a user, I want a, so that b. | docs/agents-v0/requirements/a.md | planned | — |
| M-B | As a user, I want c, so that d. | docs/agents-v0/requirements/b.md | planned | M-A |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/m.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/requirements/a.md" <<'EOF'
# A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/a.md | dev | Approved | 2026-01-01 |
| Build | docs/agents-v0/build/a/build-report.md | dev | Approved | 2026-01-02 |
EOF
cat > "$d/docs/agents-v0/requirements/b.md" <<'EOF'
# B

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/b.md | dev | Approved | 2026-01-01 |
| Build | docs/agents-v0/build/b/build-report.md | dev | Approved | 2026-01-03 |
EOF
# Decision semantics: the last row for a phase is the current decision, and a conditional approval
# is not an approval.
mkdir -p "$d/docs/agents-v0/build/dec"
printf 'commit: abcdef1234567\n' > "$d/docs/agents-v0/build/dec/build-report.md"
mkdir_dec() { # <name> <rows...>: write docs/agents-v0/requirements/<name>.md with the given approval rows
  name="$1"; shift
  {
    printf '# Dec\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$d/docs/agents-v0/requirements/$name.md"
}
mkdir_dec dec-stale-approved \
  '| Verify | docs/agents-v0/build/dec/build-report.md | @ada | Approved | 2026-01-01 |' \
  '| Verify | docs/agents-v0/build/dec/build-report.md | @ada | Re-opened | 2026-01-02 |'
expect_fail "check-approvals: a later Re-opened row overrides an earlier Approved row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/dec-stale-approved.md verify
mkdir_dec dec-reapproved \
  '| Verify | docs/agents-v0/build/dec/build-report.md | @ada | Re-opened | 2026-01-01 |' \
  '| Verify | docs/agents-v0/build/dec/build-report.md | @ada | Approved | 2026-01-02 |'
expect_pass "check-approvals: a later Approved row overrides an earlier Re-opened row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/dec-reapproved.md verify
mkdir_dec dec-conditional '| Design | docs/agents-v0/design/x/design.md | @ada | Approved with conditions: fix X | 2026-01-01 |'
expect_fail "check-approvals: Approved with conditions is not an approval" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/dec-conditional.md design
mkdir_dec dec-pending '| Design | docs/agents-v0/design/x/design.md | @ada | Approved, pending review | 2026-01-01 |'
expect_fail "check-approvals: a pending approval is not an approval" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/dec-pending.md design
mkdir_dec dec-plain '| Design | docs/agents-v0/design/x/design.md | @ada | Approved | 2026-01-01 |'
expect_pass "check-approvals: a plain Approved row still passes" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/dec-plain.md design
mkdir_dec dec-evidence \
  '| Build | docs/agents-v0/build/missing/build-report.md | @ada | Approved | 2026-01-01 |' \
  '| Build | docs/agents-v0/build/dec/build-report.md | @ada | Approved | 2026-01-02 |'
expect_pass "check-evidence reads the last row for a phase" "$d" env VERIFY_STALE=0 sh "$CI/check-evidence.sh" docs/agents-v0/requirements/dec-evidence.md build
mkdir -p "$d/docs/agents-v0/build/p0-a-platform-skeleton"
printf 'commit: abcdef1234567\n' > "$d/docs/agents-v0/build/p0-a-platform-skeleton/build-report.md"
{
  printf '# Story: P0-A\nMilestone: P0 — Platform Skeleton\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n'
} > "$d/docs/agents-v0/requirements/p0-a-platform-skeleton.md"
expect_pass "check-evidence accepts unapproved P0-A build evidence on disk" "$d" env VERIFY_STALE=0 sh "$CI/check-evidence.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md build
# The state file follows the same rules.
mkdir_dec dec-state \
  '| Intake | docs/agents-v0/requirements/dec-state.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved with conditions: fix X | 2026-01-02 |'
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state.md >/dev/null 2>&1)
if grep -Fq '"lastApprovedPhase": "intake"' "$d/docs/agents-v0/requirements/dec-state.state.json"; then pass "state: a conditional design approval leaves lastApprovedPhase at intake"; else fail "state: a conditional design approval leaves lastApprovedPhase at intake"; fi
mkdir_dec dec-state2 \
  '| Intake | docs/agents-v0/requirements/dec-state2.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved | 2026-01-02 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Re-opened | 2026-01-03 |'
mkdir -p "$d/.git/refs/heads"
printf 'ref: refs/heads/main\n' > "$d/.git/HEAD"
printf '0123456789abcdef0123456789abcdef01234567\n' > "$d/.git/refs/heads/main"
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state2.md >/dev/null 2>&1)
if grep -Fq '"lastApprovedPhase": "intake"' "$d/docs/agents-v0/requirements/dec-state2.state.json"; then pass "state: a later Re-opened row withdraws an earlier Approved design"; else fail "state: a later Re-opened row withdraws an earlier Approved design"; fi
if grep -Eq '"baseCommit": "[0-9a-f]{40}"' "$d/docs/agents-v0/requirements/dec-state2.state.json"; then pass "state: sync-feature-state records baseCommit SHA"; else fail "state: sync-feature-state records baseCommit SHA"; fi
expect_pass "check-feature-state passes when baseCommit is set" "$d" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/dec-state2.md
python3 - "$d/docs/agents-v0/requirements/dec-state2.state.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p, encoding="utf-8"))
data["baseCommit"] = ""
json.dump(data, open(p, "w", encoding="utf-8"), indent=2)
PY
expect_fail "check-feature-state fails when baseCommit is empty in a git repo" "$d" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/dec-state2.md
(cd "$d" && HOOK_BASE="" sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state2.md >/dev/null 2>&1)
expect_pass "sync-feature-state backfills empty baseCommit from .git/HEAD" "$d" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/dec-state2.md
mkdir_dec dec-reopen \
  '| Intake | docs/agents-v0/requirements/dec-reopen.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved | 2026-01-02 |' \
  '| Build | docs/agents-v0/build/x/build-report.md | @ada | Re-opened | 2026-01-03 |'
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-reopen.md --active-phase verify --status blocked --reason "Build is Re-opened" >/dev/null 2>&1)
if grep -Fq '"activePhase": "build"' "$d/docs/agents-v0/requirements/dec-reopen.state.json"; then pass "state: blocked verify with Re-opened build routes activePhase to build"; else fail "state: blocked verify with Re-opened build routes activePhase to build"; fi
expect_pass "check-feature-state accepts activePhase routed to Re-opened build" "$d" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/dec-reopen.md
python3 - "$d/docs/agents-v0/requirements/dec-reopen.state.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p, encoding="utf-8"))
data["activePhase"] = "verify"
json.dump(data, open(p, "w", encoding="utf-8"), indent=2)
PY
expect_fail "check-feature-state rejects activePhase verify when build is Re-opened" "$d" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/dec-reopen.md
expect_pass "check-approvals accepts the plan row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/milestones/m.md plan
expect_fail "check-approvals rejects a missing plan row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/requirements/a.md plan
expect_fail "check-milestone fails a build-approved story whose dependency lacks verify" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake
expect_pass "check-milestone order check can be turned off" "$d" env MILESTONE_ORDER=0 sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake
printf '| Verify | docs/agents-v0/verify/a/test-report.md | dev | Approved | 2026-01-04 |\n' >> "$d/docs/agents-v0/requirements/a.md"
expect_pass "check-milestone passes once the dependency has a verify approval" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake
cat > "$d/docs/agents-v0/milestones/m.md" <<'EOF'
# Milestone: M

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| M-A | As a user, I want a, so that b. | docs/agents-v0/requirements/a.md | planned | — |
| M-B | As a user, I want c, so that d. | docs/agents-v0/requirements/b.md | planned | M-A |
| M-C | As a user, I want e, so that f. | docs/agents-v0/requirements/c.md | planned | docs/agents-v0/milestones/earlier.md |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/m.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/requirements/c.md" <<'EOF'
# C

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/c.md | dev | Approved | 2026-01-01 |
| Build | docs/agents-v0/build/c/build-report.md | dev | Approved | 2026-01-05 |
EOF
mkdir -p "$d/docs/agents-v0/milestones"
printf '# Earlier\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n| plan | x | dev | Approved | 2026-01-01 |\n' > "$d/docs/agents-v0/milestones/earlier.md"
expect_fail "check-milestone fails Build when a dependency manifest has no milestone approval" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake
printf '| milestone | docs/agents-v0/milestones/earlier.md | dev | Approved | 2026-01-06 |\n' >> "$d/docs/agents-v0/milestones/earlier.md"
expect_pass "check-milestone accepts a dependency manifest with an approved milestone row" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake

# Cross-milestone story dependencies and plan phase
cat > "$d/docs/agents-v0/milestones/m2.md" <<'EOF'
# Milestone: M2

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| M2-A | As a user, I want g, so that h. | docs/agents-v0/requirements/g.md | planned | M-A | backend | 3 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/m2.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/requirements/g.md" <<'EOF'
# G

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/g.md | dev | Approved | 2026-01-01 |
| Build | docs/agents-v0/build/g/build-report.md | dev | Approved | 2026-01-05 |
EOF
expect_pass "check-milestone cross-milestone: M2-A passes when dependency M-A has verify approval" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m2.md intake
sedi '/Verify.*Approved/d' "$d/docs/agents-v0/requirements/a.md"
expect_fail "check-milestone cross-milestone: M2-A fails when dependency M-A lacks verify approval" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m2.md intake
printf '| Verify | docs/agents-v0/verify/a/test-report.md | dev | Approved | 2026-01-04 |\n' >> "$d/docs/agents-v0/requirements/a.md"

cp "$KIT/templates/docs/agents-v0/milestones/_template.md" "$d/docs/agents-v0/milestones/_template.md"
expect_pass "check-milestone plan phase accepts acyclic concrete stories and ignores _template.md" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m2.md plan

d_p0="$tmp/milestone-p0-seeded"
mkdir -p "$d_p0/docs/agents-v0/milestones"
cp "$KIT/templates/docs/agents-v0/milestones/"*.md "$d_p0/docs/agents-v0/milestones/"
expect_pass "check-milestone plan phase accepts seeded p0-platform-skeleton.md alongside unfilled sibling templates" "$d_p0" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/p0-platform-skeleton.md plan
expect_fail "check-milestone plan phase rejects unfilled p1-contracts-and-data-models.md" "$d_p0" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/p1-contracts-and-data-models.md plan

cat > "$d/docs/agents-v0/milestones/dup.md" <<'EOF'
# Milestone: Dup

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| M2-A | As a user, I want dup, so that x. | docs/agents-v0/requirements/dup.md | planned | — | backend | 2 |
EOF
expect_fail "check-milestone detects duplicate story ID across manifests" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m2.md plan
rm -f "$d/docs/agents-v0/milestones/dup.md"

cat > "$d/docs/agents-v0/milestones/bad-plan.md" <<'EOF'
# Milestone: Bad

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| B-A | As a [role], I want g, so that h. | docs/agents-v0/requirements/ba.md | planned | M-A | backend | 3 |
EOF
expect_fail "check-milestone plan phase rejects [role] placeholder in user story" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/bad-plan.md plan

cat > "$d/docs/agents-v0/milestones/bad-plan.md" <<'EOF'
# Milestone: Bad

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| B-A | As a user, I want g, so that h. | docs/agents-v0/requirements/ba.md | planned | P1 | backend | 3 |
EOF
expect_fail "check-milestone plan phase rejects bare milestone label dependency stub P1" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/bad-plan.md plan

cat > "$d/docs/agents-v0/milestones/bad-plan.md" <<'EOF'
# Milestone: Bad

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| B-A | As a user, I want g, so that h. | docs/agents-v0/requirements/ba.md | planned | M-A | — | 3 |
EOF
expect_fail "check-milestone plan phase rejects unassigned Surface" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/bad-plan.md plan

cat > "$d/docs/agents-v0/milestones/bad-plan.md" <<'EOF'
# Milestone: Bad

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| B-A | As a user, I want g, so that h. | docs/agents-v0/requirements/ba.md | planned | M-A | backend | 9 |
EOF
expect_fail "check-milestone plan phase rejects Size > 8" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/bad-plan.md plan
rm -f "$d/docs/agents-v0/milestones/bad-plan.md"

cat > "$d/docs/agents-v0/milestones/cycle.md" <<'EOF'
# Milestone: Cycle

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| C-A | As a user, I want c1, so that c2. | docs/agents-v0/requirements/ca.md | planned | C-B | backend | 2 |
| C-B | As a user, I want c3, so that c4. | docs/agents-v0/requirements/cb.md | planned | C-A | backend | 2 |
EOF
expect_fail "check-milestone detects dependency cycle and fails" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/cycle.md plan
rm -f "$d/docs/agents-v0/milestones/cycle.md"

# --- check-milestone.sh SLO waivers -----------------------------------------
d="$tmp/slo"
mkdir -p "$d/docs/agents-v0/milestones" "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/design/system" "$d/docs/agents-v0/verify/s"
printf 'commit: abcdef1234567\n' > "$d/docs/agents-v0/verify/s/test-report.md"
cat > "$d/docs/agents-v0/milestones/p4.md" <<'EOF'
# Milestone: P4

Evidence: docs/agents-v0/design/system/slo-evidence.md

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| P4-A | As an operator, I want slo, so that ok. | docs/agents-v0/requirements/s.md | planned | — |
EOF
cat > "$d/docs/agents-v0/requirements/s.md" <<'EOF'
# S

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/s.md | dev | Approved | 2026-01-01 |
| Verify | docs/agents-v0/verify/s/test-report.md | dev | Approved | 2026-01-02 |
EOF
cat > "$d/docs/agents-v0/design/system/slo-evidence.md" <<'EOF'
| Surface | Kind | Command or waiver | Output or approver | Date |
|---------|------|-------------------|--------------------|------|
| checkout | waiver | Not measured | Ada | 2026-01-01 |
EOF
expect_pass "slo waiver is accepted by default" "$d" env VERIFY_STALE=0 sh "$CI/check-milestone.sh" docs/agents-v0/milestones/p4.md verify
expect_fail "slo waiver is rejected with SLO_ALLOW_WAIVERS=0" "$d" env VERIFY_STALE=0 SLO_ALLOW_WAIVERS=0 sh "$CI/check-milestone.sh" docs/agents-v0/milestones/p4.md verify

# --- check-event-schemas.sh --------------------------------------------------
d="$tmp/events"
mkdir -p "$d/docs/agents-v0/design/f/events"
(
  cd "$d"
  git init -q
  printf '{"eventVersion":"1","type":"object","properties":{"id":{"type":"string"},"qty":{"type":"integer"}},"required":["id"]}\n' \
    > docs/agents-v0/design/f/events/order-created.json
  git add -A && git_commit base
)
base="$(cd "$d" && git rev-parse HEAD)"
(
  cd "$d"
  printf '{"eventVersion":"1.1","type":"object","properties":{"id":{"type":"string"},"qty":{"type":"integer"},"note":{"type":"string"}},"required":["id"]}\n' \
    > docs/agents-v0/design/f/events/order-created.json
  git add -A && git_commit additive
)
additive="$(cd "$d" && git rev-parse HEAD)"
(
  cd "$d"
  printf '{"eventVersion":"2","type":"object","properties":{"id":{"type":"string"}},"required":["id"]}\n' \
    > docs/agents-v0/design/f/events/order-created.json
  git add -A && git_commit breaking
)
breaking="$(cd "$d" && git rev-parse HEAD)"
expect_pass "event schema: an added property is additive" "$d" sh "$CI/check-event-schemas.sh" "$base" "$additive"
expect_fail "event schema: a removed property is breaking" "$d" sh "$CI/check-event-schemas.sh" "$base" "$breaking"

# --- check-gate-metrics.sh ---------------------------------------------------
write_module() {
  m="$1"
  mkdir -p "$m/target/surefire-reports" "$m/target/site/jacoco"
  printf '<testsuite tests="3" failures="0" errors="0" skipped="0"/>\n' > "$m/target/surefire-reports/TEST-a.xml"
  cat > "$m/target/site/jacoco/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="x"><package name="com/acme"><sourcefile name="A.java"><line nr="3" mi="0" ci="1"/><line nr="4" mi="1" ci="0"/><counter type="LINE" missed="1" covered="1"/></sourcefile><counter type="LINE" missed="1" covered="1"/></package><counter type="LINE" missed="1" covered="1"/></report>
EOF
}
m="$tmp/gate-ok"
write_module "$m"
expect_pass "gate metrics: executed tests and coverage report pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

# Stage a copy under ci-artifacts/gate/<rel_root> as collect-gate-reports.sh does:
rel_m="$(python3 -c "import os; print(os.path.relpath('$m', '$tmp'))")"
mkdir -p "$tmp/ci-artifacts/gate/$rel_m/target/surefire-reports"
cp "$m/target/surefire-reports/TEST-a.xml" "$tmp/ci-artifacts/gate/$rel_m/target/surefire-reports/"
out="$(cd "$tmp" && sh "$CI/check-gate-metrics.sh" "$m" 2>&1)"
if printf '%s\n' "$out" | grep -Fq "tests: run=3"; then
  pass "gate metrics: does not double-count tests when ci-artifacts/gate copy exists"
else
  fail "gate metrics: double-counted tests with ci-artifacts/gate copy: $out"
fi
rm -rf "$tmp/ci-artifacts"

expect_fail "gate metrics: bundle coverage below MIN_LINE_PCT fails" "$tmp" env MIN_LINE_PCT=80 sh "$CI/check-gate-metrics.sh" "$m"
printf '<testsuite tests="1" failures="1" errors="0" skipped="0"/>\n' > "$m/target/surefire-reports/TEST-b.xml"
expect_fail "gate metrics: a failing test fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

# known_failures budget (project profile table): failures up to the count are reported, not failed.
kf="$tmp/kf"
mkdir -p "$kf/docs/agents-v0"
cat > "$kf/docs/agents-v0/project-profile.md" <<'EOF'
## Brownfield exceptions

### known_failures (optional budget for ci/check-known-failures.sh)

| Allowed failure count | Scope / test IDs | Owner | Remove by |
|----------------------|------------------|-------|-----------|
| 1 | services/order | @ada | 2027-01-01 |

### coverage_ratchet

| Scope | Interim minimum | Approver (Security + architecture) | Remove by |
|-------|-----------------|------------------------------------|-----------|
| services/order | 70 | @ada | 2027-01-01 |
EOF
expect_pass "gate metrics: one failure within a known_failures budget of 1 passes" "$kf" sh "$CI/check-gate-metrics.sh" "$m"
printf '<testsuite tests="2" failures="1" errors="0" skipped="0"/>\n' > "$m/target/surefire-reports/TEST-c.xml"
expect_fail "gate metrics: two failures exceed a known_failures budget of 1" "$kf" sh "$CI/check-gate-metrics.sh" "$m"
rm -f "$m/target/surefire-reports/TEST-b.xml" "$m/target/surefire-reports/TEST-c.xml"

# check-known-failures.sh: --require-failures after a verify that exited non-zero.
printf '[ERROR] Tests run: 3, Failures: 1, Errors: 0, Skipped: 0\n' > "$kf/one-failure.log"
printf '[ERROR] Tests run: 3, Failures: 2, Errors: 0, Skipped: 0\n' > "$kf/two-failures.log"
printf '[ERROR] COMPILATION ERROR : cannot find symbol\n' > "$kf/compile-error.log"
printf 'Failed!  - Failed: 1, Passed: 4, Skipped: 0, Total: 5\n' > "$kf/dotnet-one.log"
printf '=== 1 failed, 3 passed in 0.12s ===\n' > "$kf/pytest-one.log"
printf 'Tests: 1 failed, 2 passed, 3 total\n' > "$kf/jest-one.log"
printf -- '--- FAIL: TestOrder (0.01s)\n' > "$kf/go-one.log"
expect_pass "known failures: one failure within the budget passes with --require-failures" "$kf" sh "$CI/check-known-failures.sh" --require-failures one-failure.log
expect_pass "known failures: dotnet test failure within budget passes" "$kf" sh "$CI/check-known-failures.sh" --require-failures dotnet-one.log
expect_pass "known failures: pytest failure within budget passes" "$kf" sh "$CI/check-known-failures.sh" --require-failures pytest-one.log
expect_pass "known failures: jest/vitest failure within budget passes" "$kf" sh "$CI/check-known-failures.sh" --require-failures jest-one.log
expect_pass "known failures: go test failure within budget passes" "$kf" sh "$CI/check-known-failures.sh" --require-failures go-one.log
expect_pass "coverage ratchet: LINE_COVERAGE_PCT meets interim minimum" "$kf" env LINE_COVERAGE_PCT=75 COVERAGE_SCOPE=services/order sh "$CI/check-coverage-ratchet.sh"
expect_fail "coverage ratchet: LINE_COVERAGE_PCT below interim minimum fails" "$kf" env LINE_COVERAGE_PCT=60 COVERAGE_SCOPE=services/order sh "$CI/check-coverage-ratchet.sh"
expect_fail "known failures: two failures exceed the budget" "$kf" sh "$CI/check-known-failures.sh" --require-failures two-failures.log
expect_fail "known failures: a compile error is not a known failure with --require-failures" "$kf" sh "$CI/check-known-failures.sh" --require-failures compile-error.log
expect_pass "known failures: a log with no test failures still passes without the flag" "$kf" sh "$CI/check-known-failures.sh" compile-error.log

m="$tmp/gate-none"
mkdir -p "$m/target"
expect_fail "gate metrics: zero executed tests fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
expect_pass "gate metrics: ALLOW_NO_TESTS=1 accepts a module with no tests" "$tmp" env ALLOW_NO_TESTS=1 sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-cve"
write_module "$m"
printf '{"dependencies":[{"vulnerabilities":[{"name":"CVE-1","severity":"HIGH"}]}]}\n' > "$m/target/dependency-check-report.json"
expect_fail "gate metrics: an unsuppressed HIGH CVE fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-diff"
mkdir -p "$m/src/main/java/com/acme"
write_module "$m"
printf 'package com.acme;\nclass A {\n}\n' > "$m/src/main/java/com/acme/A.java"
printf 'target/\n' > "$m/.gitignore"
(
  cd "$m"
  git init -q
  git add -A && git_commit base
)
diff_base="$(cd "$m" && git rev-parse HEAD)"
printf 'package com.acme;\nclass A {\nint x;\nint y;\n}\n' > "$m/src/main/java/com/acme/A.java"
(
  cd "$m"
  git add -A && git_commit change
)
expect_fail "gate metrics: diff coverage 50% fails the default 80%" "$tmp" env DIFF_BASE="$diff_base" sh "$CI/check-gate-metrics.sh" "$m"
expect_pass "gate metrics: diff coverage 50% passes MIN_DIFF_LINE_PCT=40" "$tmp" env DIFF_BASE="$diff_base" MIN_DIFF_LINE_PCT=40 sh "$CI/check-gate-metrics.sh" "$m"
mkdir -p "$tmp/docs/agents-v0"
cat > "$tmp/docs/agents-v0/quality-gates.md" <<'EOF'
# Quality gates

## Coverage

| Area | Minimum | CI / stretch |
|------|---------|--------------|
| Changed lines | 40% | CI fails when DIFF_BASE is set |
EOF
expect_pass "gate metrics: diff coverage 50% passes Changed lines 40% from quality-gates.md" "$tmp" env DIFF_BASE="$diff_base" sh "$CI/check-gate-metrics.sh" "$m"
rm -rf "$tmp/docs"

mkdir -p "$m/src/main/resources/db/migration" "$m/src/test/resources" "$m/src/test/java/com/acme"
printf 'CREATE TABLE orders (id UUID PRIMARY KEY);\n' > "$m/src/main/resources/db/migration/V1__init.sql"
printf 'spring:\n  datasource:\n    url: jdbc:h2:mem:testdb\n' > "$m/src/test/resources/application-test.yml"
(
  cd "$m"
  git add -A && git_commit schema_h2_only
)
expect_fail "gate metrics: schema migration diff with H2-only test config fails" "$tmp" env DIFF_BASE="$diff_base" MIN_DIFF_LINE_PCT=0 sh "$CI/check-gate-metrics.sh" "$m"
cat > "$m/src/test/java/com/acme/MigrationIntegrationTest.java" <<'EOF'
package com.acme;
import org.testcontainers.containers.PostgreSQLContainer;
class MigrationIntegrationTest {}
EOF
(
  cd "$m"
  git add -A && git_commit schema_with_tc
)
expect_pass "gate metrics: schema migration diff with Testcontainers test passes" "$tmp" env DIFF_BASE="$diff_base" MIN_DIFF_LINE_PCT=0 sh "$CI/check-gate-metrics.sh" "$m"

mkdir -p "$m/target/pit-reports"
cat > "$m/target/pit-reports/mutations.xml" <<'EOF'
<mutations>
  <mutation detected="true" status="KILLED"/>
  <mutation detected="false" status="SURVIVED"/>
</mutations>
EOF
expect_fail "gate metrics: pitest mutation score 50% below MIN_MUTATION_PCT=75 fails" "$tmp" env MIN_MUTATION_PCT=75 sh "$CI/check-gate-metrics.sh" "$m"
expect_pass "gate metrics: pitest mutation score 50% meeting MIN_MUTATION_PCT=50 passes" "$tmp" env MIN_MUTATION_PCT=50 sh "$CI/check-gate-metrics.sh" "$m"
rm -rf "$m/target/pit-reports"

m="$tmp/gate-python"
mkdir -p "$m"
printf '[project]\nname = "orders"\n' > "$m/pyproject.toml"
printf '<testsuite tests="2" failures="0" errors="0" skipped="0"/>\n' > "$m/pytest-report.xml"
printf '<coverage line-rate="0.91"/>\n' > "$m/coverage.xml"
expect_pass "gate metrics: pytest and coverage.xml pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-python-diff"
mkdir -p "$m"
printf '[project]\nname = "orders"\n' > "$m/pyproject.toml"
printf '<testsuite tests="1" failures="0" errors="0" skipped="0"/>\n' > "$m/pytest-report.xml"
cat > "$m/coverage.xml" <<'EOF'
<coverage line-rate="0.5"><packages><package><classes><class filename="app.py"><lines><line number="1" hits="1"/><line number="2" hits="0"/></lines></class></classes></package></packages></coverage>
EOF
printf 'x = 1\n' > "$m/app.py"
(
  cd "$m"
  git init -q
  git add -A && git_commit base
)
py_base="$(cd "$m" && git rev-parse HEAD)"
printf 'x = 1\ny = 2\n' > "$m/app.py"
(
  cd "$m"
  git add -A && git_commit change
)
expect_fail "gate metrics: python diff coverage 50% fails the default 80%" "$tmp" env DIFF_BASE="$py_base" sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-go"
mkdir -p "$m"
printf 'module example.com/orders\n\ngo 1.26\n' > "$m/go.mod"
expect_fail "gate metrics: a Go module with no test report fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"Action":"pass","Package":"example.com/orders","Test":"TestPlace"}' > "$m/go-test.json"
printf 'mode: set\nexample.com/orders/a.go:1.1,2.2 1 1\n' > "$m/coverage.out"
expect_pass "gate metrics: go test json and coverage.out pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"vulnerabilities":[{"name":"CVE-9","severity":"CRITICAL"}]}' > "$m/cve-report.json"
expect_fail "gate metrics: a top-level vulnerabilities list fails" "$tmp" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" "$m"

d="$tmp/unbound-go"
mkdir -p "$d/app/backend"
printf 'module example.com/orders\n\ngo 1.26\n' > "$d/app/backend/go.mod"
plan="$(cd "$d" && BACKEND_ROOT=app/backend sh "$CI/unbound-verify-plan.sh")"
printf '%s\n' "$plan" | head -n 1 | grep -qx go \
  && pass "unbound plan: a go.mod tree selects go" || fail "unbound plan: a go.mod tree selects go"
printf '%s\n' "$plan" | grep -q 'go test' \
  && pass "unbound plan: the go verify command is the pack command" || fail "unbound plan: the go verify command is the pack command"
d="$tmp/unbound-java"
mkdir -p "$d/app/backend"
printf '<project/>\n' > "$d/app/backend/pom.xml"
plan="$(cd "$d" && BACKEND_ROOT=app/backend sh "$CI/unbound-verify-plan.sh")"
printf '%s\n' "$plan" | grep -qx java \
  && pass "unbound plan: a pom tree selects the java example" || fail "unbound plan: a pom tree selects the java example"
d="$tmp/unbound-none"
mkdir -p "$d"
if (cd "$d" && sh "$CI/unbound-verify-plan.sh") >/dev/null 2>&1; then
  fail "unbound plan: no marker does not select a pack"
else
  pass "unbound plan: no marker does not select a pack"
fi

m="$tmp/gate-dotnet"
mkdir -p "$m/TestResults"
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$m/Orders.csproj"
printf '<TestRun><ResultSummary><Counters total="1" executed="1" passed="1" failed="0"/></ResultSummary></TestRun>\n' > "$m/TestResults/test-results.trx"
printf '<coverage line-rate="0.88"/>\n' > "$m/coverage.cobertura.xml"
expect_pass "gate metrics: trx and cobertura pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"dependencies":[{"vulnerabilities":[{"name":"CVE-2","severity":"HIGH"}]}]}' > "$m/cve-report.json"
expect_fail "gate metrics: a pack cve-report.json HIGH fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"projects":[{"frameworks":[{"topLevelPackages":[{"id":"Newtonsoft.Json","vulnerabilities":[{"severity":"High","advisoryUrl":"https://github.com/advisories/GHSA-1"}]}]}]}]}' > "$m/cve-report.json"
expect_fail "gate metrics: a dotnet list package --vulnerable High CVE fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"vulnerabilities":{"lodash":{"name":"lodash","severity":"critical"}}}' > "$m/cve-report.json"
expect_fail "gate metrics: an npm audit dict critical CVE fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
rm -f "$m/cve-report.json"

m="$tmp/gate-empty"
mkdir -p "$m"
if (cd "$tmp" && sh "$CI/check-gate-metrics.sh" "$m" 2>&1) | grep -Fq "does not assume a language"; then
  pass "gate metrics: no marker does not assume a language"
else
  fail "gate metrics: no marker does not assume a language"
fi

repo="$tmp/gate-rust-repo"
mod="$repo/service"
mkdir -p "$repo/docs/agents-v0" "$repo/.agents-v0/packs/rust" "$mod"
cat > "$repo/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | rust |
EOF
cat > "$repo/.agents-v0/packs/rust/pack.json" <<'EOF'
{
  "id": "rust",
  "verify": "cargo test",
  "verifyFast": "cargo test",
  "coverage": {"path": "coverage.xml", "format": "cobertura"},
  "testsReport": {"path": "junit.xml", "format": "junit"},
  "cve": {"path": "cve-report.json"},
  "authMarker": "auth",
  "publicMarker": "public",
  "migrationTool": "sqlx",
  "ciImage": "rust:1",
  "endpoints": [{"suffix": ".rs", "mapping": "#\\[(get)\\]\\(\"([^\"]+)\"\\)", "security": "auth", "name": "rust"}]
}
EOF
printf '<testsuite tests="2" failures="0" errors="0" skipped="0"/>\n' > "$mod/junit.xml"
printf '<coverage line-rate="0.90"/>\n' > "$mod/coverage.xml"
expect_pass "gate metrics: a rust pack reads its own junit and cobertura paths" "$repo" sh "$CI/check-gate-metrics.sh" service
rm -f "$mod/junit.xml"
printf '<testsuite tests="2" failures="0" errors="0" skipped="0"/>\n' > "$mod/pytest-report.xml"
expect_fail "gate metrics: a rust pack does not read the python report path" "$repo" sh "$CI/check-gate-metrics.sh" service

d="$tmp/roots-go"
mkdir -p "$d/app/backend"
printf 'module example.com/orders\n\ngo 1.26\n' > "$d/app/backend/go.mod"
expect_pass "layout roots: a go.mod backend is a backend root" "$d" sh "$CI/check-layout-roots.sh"
if (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "BACKEND_ROOT='app/backend'"; then
  pass "resolve-layout: app/backend/go.mod resolves as the backend root"
else
  fail "resolve-layout: app/backend/go.mod resolves as the backend root"
fi

d="$tmp/roots-cargo"
mkdir -p "$d/app/backend" "$d/.agents-v0/packs/rust"
printf '[package]\nname = "orders"\n' > "$d/app/backend/Cargo.toml"
cat > "$d/.agents-v0/packs/rust/pack.json" <<'EOF'
{"id":"rust","detect":["Cargo.toml"]}
EOF
expect_pass "layout roots: a Cargo.toml pack marker is a backend root" "$d" sh "$CI/check-layout-roots.sh"
if (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "BACKEND_ROOT='app/backend'"; then
  pass "resolve-layout: Cargo.toml resolves as the backend root"
else
  fail "resolve-layout: Cargo.toml resolves as the backend root"
fi

# activate-stack-pack.sh
act="$KIT/templates/.agents-v0/scripts/activate-stack-pack.sh"
d="$tmp/activate-java"
mkdir -p "$d/docs/agents-v0" "$d/app/backend"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
printf '<project/>\n' > "$d/app/backend/pom.xml"
expect_pass "activate-stack-pack --detect binds java" "$d" sh "$act" --detect
grep -Fq '| Pack | java |' "$d/docs/agents-v0/project-profile.md" \
  && pass "activate-stack-pack writes the Pack row" || fail "activate-stack-pack writes the Pack row"
expect_fail "activate-stack-pack refuses to replace java with go" "$d" sh "$act" go
d="$tmp/activate-ambiguous"
mkdir -p "$d/docs/agents-v0"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
printf '<project/>\n' > "$d/pom.xml"
printf 'module example.com/orders\n\ngo 1.26\n' > "$d/go.mod"
if (cd "$d" && sh "$act" --detect) >/dev/null 2>&1; then
  fail "activate-stack-pack --detect rejects two backend markers (expected non-zero)"
else
  pass "activate-stack-pack --detect rejects two backend markers"
fi
d="$tmp/activate-service-only"
mkdir -p "$d/docs/agents-v0" "$d/app/backend"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
sedi 's/| Profile | <!-- service, ui, or app --> |/| Profile | service |/' "$d/docs/agents-v0/project-profile.md"
sedi 's/| Backend root | <!-- `app\/backend\/` or n\/a --> |/| Backend root | `app\/backend\/` |/' "$d/docs/agents-v0/project-profile.md"
sedi 's/| Frontend root | <!-- `app\/frontend\/` or n\/a --> |/| Frontend root | n\/a |/' "$d/docs/agents-v0/project-profile.md"
expect_pass "activate-stack-pack binds dotnet on a service-only profile" "$d" sh "$act" dotnet
if grep -Fq '| Frontend verify | npm run verify |' "$d/docs/agents-v0/project-profile.md"; then
  fail "activate-stack-pack must not populate Frontend verify when Profile is service"
else
  pass "activate-stack-pack skips Frontend verify when Profile is service"
fi
d="$tmp/activate-app-fe"
mkdir -p "$d/docs/agents-v0" "$d/app/backend" "$d/app/frontend"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
sedi 's/| Profile | <!-- service, ui, or app --> |/| Profile | app |/' "$d/docs/agents-v0/project-profile.md"
sedi 's/| Backend root | <!-- `app\/backend\/` or n\/a --> |/| Backend root | `app\/backend\/` |/' "$d/docs/agents-v0/project-profile.md"
sedi 's/| Frontend root | <!-- `app\/frontend\/` or n\/a --> |/| Frontend root | `app\/frontend\/` |/' "$d/docs/agents-v0/project-profile.md"
expect_pass "activate-stack-pack binds dotnet on an app profile" "$d" sh "$act" dotnet
grep -Fq '| Frontend verify | cd app/frontend && npm run verify |' "$d/docs/agents-v0/project-profile.md" \
  && pass "activate-stack-pack prefixes Frontend root on Frontend verify" || fail "activate-stack-pack prefixes Frontend root on Frontend verify"
d="$tmp/activate-rollback"
mkdir -p "$d/docs/agents-v0" "$d/app/backend" "$d/.cursor/rules/org"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
printf 'pre-existing rule\n' > "$d/.cursor/rules/org/pre-existing.mdc"
printf 'blocking\n' > "$d/.cursor/skills"
expect_fail "activate-stack-pack rolls back and fails when cursor install fails" "$d" sh "$act" dotnet
[ -f "$d/.cursor/rules/org/pre-existing.mdc" ] \
  && pass "activate-stack-pack rollback preserves existing rules on failure" || fail "activate-stack-pack rollback preserves existing rules on failure"
grep -Fq '<!-- pack id;' "$d/docs/agents-v0/project-profile.md" \
  && pass "activate-stack-pack leaves profile unmutated on failure" || fail "activate-stack-pack leaves profile unmutated on failure"
d="$tmp/activate-hooks-ro"
mkdir -p "$d/docs/agents-v0" "$d/app/backend" "$d/.cursor/rules/org" "$d/.cursor/skills/spec-intake" "$d/.cursor/agents" "$d/.cursor/hooks"
cp "$KIT/templates/docs/agents-v0/project-profile.md" "$d/docs/agents-v0/project-profile.md"
printf 'shared rule\n' > "$d/.cursor/rules/org/workflow-orchestration.mdc"
printf 'shared skill\n' > "$d/.cursor/skills/spec-intake/SKILL.md"
printf 'shared agent\n' > "$d/.cursor/agents/solution-architect.md"
chmod 500 "$d/.cursor/hooks"
expect_fail "activate-stack-pack fails cleanly when .cursor/hooks is read-only" "$d" sh "$act" java
chmod 755 "$d/.cursor/hooks"
[ -f "$d/.cursor/rules/org/workflow-orchestration.mdc" ] && [ -f "$d/.cursor/skills/spec-intake/SKILL.md" ] && [ -f "$d/.cursor/agents/solution-architect.md" ] \
  && pass "activate-stack-pack failure on .cursor/hooks preserves shared .cursor rules, skills, and agents" \
  || fail "activate-stack-pack failure on .cursor/hooks preserves shared .cursor rules, skills, and agents"
expect_pass "activate-stack-pack succeeds on retry after .cursor/hooks is writable" "$d" sh "$act" java
[ -f "$d/.cursor/rules/org/workflow-orchestration.mdc" ] && [ -f "$d/.cursor/skills/spec-intake/SKILL.md" ] && [ -f "$d/.cursor/agents/solution-architect.md" ] \
  && pass "activate-stack-pack retry keeps shared .cursor files intact" \
  || fail "activate-stack-pack retry keeps shared .cursor files intact"
chmod 500 "$d/.cursor/hooks"
expect_pass "activate-stack-pack re-bind skips unchanged .cursor/hooks/pack-scan.sh when read-only" "$d" sh "$act" java
chmod 755 "$d/.cursor/hooks"

link="$tmp/link-project"
mkdir -p "$link"
git -C "$link" init -q
pin_commit="$(git -C "$KIT" rev-parse HEAD)"
expect_pass "link-project pins a kit checkout" "$link" sh "$KIT/scripts/link-project.sh" --path "$KIT" --commit "$pin_commit" "$link"
expect_pass "resolve-kit-root prints the pinned kit" "$link" sh .agents-v0/scripts/resolve-kit-root.sh
[ -L "$link/.agents-v0/ci/packlib.py" ] && pass "link-project symlinks kit CI" || fail "link-project symlinks kit CI"
[ ! -f "$link/.agents-v0/packs/java/pack.json" ] && pass "link-project does not copy example packs" || fail "link-project does not copy example packs"

# --- check-layout-roots.sh ---------------------------------------------------
d="$tmp/roots-unknown"
mkdir -p "$d/app"
: > "$d/app/pom.xml"
expect_fail "layout roots: a pom outside every known root fails" "$d" sh "$CI/check-layout-roots.sh"

d="$tmp/roots-profile"
mkdir -p "$d/app" "$d/docs/agents-v0"
: > "$d/app/pom.xml"
printf '| This repo | Value |\n|---|---|\n| Backend root | app |\n' > "$d/docs/agents-v0/project-profile.md"
expect_pass "layout roots: a profile row that names the module passes" "$d" sh "$CI/check-layout-roots.sh"

d="$tmp/roots-backend"
mkdir -p "$d/backend"
: > "$d/backend/pom.xml"
expect_pass "layout roots: backend/ is detected" "$d" sh "$CI/check-layout-roots.sh"

d="$tmp/roots-app-backend"
mkdir -p "$d/app/backend" "$d/app/frontend"
: > "$d/app/backend/pom.xml"
printf '{}\n' > "$d/app/frontend/package.json"
expect_pass "layout roots: app/backend/ is detected" "$d" sh "$CI/check-layout-roots.sh"
if (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "BACKEND_ROOT='app/backend'"; then
  pass "layout roots: app/backend resolves as the backend root"
else
  fail "layout roots: app/backend resolves as the backend root"
fi
if (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "FRONTEND_ROOT='app/frontend'"; then
  pass "layout roots: app/frontend resolves as the frontend root"
else
  fail "layout roots: app/frontend resolves as the frontend root"
fi

d="$tmp/roots-services"
mkdir -p "$d/services/order"
: > "$d/services/order/pom.xml"
expect_pass "layout roots: services/*/ is detected" "$d" sh "$CI/check-layout-roots.sh"

d="$tmp/roots-frontend-only"
mkdir -p "$d/frontend"
printf '{}\n' > "$d/frontend/package.json"
expect_pass "layout roots: a repo with no JVM module passes" "$d" sh "$CI/check-layout-roots.sh"

d="$tmp/roots-node-root"
mkdir -p "$d"
printf '{"name":"orders","dependencies":{"@nestjs/core":"10.0.0"}}\n' > "$d/package.json"
if (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "BACKEND_ROOT='\.'" && (cd "$d" && sh "$CI/resolve-layout.sh") | grep -q "FRONTEND_ROOT=''"; then
  pass "resolve-layout: a root NestJS package.json resolves BACKEND_ROOT=. and FRONTEND_ROOT=''"
else
  fail "resolve-layout: a root NestJS package.json resolves BACKEND_ROOT=. and FRONTEND_ROOT=''"
fi

d="$tmp/roots-ignored"
mkdir -p "$d/frontend/node_modules/x"
printf '{}\n' > "$d/frontend/package.json"
: > "$d/frontend/node_modules/x/pom.xml"
expect_pass "layout roots: node_modules is not scanned" "$d" sh "$CI/check-layout-roots.sh"

# --- roadmap row and material ARC -------------------------------------------
d="$tmp/arc"
mkdir -p "$d/docs/agents-v0/roadmap" "$d/docs/agents-v0/milestones" "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/design/system"
cat > "$d/docs/agents-v0/roadmap/claims.md" <<'EOF'
# Roadmap

Discovery: notes/discovery.md

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/claims.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/milestones/m.md" <<'EOF'
# Milestone: M

Roadmap: docs/agents-v0/roadmap/claims.md

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| M-A | As a user, I want a, so that b. | docs/agents-v0/requirements/a.md | planned | — | backend | 1 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/m.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/requirements/a.md" <<'EOF'
# A

Material: no

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/a.md | dev | Approved | 2026-01-01 |
EOF
expect_pass "check-approvals accepts the roadmap row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/roadmap/claims.md roadmap
expect_pass "check-milestone accepts a manifest that names an approved roadmap" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake

# --- check-roadmap.sh tests ------------------------------------------------
mkdir -p "$d/docs/product"
cat > "$d/docs/product/claims-discovery.md" <<'EOF'
# Claims Discovery
## Problem
Slow batch claim adjudication.
## **Success Metrics**
Adjudication time under 15 minutes.
## Options
### Option A: In-memory queue
Single-node queue for batch processing.
### Option B: Event stream
Partitioned log for high-throughput streams.
## Chosen option
Option A.
## In scope
- Batch file ingestion
- Adjudication rules engine
- **Ticketed Configuration Lifecycle:**
  - Create and validate configuration tickets
  - Audit trail for configuration changes
- **Ingestion Modes:**
  - Scheduled CSV batch import
  - Real-time webhook ingestion
## Out of scope
- Real-time mobile push notifications
EOF
expect_pass "check-roadmap preflight accepts normalized ## **Success Metrics** and ### subheadings" "$d" sh "$CI/check-roadmap.sh" --preflight docs/product/claims-discovery.md
expect_fail "check-roadmap preflight rejects unfilled discovery _template.md" "$d" sh "$CI/check-roadmap.sh" --preflight "$KIT/templates/docs/agents-v0/discovery/_template.md"

cat > "$d/docs/product/claims-discovery-placeholder.md" <<'EOF'
# Claims Discovery
## Problem
Slow batch claim adjudication.
## Success metric
Target is a couple of XX MB latency.
## Options
Option A.
## Chosen option
Option A.
## In scope
- Item 1
## Out of scope
- Item 2
EOF
expect_fail "check-roadmap preflight rejects XX placeholder" "$d" sh "$CI/check-roadmap.sh" --preflight docs/product/claims-discovery-placeholder.md

disc_hash="$(python3 -c 'import hashlib, sys; sys.stdout.write(hashlib.sha256(open("'$d'/docs/product/claims-discovery.md", "rb").read()).hexdigest())')"
cat > "$d/docs/agents-v0/roadmap/claims-unapproved.md" <<EOF
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)

## Problem
Slow batch claim adjudication.

## Success metric
Adjudication time under 15 minutes.

## Chosen option
Option A.

## Now
- Batch file ingestion
- Scheduled CSV batch import

## Next
- Adjudication rules engine
- Real-time webhook ingestion

## Later
- **Ticketed Configuration Lifecycle:**
  - Create and validate configuration tickets
  - Audit trail for configuration changes

## Out of scope
- Real-time mobile push notifications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
expect_pass "check-roadmap validates pre-approval roadmap content gate without Approved row" "$d" sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/claims-unapproved.md
expect_fail "check-roadmap --approved rejects roadmap missing Approved row" "$d" sh "$CI/check-roadmap.sh" --approved docs/agents-v0/roadmap/claims-unapproved.md

cat > "$d/docs/agents-v0/roadmap/claims-valid.md" <<EOF
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)

## Problem
Slow batch claim adjudication.

## Success metric
Adjudication time under 15 minutes.

## Chosen option
Option A.

## Now
- Batch file ingestion
- **Ingestion Modes:**
  - Scheduled CSV batch import

## Next
- Adjudication rules engine
- **Ingestion Modes:**
  - Real-time webhook ingestion

## Later
- Create and validate configuration tickets
- Audit trail for configuration changes

## Out of scope
- Real-time mobile push notifications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/claims-valid.md, docs/product/claims-discovery.md | dev | Approved | 2026-01-01 |
EOF
expect_pass "check-roadmap validates partitioned roadmap with matching sha256 and nested bullets" "$d" sh "$CI/check-roadmap.sh" --approved docs/agents-v0/roadmap/claims-valid.md

cat > "$d/docs/agents-v0/roadmap/claims-invented.md" <<EOF
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: $disc_hash)

## Now
- Batch file ingestion

## Next
- Adjudication rules engine (follow-on theme)

## Later

## Out of scope
- Real-time mobile push notifications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/claims-invented.md, docs/product/claims-discovery.md | dev | Approved | 2026-01-01 |
EOF
expect_fail "check-roadmap rejects invented item in horizon" "$d" sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/claims-invented.md

cat > "$d/docs/agents-v0/roadmap/claims-hash-mismatch.md" <<'EOF'
# Roadmap: claims

Discovery: docs/product/claims-discovery.md (sha256: 0000000000000000000000000000000000000000000000000000000000000000)

## Now
- Batch file ingestion

## Next
- Adjudication rules engine

## Later

## Out of scope
- Real-time mobile push notifications

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/claims-hash-mismatch.md, docs/product/claims-discovery.md | dev | Approved | 2026-01-01 |
EOF
expect_fail "check-roadmap rejects hash mismatch when discovery document changed" "$d" sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/claims-hash-mismatch.md

# Pre-sha256 sealed roadmap committed in git passes with warning; editing or re-opening enforces strict check
d_legacy_rm="$tmp/roadmap-legacy-git"
mkdir -p "$d_legacy_rm/docs/product" "$d_legacy_rm/docs/agents-v0/roadmap"
cp "$d/docs/product/claims-discovery-placeholder.md" "$d_legacy_rm/docs/product/disc.md"
cat > "$d_legacy_rm/docs/agents-v0/roadmap/legacy.md" <<'EOF'
# Roadmap: legacy

Discovery: docs/product/disc.md

## Now
- Summarized horizon bullet from earlier kit

## Next

## Later

## Out of scope
- Item 2

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/legacy.md, docs/product/disc.md | dev | Approved | 2026-01-01 |
EOF
(
  cd "$d_legacy_rm"
  git init -q
  git add docs/product/disc.md docs/agents-v0/roadmap/legacy.md
  git_commit "docs: legacy approved roadmap"
)
expect_pass "check-roadmap tolerates pre-sha256 Approved roadmap committed and clean in git" "$d_legacy_rm" sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/legacy.md
expect_fail "check-roadmap KIT_STRICT_ROADMAP=1 rejects pre-sha256 roadmap with horizon mismatch" "$d_legacy_rm" env KIT_STRICT_ROADMAP=1 sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/legacy.md
printf '\n<!-- edit -->\n' >> "$d_legacy_rm/docs/agents-v0/roadmap/legacy.md"
expect_fail "check-roadmap enforces strict check when pre-sha256 roadmap is edited on disk" "$d_legacy_rm" sh "$CI/check-roadmap.sh" docs/agents-v0/roadmap/legacy.md

expect_pass "check-arc ignores a story that is not material" "$d" sh "$CI/check-arc.sh" docs/agents-v0/requirements/a.md
printf 'Material: yes\nARC: docs/agents-v0/design/system/arc-record.md\n' > "$d/docs/agents-v0/requirements/a.md"
expect_fail "check-arc fails a material story with no ARC record" "$d" sh "$CI/check-arc.sh" docs/agents-v0/requirements/a.md
mkdir -p "$d/docs/agents-v0"
cat > "$d/docs/agents-v0/design/system/arc-record.md" <<'EOF'
# ARC record

## Fitness functions

| Name | Target | Evidence |
|------|--------|----------|
| checkout | p95 under 300ms | slo-evidence |
EOF
cat > "$d/docs/agents-v0/architecture.md" <<'EOF'
# Architecture

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md | dev | Approved | 2026-01-01 |
EOF
expect_pass "check-arc accepts an architecture row that names the ARC file" "$d" sh "$CI/check-arc.sh" docs/agents-v0/requirements/a.md
cat > "$d/docs/agents-v0/design/system/arc-record.md" <<'EOF'
# ARC record

## Fitness functions

| Name | Target | Evidence |
|------|--------|----------|
| checkout | p95 under 300ms | slo-evidence |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| arc | docs/agents-v0/design/system/arc-record.md | dev | Approved | 2026-01-02 |
EOF
expect_pass "check-arc accepts an approved ARC record" "$d" sh "$CI/check-arc.sh" docs/agents-v0/requirements/a.md
expect_pass "check-approvals accepts the arc row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/design/system/arc-record.md arc
write_pack "$d"
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-pattern.md"
cat >> "$d/docs/agents-v0/architecture.md" <<'EOF'

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md | dev | Approved | 2026-01-01 |
EOF
printf '\nArchitecture: docs/agents-v0/architecture.md\n' >> "$d/docs/agents-v0/milestones/m.md"
cat >> "$d/docs/agents-v0/requirements/a.md" <<'EOF'

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/a.md | dev | Approved | 2026-01-01 |
EOF
expect_pass "check-approvals accepts the architecture row" "$d" sh "$CI/check-approvals.sh" docs/agents-v0/architecture.md architecture
expect_pass "check-milestone accepts a manifest that names an approved architecture pack" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake

# --- check-intake.sh ---------------------------------------------------------
d="$tmp/intake"
mkdir -p "$d/docs/agents-v0/requirements" "$d/docs/agents-v0/milestones"
cat > "$d/docs/agents-v0/milestones/p2.md" <<'EOF'
| P2-A | As a clerk, I want to place an order, so that stock is reserved. |
EOF
cat > "$d/docs/agents-v0/requirements/orders.md" <<'EOF'
# Orders

As a clerk, I want to place an order, so that stock is reserved.

Milestone: P2
Milestone file: docs/agents-v0/milestones/p2.md
Story: P2-A
Surfaces: backend
Material: no

## Preconditions
The clerk is signed in and fixture CUST-1 exists.

## Desk check
Call POST /api/v1/orders with fixture CUST-1 and confirm the order row.

## Acceptance criteria

### AC-1 — place the order
Kind: happy
Given a signed-in clerk and fixture CUST-1
When the clerk places an order for SKU-1
Then HTTP 201 and the order row is stored with status PENDING

### AC-2 — reject an unsigned clerk
Kind: negative
Given no session for fixture CUST-1
When the clerk places an order
Then HTTP 401 and no order row is written

## Out of scope
- Mobile checkout

## NFRs
The place-order call returns within two seconds for fixture CUST-1.

## Regulations
N/A: no personal data beyond the customer id already stored.

## Security-review triggers
- auth: the clerk must be signed in

## Open questions
none
EOF
expect_pass "check-intake accepts a story with a refusing negative" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/orders.md
cp "$d/docs/agents-v0/requirements/orders.md" "$d/docs/agents-v0/requirements/plain.md"
sedi 's/Call POST.*/Sign in as the clerk and place one order for the customer./' "$d/docs/agents-v0/requirements/plain.md"
sedi 's/Then HTTP 201 and the order row is stored with status PENDING/Then the clerk sees the confirmation./' "$d/docs/agents-v0/requirements/plain.md"
expect_pass "check-intake accepts a plain desk check and Then" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/plain.md
sedi 's/Then the clerk sees the confirmation./Then nope/' "$d/docs/agents-v0/requirements/plain.md"
expect_fail "check-intake rejects a Then that is only a stub" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/plain.md
sedi 's/Kind: negative/Kind: happy/' "$d/docs/agents-v0/requirements/orders.md"
expect_fail "check-intake rejects a security trigger without a refusal" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/orders.md
sedi 's/Kind: happy/Kind: negative/' "$d/docs/agents-v0/requirements/orders.md"
sedi 's/Then HTTP 201 and the order row is stored with status PENDING/Then it works as expected/' "$d/docs/agents-v0/requirements/orders.md"
expect_fail "check-intake rejects a vague Then" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/orders.md
sedi 's/Then it works as expected/Then HTTP 201 and the order row is stored with status PENDING/' "$d/docs/agents-v0/requirements/orders.md"
printf 'Story: P0-A\n' > "$d/docs/agents-v0/requirements/p0.md"
expect_pass "check-intake skips P0-A" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/p0.md
cp "$d/docs/agents-v0/requirements/orders.md" "$d/docs/agents-v0/requirements/an_role.md"
sedi 's/As a clerk/As an API consumer/' "$d/docs/agents-v0/requirements/an_role.md"
expect_pass "check-intake accepts an As an role sentence" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/an_role.md
cp "$d/docs/agents-v0/requirements/orders.md" "$d/docs/agents-v0/requirements/no_trigger.md"
sedi 's/- auth: the clerk must be signed in/This story does not change authentication, RBAC, or a public route./' "$d/docs/agents-v0/requirements/no_trigger.md"
sedi 's/Then HTTP 401 and no order row is written/Then the order is placed on hold instead of failing/' "$d/docs/agents-v0/requirements/no_trigger.md"
expect_pass "check-intake does not require refusal when trigger words appear in a negative explanation" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/no_trigger.md

# --- check-architecture-pack.sh ----------------------------------------------
d="$tmp/pack"
write_pack "$d"
expect_pass "check-architecture-pack accepts a complete pack" "$d" sh "$CI/check-architecture-pack.sh"
expect_fail "check-architecture-pack --approved needs an Accepted pattern ADR" "$d" sh "$CI/check-architecture-pack.sh" --approved
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-pattern.md"
expect_pass "check-architecture-pack --approved accepts an Accepted pattern ADR" "$d" sh "$CI/check-architecture-pack.sh" --approved

d="$tmp/pack-tech"
write_pack "$d"
sedi 's/MessageBus\[Message bus\]/MessageBus[Kafka topic]/' "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack rejects a product name in C4" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-go"
write_pack "$d"
sedi 's/OrderService\[Order service\]/OrderService[Go service]/' "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack rejects Go in C4" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-node-word"
write_pack "$d"
sedi 's/OrderService\[Order service\]/OrderService[order node]/' "$d/docs/agents-v0/architecture.md"
expect_pass "check-architecture-pack allows the word node" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-fastapi"
write_pack "$d"
sedi 's/OrderService\[Order service\]/OrderService[FastAPI service]/' "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack rejects FastAPI in C4" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-nopack"
write_pack "$d"
sedi '/^Pack: java$/d' "$d/docs/agents-v0/adr/01-pattern.md"
expect_fail "check-architecture-pack requires Pack on the pattern ADR" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-rust"
write_pack "$d"
sedi 's/^Pack: java$/Pack: rust/' "$d/docs/agents-v0/adr/01-pattern.md"
expect_fail "check-architecture-pack rejects a stack with no pack" "$d" sh "$CI/check-architecture-pack.sh"
rust="$d/.agents-v0/packs/rust"
mkdir -p "$rust/rules" "$rust/skills/implement-service" "$rust/skills/implement-bff"
printf '%s\n' '---' 'description: rust backend' '---' '# backend' > "$rust/rules/backend.mdc"
printf '%s\n' '# implement-service' > "$rust/skills/implement-service/SKILL.md"
printf '%s\n' '# implement-bff' > "$rust/skills/implement-bff/SKILL.md"
cat > "$rust/pack.json" <<'EOF'
{
  "id": "rust",
  "verify": "cargo test",
  "verifyFast": "cargo test",
  "coverage": {"path": "coverage.xml", "format": "cobertura"},
  "testsReport": {"path": "junit.xml", "format": "junit"},
  "cve": {"path": "cve-report.json"},
  "authMarker": "auth",
  "publicMarker": "public",
  "migrationTool": "sqlx",
  "ciImage": "rust:1",
  "endpoints": [{"suffix": ".rs", "mapping": "#\\[(get|post)\\]\\(\"([^\"]+)\"\\)", "security": "auth|public", "name": "rust"}]
}
EOF
expect_pass "check-architecture-pack accepts a complete custom pack" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/"cobertura"/"llvm"/' "$rust/pack.json"
expect_fail "check-architecture-pack rejects an unmeasured coverage format" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/"llvm"/"cobertura"/' "$rust/pack.json"
python3 - "$rust/pack.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["ui"] = "nonexistent"
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
expect_fail "check-architecture-pack rejects a pack with missing UI manifest" "$d" sh "$CI/check-architecture-pack.sh"
python3 - "$rust/pack.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["ui"] = "react"
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
expect_pass "check-architecture-pack accepts a pack with valid UI manifest" "$d" sh "$CI/check-architecture-pack.sh"
python3 - "$rust/pack.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["ui"] = {"id": "react"}
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
expect_fail "check-architecture-pack rejects an incomplete inlined UI manifest" "$d" sh "$CI/check-architecture-pack.sh"
python3 - "$rust/pack.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
data["ui"] = {
    "id": "react",
    "stack": "React",
    "verify": "npm run verify",
    "verifyFast": "npm test",
    "layout": "src/",
    "coverage": {"path": "coverage/coverage-summary.json", "format": "jest-summary"},
}
json.dump(data, open(sys.argv[1], "w"), indent=2)
PY
expect_pass "check-architecture-pack accepts a complete inlined UI manifest" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-topology"
write_pack "$d"
python3 - "$d/docs/agents-v0/architecture.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
flow = text.index("## Data flow")
head, tail = text[:flow], text[flow:]
tail = tail.replace("OrderService", "BillingService", 1)
open(path, "w", encoding="utf-8").write(head + tail)
PY
expect_fail "check-architecture-pack rejects a Data flow with other nodes than C4 Container" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-placeholder"
write_pack "$d"
python3 - "$d/docs/agents-v0/architecture.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"### Logical\n\n```mermaid.*?```\n", "### Logical\n\n<!-- fill me -->\n", text, flags=re.S)
open(path, "w", encoding="utf-8").write(text)
PY
expect_fail "check-architecture-pack rejects an empty Logical data model" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's|<!-- fill me -->|N/A: the system keeps no state of its own.|' "$d/docs/agents-v0/architecture.md"
expect_pass "check-architecture-pack accepts N/A with a reason" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's|N/A: the system keeps no state of its own.|N/A: no|' "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack rejects N/A without a reason" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-review"
write_pack "$d"
rm "$d/docs/agents-v0/design/system/architecture-review.md"
expect_fail "check-architecture-pack needs the independent review" "$d" sh "$CI/check-architecture-pack.sh"
expect_pass "check-architecture-pack --without-review passes without the independent review" "$d" sh "$CI/check-architecture-pack.sh" --without-review
write_pack "$d"
printf '| 2 | Critical | no failure row for the bus | architecture.md | Open |\n' >> "$d/docs/agents-v0/design/system/architecture-review.md"
expect_fail "check-architecture-pack rejects an open Critical review finding" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/| Critical | no failure row for the bus | architecture.md | Open |/| Critical | no failure row for the bus | architecture.md | Resolved |/' "$d/docs/agents-v0/design/system/architecture-review.md"
expect_pass "check-architecture-pack accepts a Resolved Critical" "$d" sh "$CI/check-architecture-pack.sh"
printf '| 3 | Suggestion | clarify timeout retry | architecture.md | Open |\n' >> "$d/docs/agents-v0/design/system/architecture-review.md"
expect_fail "check-architecture-pack rejects an Open Suggestion review finding" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/| Suggestion | clarify timeout retry | architecture.md | Open |/| Suggestion | clarify timeout retry | architecture.md | Deferred |/' "$d/docs/agents-v0/design/system/architecture-review.md"
expect_pass "check-architecture-pack accepts a Deferred Suggestion" "$d" sh "$CI/check-architecture-pack.sh"

# pack-hash verification and post-approval ADR status prose in architecture-review.md
phash="$(cd "$d" && sh "$CI/check-architecture-pack.sh" --hash | cut -c1-12)"
cat > "$d/docs/agents-v0/design/system/architecture-review.md" <<EOF
agent: design-reviewer
pack-hash: 000000000000

| # | Label | Finding | Evidence | Status |
|---|-------|---------|----------|--------|
| 1 | Suggestion | name the retry budget | architecture.md | Resolved |
EOF
expect_fail "check-architecture-pack rejects stale pack-hash in architecture-review.md" "$d" sh "$CI/check-architecture-pack.sh"
sedi "s/pack-hash: 000000000000/pack-hash: $phash/" "$d/docs/agents-v0/design/system/architecture-review.md"
expect_pass "check-architecture-pack accepts matching pack-hash in architecture-review.md" "$d" sh "$CI/check-architecture-pack.sh"
printf '\nJudgment: ADR 0001 is Proposed and sound.\n' >> "$d/docs/agents-v0/design/system/architecture-review.md"
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-pattern.md"
expect_fail "check-architecture-pack --approved rejects review judgment still calling ADR Proposed" "$d" sh "$CI/check-architecture-pack.sh" --approved
sedi 's/ADR 0001 is Proposed/ADR 0001 is Accepted/' "$d/docs/agents-v0/design/system/architecture-review.md"
expect_pass "check-architecture-pack --approved accepts review judgment updated to Accepted (and pack-hash survives ADR approval flip)" "$d" sh "$CI/check-architecture-pack.sh" --approved

d="$tmp/pack-fitness"
write_pack "$d"
sedi 's/| no module cycles | ArchUnit rule | zero cycles | block merge |/| <e.g. rule> | <e.g. check> | <e.g. threshold> | <e.g. action> |/' "$d/docs/agents-v0/design/system/arc-record.md"
expect_fail "check-architecture-pack needs a structural fitness function row" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-component"
write_pack "$d"
sedi 's#N/A: single service in this release#docs/agents-v0/design/system/components/orders.md#' "$d/docs/agents-v0/design/system/context-map.md"
expect_fail "check-architecture-pack needs the component plan file a context names" "$d" sh "$CI/check-architecture-pack.sh"
printf '# Component plan: orders\n\nParent: `docs/agents-v0/architecture.md`\n' > "$d/docs/agents-v0/design/system/components/orders.md"
expect_pass "check-architecture-pack accepts a component plan that links its parent" "$d" sh "$CI/check-architecture-pack.sh"
cat > "$d/docs/agents-v0/design/system/components/orders.md" <<'EOF'
# Component plan: orders

Parent: `docs/agents-v0/architecture.md`

## Consistency check

- [ ] Names match `docs/agents-v0/adr/01-pattern.md` (Proposed).
EOF
expect_fail "check-architecture-pack rejects component plan with unchecked Consistency check box before approval" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/- \[ \]/- [x]/' "$d/docs/agents-v0/design/system/components/orders.md"
expect_pass "check-architecture-pack accepts component plan with (Proposed) and checked Consistency check before approval" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-pattern.md"
expect_fail "check-architecture-pack --approved rejects component plan labeling ADR (Proposed)" "$d" sh "$CI/check-architecture-pack.sh" --approved
sedi 's/(Proposed)/(Accepted)/' "$d/docs/agents-v0/design/system/components/orders.md"
sedi 's/- \[x\]/- [ ]/' "$d/docs/agents-v0/design/system/components/orders.md"
expect_fail "check-architecture-pack --approved rejects component plan with unchecked Consistency check box" "$d" sh "$CI/check-architecture-pack.sh" --approved
sedi 's/- \[ \]/- [x]/' "$d/docs/agents-v0/design/system/components/orders.md"
expect_pass "check-architecture-pack --approved accepts component plan with Accepted ADR and checked Consistency check" "$d" sh "$CI/check-architecture-pack.sh" --approved

# Sealed git-tracked Approved component plan with (Proposed) or - [ ] passes with warning only for legacy packs without pack-hash; pack-hash, editing, or KIT_STRICT_COMPONENT_PLAN=1 fails
cat >> "$d/docs/agents-v0/architecture.md" <<'EOF'

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/design/system/components/orders.md" <<'EOF'
# Component plan: orders

Parent: `docs/agents-v0/architecture.md`

## Consistency check

- [ ] Names match `docs/agents-v0/adr/01-pattern.md` (Proposed).
EOF
(
  cd "$d"
  git init -q
  git add -A && git_commit "docs: sealed approved architecture and component plan"
)
expect_pass "check-architecture-pack --approved tolerates legacy sealed git-tracked component plan without pack-hash" "$d" sh "$CI/check-architecture-pack.sh" --approved
expect_pass "check-architecture-pack tolerates legacy sealed git-tracked component plan without --approved" "$d" sh "$CI/check-architecture-pack.sh"
expect_fail "check-architecture-pack --approved KIT_STRICT_COMPONENT_PLAN=1 rejects sealed component plan with (Proposed)" "$d" env KIT_STRICT_COMPONENT_PLAN=1 sh "$CI/check-architecture-pack.sh" --approved
printf '\n<!-- edit -->\n' >> "$d/docs/agents-v0/design/system/components/orders.md"
expect_fail "check-architecture-pack --approved rejects sealed component plan once edited on disk" "$d" sh "$CI/check-architecture-pack.sh" --approved
(cd "$d" && git checkout -q -- docs/agents-v0/design/system/components/orders.md)
printf '\n<!-- arch edit -->\n' >> "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack requires pack-hash when git-tracked architecture.md is edited on disk" "$d" sh "$CI/check-architecture-pack.sh"
(cd "$d" && git checkout -q -- docs/agents-v0/architecture.md)
printf '| architecture | docs/agents-v0/architecture.md | dev | Re-opened | 2026-01-02 |\n' >> "$d/docs/agents-v0/architecture.md"
expect_fail "check-architecture-pack requires pack-hash when architecture row is Re-opened" "$d" sh "$CI/check-architecture-pack.sh"
(cd "$d" && git checkout -q -- docs/agents-v0/architecture.md)
phash_comp="$(cd "$d" && sh "$CI/check-architecture-pack.sh" --hash | cut -c1-12)"
cat > "$d/docs/agents-v0/design/system/architecture-review.md" <<EOF
agent: design-reviewer
pack-hash: $phash_comp

| # | Label | Finding | Evidence | Status |
|---|-------|---------|----------|--------|
| 1 | Suggestion | name the retry budget | architecture.md | Resolved |
EOF
(cd "$d" && git add -A && git_commit "docs: add pack-hash to review")
expect_fail "check-architecture-pack --approved rejects git-committed component plan with (Proposed) when review has pack-hash" "$d" sh "$CI/check-architecture-pack.sh" --approved

printf '# Component plan: orders\n' > "$d/docs/agents-v0/design/system/components/orders.md"
expect_fail "check-architecture-pack rejects a component plan with no parent link" "$d" sh "$CI/check-architecture-pack.sh"

d="$tmp/pack-milestone"
write_pack "$d"
sedi 's/Proposed/Accepted/' "$d/docs/agents-v0/adr/01-pattern.md"
mkdir -p "$d/docs/agents-v0/milestones" "$d/docs/agents-v0/requirements"
cat >> "$d/docs/agents-v0/architecture.md" <<'EOF'

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/requirements/a.md" <<'EOF'
# a

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/agents-v0/requirements/a.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/agents-v0/milestones/m.md" <<'EOF'
# m

Architecture: docs/agents-v0/architecture.md

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| M-A | As a clerk, I want x, so that y. | docs/agents-v0/requirements/a.md | todo | - |
EOF
expect_pass "check-milestone runs the pack check for an approved architecture row" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake
rm "$d/docs/agents-v0/design/system/ops-readiness.md"
expect_fail "check-milestone fails when the approved pack is incomplete" "$d" sh "$CI/check-milestone.sh" docs/agents-v0/milestones/m.md intake

# --- collect-gate-reports.sh fail-closed CVE & pip-audit format --------------
d="$tmp/cve-fail-closed"
mkdir -p "$d/.agents-v0/packs/python" "$d/docs/agents-v0"
cp "$KIT/core/python/pack.json" "$d/.agents-v0/packs/python/pack.json"
cat > "$d/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | python |
EOF
cat > "$d/coverage.xml" <<'EOF'
<coverage line-rate="0.90"><packages><package><classes><class filename="app.py"><lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>
EOF
cat > "$d/pytest-report.xml" <<'EOF'
<testsuite tests="1" failures="0" errors="0"><testcase classname="t" name="ok"/></testsuite>
EOF
# Run collect-gate-reports with PATH stripped of pip-audit so no scanner runs
expect_pass "collect-gate-reports succeeds when coverage and junit exist" "$d" env PATH="/usr/bin:/bin" sh "$CI/collect-gate-reports.sh" .
if [ -f "$d/ci-artifacts/gate/cve-report.json" ]; then
  fail "collect-gate-reports must not fabricate cve-report.json when no scanner ran"
else
  pass "collect-gate-reports does not fabricate cve-report.json when scanner is absent"
fi
expect_fail "check-gate-metrics with REQUIRE_CVE_REPORT=1 fails closed when no CVE report was produced" "$d" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh"

cat > "$d/cve-report.json" <<'EOF'
{"dependencies": [{"name": "urllib3", "version": "1.26.0", "vulns": [{"id": "PYSEC-2023-1", "fix_versions": ["1.26.18"]}]}]}
EOF
expect_pass "collect-gate-reports copies real pip-audit cve-report.json" "$d" sh "$CI/collect-gate-reports.sh" .
expect_fail "check-gate-metrics fails closed on pip-audit dependencies[].vulns[] entry" "$d" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh"

# Test Java collect-gate-reports invokes mvnw when pom.xml exists and cve.path is absent
dj="$tmp/java-cve-test"
mkdir -p "$dj/.agents-v0/ci" "$dj/.agents-v0/packs/java" "$dj/docs/agents-v0"
cp "$CI/"*.sh "$CI/"*.py "$dj/.agents-v0/ci/"
cp "$KIT/core/java/pack.json" "$dj/.agents-v0/packs/java/pack.json"
cat > "$dj/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | java |
EOF
cat > "$dj/pom.xml" <<'EOF'
<project></project>
EOF
cat > "$dj/mvnw" <<'EOF'
#!/bin/sh
mkdir -p target
cat > target/dependency-check-report.json <<'JEOF'
{"dependencies": [{"fileName": "log4j.jar", "vulnerabilities": []}]}
JEOF
EOF
chmod +x "$dj/mvnw"
expect_pass "collect-gate-reports invokes mvnw -Pci-security for java when report is absent" "$dj" sh "$CI/collect-gate-reports.sh" .
if [ -f "$dj/ci-artifacts/gate/target/dependency-check-report.json" ]; then
  pass "collect-gate-reports staged java dependency-check-report.json under ci-artifacts/gate/"
else
  fail "collect-gate-reports did not stage java dependency-check-report.json"
fi

# Stale ci-artifacts/gate CVE report must not pass REQUIRE_CVE_REPORT=1 when target/ was rebuilt without it
rm -f "$dj/target/dependency-check-report.json" "$dj/mvnw"
mkdir -p "$dj/target/surefire-reports" "$dj/target/site/jacoco"
printf '<testsuite tests="1" failures="0" errors="0" skipped="0"/>\n' > "$dj/target/surefire-reports/TEST-a.xml"
cat > "$dj/target/site/jacoco/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="x"><package name="com/acme"><sourcefile name="A.java"><line nr="3" mi="0" ci="1"/><counter type="LINE" missed="0" covered="1"/></sourcefile><counter type="LINE" missed="0" covered="1"/></package><counter type="LINE" missed="0" covered="1"/></report>
EOF
python3 - "$dj/ci-artifacts/gate/target/dependency-check-report.json" <<'PY'
import os, sys, time
old = time.time() - 3600
os.utime(sys.argv[1], (old, old))
PY
expect_fail "check-gate-metrics rejects stale ci-artifacts/gate CVE report when module build is newer" "$dj" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" .
expect_pass "collect-gate-reports purges stale ci-artifacts/gate files when scanner is absent" "$dj" env PATH="/usr/bin:/bin" sh "$CI/collect-gate-reports.sh" .
if [ -f "$dj/ci-artifacts/gate/target/dependency-check-report.json" ]; then
  fail "collect-gate-reports left stale dependency-check-report.json in ci-artifacts/gate/"
else
  pass "collect-gate-reports purged stale dependency-check-report.json from ci-artifacts/gate/"
fi

# Even if ci-artifacts/gate/target/dependency-check-report.json has a NEWER mtime than target/, Java live build must reject missing target/dependency-check-report.json
cat > "$dj/ci-artifacts/gate/target/dependency-check-report.json" <<'EOF'
{"dependencies": []}
EOF
expect_fail "check-gate-metrics rejects ci-artifacts/gate CVE report for java when target/dependency-check-report.json is absent even if gate copy is newer" "$dj" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" .

# When both target/ and ci-artifacts/gate/target/ have reports, tests must not be double-counted
mkdir -p "$dj/ci-artifacts/gate/target/surefire-reports"
cp "$dj/target/surefire-reports/TEST-a.xml" "$dj/ci-artifacts/gate/target/surefire-reports/TEST-a.xml"
cp "$dj/ci-artifacts/gate/target/dependency-check-report.json" "$dj/target/dependency-check-report.json"
out="$(cd "$dj" && env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" . 2>&1)"
if printf '%s\n' "$out" | grep -Fq "tests: run=1 "; then
  pass "check-gate-metrics does not double-count JUnit XML under ci-artifacts/gate/"
else
  fail "check-gate-metrics double-counted JUnit XML when ci-artifacts/gate/ was populated: $out"
fi

# DIFF_BASE=HEAD (checkout already on integration branch tip) falls back to feature baseCommit
mkdir -p "$tmp/gate-diff/docs/agents-v0/requirements" "$tmp/gate-diff/docs/agents-v0/build/orders"
cat > "$tmp/gate-diff/docs/agents-v0/requirements/orders.state.json" <<EOF
{"feature":"orders","activePhase":"verify","baseCommit":"$diff_base"}
EOF
expect_fail "gate metrics: DIFF_BASE=HEAD on main falls back to state baseCommit and measures diff coverage" "$tmp/gate-diff" env DIFF_BASE=HEAD sh "$CI/check-gate-metrics.sh" .

# When baseCommit equals the code commit (e.g. stamped after code commit on main) and doc-only commits follow, resolve_merge_base uses <report-commit>^
code_sha="$(cd "$tmp/gate-diff" && git log -1 --format=%H -- src/main/java/com/acme/A.java)"
cat > "$tmp/gate-diff/docs/agents-v0/build/orders/build-report.md" <<EOF
# Build Report — orders
commit: $code_sha
EOF
cat > "$tmp/gate-diff/docs/agents-v0/requirements/orders.state.json" <<EOF
{"feature":"orders","activePhase":"verify","baseCommit":"$code_sha"}
EOF
(
  cd "$tmp/gate-diff"
  git add docs/agents-v0/build/orders/build-report.md docs/agents-v0/requirements/orders.state.json
  git_commit "docs: record build report and state"
)
expect_fail "gate metrics: DIFF_BASE=HEAD on main with doc commits after build-report commit resolves <report-commit>^ and measures diff coverage" "$tmp/gate-diff" env DIFF_BASE=HEAD sh "$CI/check-gate-metrics.sh" .


# --- .gitlab-ci.yml build script multi-service execution ---------------------
d="$tmp/gitlab-build-sim"
mkdir -p "$d/.agents-v0/ci" "$d/.agents-v0/packs/node" "$d/docs/agents-v0" "$d/services/orders"
cp "$CI/"*.sh "$CI/"*.py "$d/.agents-v0/ci/"
cp "$KIT/core/node/pack.json" "$d/.agents-v0/packs/node/pack.json"
cat > "$d/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | node |

## Commands

| Purpose | Command |
|---------|---------|
| Service verify | cd {root} && echo "ran-service-verify" > verified.txt && mkdir -p coverage && printf '{"total":{"lines":{"pct":90}}}\n' > coverage/coverage-summary.json && printf '<testsuite tests="1" failures="0" errors="0"><testcase classname="t" name="ok"/></testsuite>\n' > junit.xml |
EOF
printf '{"name":"orders","dependencies":{"@nestjs/core":"10.0.0"}}\n' > "$d/services/orders/package.json"
python3 - "$KIT/templates/.gitlab-ci.yml" "$d/run-build.sh" <<'PY'
import sys, yaml
ci = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
script = "\n".join(ci["build"]["script"])
open(sys.argv[2], "w", encoding="utf-8").write(script + "\n")
PY
expect_pass ".gitlab-ci.yml build script executes Service verify across SERVICE_ROOTS and collects gate reports" "$d" env CI_PACK_IMAGE="node:22-bookworm" sh run-build.sh
if [ -f "$d/ci-artifacts/gate/services/orders/coverage/coverage-summary.json" ] && [ -f "$d/services/orders/verified.txt" ]; then
  pass ".gitlab-ci.yml build script staged coverage/coverage-summary.json under ci-artifacts/gate/services/orders/"
else
  fail ".gitlab-ci.yml build script did not stage per-service gate artifacts"
fi

# --- Sibling frontend CVE check when measuring app/backend -------------------
dfe="$tmp/app-fe-cve"
mkdir -p "$dfe/.agents-v0/ci" "$dfe/.agents-v0/packs/java" "$dfe/.agents-v0/ui/react" "$dfe/docs/agents-v0" "$dfe/app/backend/target/surefire-reports" "$dfe/app/backend/target/site/jacoco" "$dfe/app/frontend"
cp "$CI/"*.sh "$CI/"*.py "$dfe/.agents-v0/ci/"
cp "$KIT/core/java/pack.json" "$dfe/.agents-v0/packs/java/pack.json"
cp "$KIT/core/ui/react/pack.json" "$dfe/.agents-v0/ui/react/pack.json"
cat > "$dfe/docs/agents-v0/project-profile.md" <<'EOF'
## Stack

| Layer | Value |
|-------|--------|
| Pack | java |
EOF
printf '<project></project>\n' > "$dfe/app/backend/pom.xml"
printf '<testsuite tests="1" failures="0" errors="0" skipped="0"/>\n' > "$dfe/app/backend/target/surefire-reports/TEST-a.xml"
cat > "$dfe/app/backend/target/site/jacoco/jacoco.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<report name="x"><counter type="LINE" missed="0" covered="5"/></report>
EOF
printf '{"dependencies": []}\n' > "$dfe/app/backend/target/dependency-check-report.json"
printf '{"name":"app-frontend"}\n' > "$dfe/app/frontend/package.json"
cat > "$dfe/app/frontend/cve-report.json" <<'EOF'
{"vulnerabilities": {"tinypool": {"name": "tinypool", "severity": "critical"}}}
EOF
expect_fail "gate metrics: critical CVE in sibling app/frontend fails check-gate-metrics.sh app/backend" "$dfe" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" app/backend
cat > "$dfe/app/frontend/cve-report.json" <<'EOF'
{"vulnerabilities": {}}
EOF
expect_pass "gate metrics: clean sibling app/frontend CVE report passes check-gate-metrics.sh app/backend" "$dfe" env REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" app/backend

(
  cd "$dfe"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  git add -A && git_commit base
  mkdir -p app/backend/src/main/resources/db/migration app/backend/src/test/resources
  printf 'CREATE TABLE IF NOT EXISTS schema_marker (id INTEGER PRIMARY KEY);\n' > app/backend/src/main/resources/db/migration/V1__baseline.sql
  printf 'spring:\n  datasource:\n    url: jdbc:h2:mem:app;MODE=PostgreSQL\n' > app/backend/src/test/resources/application-test.yml
  git checkout -qb feature/p0-a
  git add -A && git_commit add_baseline_sql
)
expect_fail "gate metrics: app/backend V1__baseline.sql with H2-only and no root Compose fails" "$dfe" env DIFF_BASE=main MIN_DIFF_LINE_PCT=0 REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" app/backend
cat > "$dfe/docker-compose.yml" <<'EOF'
services:
  db:
    image: postgres:15-alpine
EOF
expect_pass "gate metrics: app/backend V1__baseline.sql with repo-root docker-compose.yml passes" "$dfe" env DIFF_BASE=main MIN_DIFF_LINE_PCT=0 REQUIRE_CVE_REPORT=1 sh "$CI/check-gate-metrics.sh" app/backend

# --- Build approval / state / phase-result / stamped-commit consistency ------
dp0="$tmp/p0-build-consistency"
mkdir -p "$dp0/docs/agents-v0/requirements" "$dp0/docs/agents-v0/design/p0-a-platform-skeleton" "$dp0/docs/agents-v0/build/p0-a-platform-skeleton" "$dp0/src"
cat > "$dp0/docs/agents-v0/design/p0-a-platform-skeleton/design.md" <<'EOF'
# Design: P0-A
EOF
(cd "$dp0" && printf '2026-10-19 %s approved\n' "$(sh "$CI/check-design.sh" p0-a-platform-skeleton --hash)" > docs/agents-v0/design/p0-a-platform-skeleton/design.lock)
cat > "$dp0/docs/agents-v0/requirements/p0-a-platform-skeleton.md" <<'EOF'
# P0-A — Platform Skeleton
Milestone: P0 — Platform Skeleton
Story: P0-A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| build | docs/agents-v0/build/p0-a-platform-skeleton/build-report.md | mdurana | Approved | 2026-10-19 |
EOF
(cd "$dp0" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md >/dev/null 2>&1)
expect_fail "check-feature-state rejects Approved build when intake and design rows are missing alongside design.lock" "$dp0" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md

cat > "$dp0/docs/agents-v0/requirements/p0-a-platform-skeleton.md" <<'EOF'
# P0-A — Platform Skeleton
Milestone: P0 — Platform Skeleton
Story: P0-A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p0-a-platform-skeleton.md | mdurana | Approved | 2026-10-19 |
| design | N/A: no /api/v1 operation, docs/agents-v0/design/p0-a-platform-skeleton/design.md | mdurana | Approved | 2026-10-19 |
| build | docs/agents-v0/build/p0-a-platform-skeleton/build-report.md | mdurana | Approved | 2026-10-19 |
EOF
cat > "$dp0/docs/agents-v0/requirements/p0-a-platform-skeleton.phase-result.md" <<'EOF'
phase: build
status: approved
EOF
(cd "$dp0" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md --active-phase verify --status in_progress >/dev/null 2>&1)
expect_fail "check-feature-state rejects story in two phases at once (phase-result build/approved vs state verify/in_progress)" "$dp0" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md
(cd "$dp0" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md >/dev/null 2>&1)
expect_pass "check-feature-state passes when intake+design+build are approved and sync-feature-state clears activePhase" "$dp0" sh "$CI/check-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md

# Stamped commit in build-report.md must not record state.json as in_progress or omit the build approval row
(
  cd "$dp0"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  # Simulate committing code while state is in_progress and approvals table is empty
  cat > docs/agents-v0/requirements/p0-a-platform-skeleton.md <<'EOF'
# P0-A — Platform Skeleton
Milestone: P0 — Platform Skeleton
Story: P0-A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
EOF
  sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md --active-phase build --status in_progress >/dev/null 2>&1
  printf 'class App {}\n' > src/App.java
  git add -A && git_commit "feat: code with in_progress state"
  bad_sha="$(git rev-parse HEAD)"
  cat > docs/agents-v0/build/p0-a-platform-skeleton/build-report.md <<EOF
commit: $bad_sha
EOF
  cat > docs/agents-v0/requirements/p0-a-platform-skeleton.md <<'EOF'
# P0-A — Platform Skeleton
Milestone: P0 — Platform Skeleton
Story: P0-A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p0-a-platform-skeleton.md | mdurana | Approved | 2026-10-19 |
| design | N/A: no /api/v1 operation, docs/agents-v0/design/p0-a-platform-skeleton/design.md | mdurana | Approved | 2026-10-19 |
| build | docs/agents-v0/build/p0-a-platform-skeleton/build-report.md | mdurana | Approved | 2026-10-19 |
EOF
  sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md >/dev/null 2>&1
  git add -A && git_commit "docs: add approval after stamped commit"
)
expect_fail "check-evidence rejects build-report whose stamped commit recorded state as build/in_progress and lacked the build row" "$dp0" sh "$CI/check-evidence.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md build
(
  cd "$dp0"
  # Now commit code with approved rows and cleared state first, then stamp build-report.md
  printf 'class App { int x; }\n' > src/App.java
  git add src/App.java docs/agents-v0/requirements/p0-a-platform-skeleton.md docs/agents-v0/requirements/p0-a-platform-skeleton.phase-result.md docs/agents-v0/requirements/p0-a-platform-skeleton.state.json
  git_commit "feat: code with approved build state"
  good_sha="$(git rev-parse HEAD)"
  cat > docs/agents-v0/build/p0-a-platform-skeleton/build-report.md <<EOF
commit: $good_sha
EOF
  git add docs/agents-v0/build/p0-a-platform-skeleton/build-report.md && git_commit "docs: stamp build-report"
)
expect_pass "check-evidence passes when stamped commit contains approved build row and cleared state" "$dp0" sh "$CI/check-evidence.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md build
(
  cd "$dp0"
  mkdir -p docs/agents-v0/verify/p0-a-platform-skeleton
  sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md --active-phase verify --status in_progress >/dev/null 2>&1
  printf 'class AppTest {}\n' > src/AppTest.java
  git add src/AppTest.java docs/agents-v0/requirements/p0-a-platform-skeleton.state.json
  git_commit "test: add verify test while verify is in_progress"
  verify_sha="$(git rev-parse HEAD)"
  cat > docs/agents-v0/verify/p0-a-platform-skeleton/test-report.md <<EOF
commit: $verify_sha
EOF
  printf '| verify | docs/agents-v0/verify/p0-a-platform-skeleton/test-report.md | mdurana | Approved | 2026-10-19 |\n' >> docs/agents-v0/requirements/p0-a-platform-skeleton.md
  git add docs/agents-v0/verify/p0-a-platform-skeleton/test-report.md docs/agents-v0/requirements/p0-a-platform-skeleton.md
  git_commit "docs: add verify report before syncing state"
)
expect_fail "check-evidence rejects verify report when HEAD still records activePhase=verify in_progress" "$dp0" sh "$CI/check-evidence.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md verify
(
  cd "$dp0"
  sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md >/dev/null 2>&1
  git add docs/agents-v0/requirements/p0-a-platform-skeleton.state.json
  git_commit "docs: sync state after verify approval"
)
expect_pass "check-evidence passes for verify report stamped on test commit once HEAD clears activePhase" "$dp0" sh "$CI/check-evidence.sh" docs/agents-v0/requirements/p0-a-platform-skeleton.md verify

if [ "$status" -ne 0 ]; then
  echo "test-ci-checks: FAILED" >&2
  exit 1
fi
echo "test-ci-checks: OK"
