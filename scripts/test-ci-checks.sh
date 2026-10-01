#!/bin/sh
# test-ci-checks.sh — behavior tests for the template CI scripts (no network).
# Covers: resolve-layout.sh (Service roots), check-attempt-budget.sh, check-approvals.sh (plan),
# check-milestone.sh (story order, SLO waivers), check-event-schemas.sh, check-gate-metrics.sh.
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
CI="$KIT/templates/ci"
SC="$KIT/templates/scripts"
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

git_commit() {
  git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$1"
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
mkdir -p "$d/docs"
cat > "$d/docs/project-profile.md" <<'EOF'
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
sed 's|services/a, services/b|../escape|' "$d/docs/project-profile.md" > "$d/docs/bad.md"
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
mkdir -p "$d/docs/milestones" "$d/docs/requirements"
cat > "$d/docs/milestones/m.md" <<'EOF'
# Milestone: M

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| M-A | As a user, I want a, so that b. | docs/requirements/a.md | planned | — |
| M-B | As a user, I want c, so that d. | docs/requirements/b.md | planned | M-A |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/milestones/m.md | dev | Approved | 2026-01-01 |
EOF
cat > "$d/docs/requirements/a.md" <<'EOF'
# A

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/requirements/a.md | dev | Approved | 2026-01-01 |
| Build | docs/build/a/build-report.md | dev | Approved | 2026-01-02 |
EOF
cat > "$d/docs/requirements/b.md" <<'EOF'
# B

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/requirements/b.md | dev | Approved | 2026-01-01 |
| Build | docs/build/b/build-report.md | dev | Approved | 2026-01-03 |
EOF
expect_pass "check-approvals accepts the plan row" "$d" sh "$CI/check-approvals.sh" docs/milestones/m.md plan
expect_fail "check-approvals rejects a missing plan row" "$d" sh "$CI/check-approvals.sh" docs/requirements/a.md plan
expect_fail "check-milestone fails a build-approved story whose dependency lacks verify" "$d" sh "$CI/check-milestone.sh" docs/milestones/m.md intake
expect_pass "check-milestone order check can be turned off" "$d" env MILESTONE_ORDER=0 sh "$CI/check-milestone.sh" docs/milestones/m.md intake
printf '| Verify | docs/verify/a/test-report.md | dev | Approved | 2026-01-04 |\n' >> "$d/docs/requirements/a.md"
expect_pass "check-milestone passes once the dependency has a verify approval" "$d" sh "$CI/check-milestone.sh" docs/milestones/m.md intake

# --- check-milestone.sh SLO waivers -----------------------------------------
d="$tmp/slo"
mkdir -p "$d/docs/milestones" "$d/docs/requirements" "$d/docs/design/system" "$d/docs/verify/s"
printf 'commit: abcdef1234567\n' > "$d/docs/verify/s/test-report.md"
cat > "$d/docs/milestones/p4.md" <<'EOF'
# Milestone: P4

Evidence: docs/design/system/slo-evidence.md

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| P4-A | As an operator, I want slo, so that ok. | docs/requirements/s.md | planned | — |
EOF
cat > "$d/docs/requirements/s.md" <<'EOF'
# S

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Intake | docs/requirements/s.md | dev | Approved | 2026-01-01 |
| Verify | docs/verify/s/test-report.md | dev | Approved | 2026-01-02 |
EOF
cat > "$d/docs/design/system/slo-evidence.md" <<'EOF'
| Surface | Kind | Command or waiver | Output or approver | Date |
|---------|------|-------------------|--------------------|------|
| checkout | waiver | Not measured | Ada | 2026-01-01 |
EOF
expect_pass "slo waiver is accepted by default" "$d" env VERIFY_STALE=0 sh "$CI/check-milestone.sh" docs/milestones/p4.md verify
expect_fail "slo waiver is rejected with SLO_ALLOW_WAIVERS=0" "$d" env VERIFY_STALE=0 SLO_ALLOW_WAIVERS=0 sh "$CI/check-milestone.sh" docs/milestones/p4.md verify

# --- check-event-schemas.sh --------------------------------------------------
d="$tmp/events"
mkdir -p "$d/docs/design/f/events"
(
  cd "$d"
  git init -q
  printf '{"eventVersion":"1","type":"object","properties":{"id":{"type":"string"},"qty":{"type":"integer"}},"required":["id"]}\n' \
    > docs/design/f/events/order-created.json
  git add -A && git_commit base
)
base="$(cd "$d" && git rev-parse HEAD)"
(
  cd "$d"
  printf '{"eventVersion":"1.1","type":"object","properties":{"id":{"type":"string"},"qty":{"type":"integer"},"note":{"type":"string"}},"required":["id"]}\n' \
    > docs/design/f/events/order-created.json
  git add -A && git_commit additive
)
additive="$(cd "$d" && git rev-parse HEAD)"
(
  cd "$d"
  printf '{"eventVersion":"2","type":"object","properties":{"id":{"type":"string"}},"required":["id"]}\n' \
    > docs/design/f/events/order-created.json
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

if [ "$status" -ne 0 ]; then
  echo "test-ci-checks: FAILED" >&2
  exit 1
fi
echo "test-ci-checks: OK"
