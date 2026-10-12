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
trap 'rm -rf "$tmp"' EXIT INT TERM
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
| 1 | Suggestion | name the retry budget | architecture.md | Open |
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
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state2.md >/dev/null 2>&1)
if grep -Fq '"lastApprovedPhase": "intake"' "$d/docs/agents-v0/requirements/dec-state2.state.json"; then pass "state: a later Re-opened row withdraws an earlier Approved design"; else fail "state: a later Re-opened row withdraws an earlier Approved design"; fi
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
| 70 | x | @ada | 2027-01-01 |
EOF
expect_pass "gate metrics: one failure within a known_failures budget of 1 passes" "$kf" sh "$CI/check-gate-metrics.sh" "$m"
printf '<testsuite tests="2" failures="1" errors="0" skipped="0"/>\n' > "$m/target/surefire-reports/TEST-c.xml"
expect_fail "gate metrics: two failures exceed a known_failures budget of 1" "$kf" sh "$CI/check-gate-metrics.sh" "$m"
rm -f "$m/target/surefire-reports/TEST-b.xml" "$m/target/surefire-reports/TEST-c.xml"

# check-known-failures.sh: --require-failures after a verify that exited non-zero.
printf '[ERROR] Tests run: 3, Failures: 1, Errors: 0, Skipped: 0\n' > "$kf/one-failure.log"
printf '[ERROR] Tests run: 3, Failures: 2, Errors: 0, Skipped: 0\n' > "$kf/two-failures.log"
printf '[ERROR] COMPILATION ERROR : cannot find symbol\n' > "$kf/compile-error.log"
expect_pass "known failures: one failure within the budget passes with --require-failures" "$kf" sh "$CI/check-known-failures.sh" --require-failures one-failure.log
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

m="$tmp/gate-python"
mkdir -p "$m"
printf '[project]\nname = "orders"\n' > "$m/pyproject.toml"
printf '<testsuite tests="2" failures="0" errors="0" skipped="0"/>\n' > "$m/pytest-report.xml"
printf '<coverage line-rate="0.91"/>\n' > "$m/coverage.xml"
expect_pass "gate metrics: pytest and coverage.xml pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-go"
mkdir -p "$m"
printf 'module example.com/orders\n\ngo 1.26\n' > "$m/go.mod"
expect_fail "gate metrics: a Go module with no test report fails" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"
printf '%s\n' '{"Action":"pass","Package":"example.com/orders","Test":"TestPlace"}' > "$m/go-test.json"
printf 'mode: set\nexample.com/orders/a.go:1.1,2.2 1 1\n' > "$m/coverage.out"
expect_pass "gate metrics: go test json and coverage.out pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

m="$tmp/gate-dotnet"
mkdir -p "$m/TestResults"
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$m/Orders.csproj"
printf '<TestRun><ResultSummary><Counters total="1" executed="1" passed="1" failed="0"/></ResultSummary></TestRun>\n' > "$m/TestResults/test-results.trx"
printf '<coverage line-rate="0.88"/>\n' > "$m/coverage.cobertura.xml"
expect_pass "gate metrics: trx and cobertura pass" "$tmp" sh "$CI/check-gate-metrics.sh" "$m"

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
printf 'Story: P0-A\n' > "$d/docs/agents-v0/requirements/p0.md"
expect_pass "check-intake skips P0-A" "$d" sh "$CI/check-intake.sh" docs/agents-v0/requirements/p0.md

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
write_pack "$d"
printf '| 2 | Critical | no failure row for the bus | architecture.md | Open |\n' >> "$d/docs/agents-v0/design/system/architecture-review.md"
expect_fail "check-architecture-pack rejects an open Critical review finding" "$d" sh "$CI/check-architecture-pack.sh"
sedi 's/| Critical | no failure row for the bus | architecture.md | Open |/| Critical | no failure row for the bus | architecture.md | Resolved |/' "$d/docs/agents-v0/design/system/architecture-review.md"
expect_pass "check-architecture-pack accepts a Resolved Critical" "$d" sh "$CI/check-architecture-pack.sh"

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

if [ "$status" -ne 0 ]; then
  echo "test-ci-checks: FAILED" >&2
  exit 1
fi
echo "test-ci-checks: OK"
