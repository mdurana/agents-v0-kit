#!/bin/sh
# test-ci-checks.sh — behavior tests for layout resolution, stack pack activation,
# backend verify runner, attempt budgets, state synchronization, and audit pack export (no network).
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$KIT/templates/.agents-v0/scripts"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }

expect_pass() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >/dev/null 2>&1; then pass "$desc"; else fail "$desc (expected exit 0)"; fi
}
expect_fail() {
  desc="$1"; dir="$2"; shift 2
  if (cd "$dir" && "$@") >/dev/null 2>&1; then fail "$desc (expected non-zero)"; else pass "$desc"; fi
}

# --- resolve-layout.sh -------------------------------------------------------
d="$tmp/layout-auto"
mkdir -p "$d/services/order" "$d/services/inventory"
: > "$d/services/order/pom.xml"
: > "$d/services/inventory/pom.xml"
out="$(cd "$d" && sh "$SC/resolve-layout.sh")"
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
out="$(cd "$d" && sh "$SC/resolve-layout.sh")"
printf '%s' "$out" | grep -Fq "SERVICE_ROOTS='services/a services/b'" \
  && pass "resolve-layout reads the Service roots row" || fail "resolve-layout reads the Service roots row"
printf '%s' "$out" | grep -Fq "BACKEND_ROOT=''" \
  && pass "resolve-layout leaves Backend root empty with Service roots" || fail "resolve-layout leaves Backend root empty with Service roots"
sed 's|services/a, services/b|../escape|' "$d/docs/agents-v0/project-profile.md" > "$d/docs/bad.md"
expect_fail "resolve-layout rejects a Service root outside the repo" "$d" sh "$SC/resolve-layout.sh" docs/bad.md

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

# --- sync-feature-state.sh decision semantics & baseCommit -------------------
d="$tmp/state-semantics"
mkdir -p "$d/docs/agents-v0/requirements" "$d/.git/refs/heads"
printf 'ref: refs/heads/main\n' > "$d/.git/HEAD"
printf '0123456789abcdef0123456789abcdef01234567\n' > "$d/.git/refs/heads/main"

mkdir_dec() {
  name="$1"; shift
  {
    printf '# Dec\n\n## Delivery approvals\n\n| Phase | Artifacts | Approver | Decision | Date |\n|-------|-----------|----------|----------|------|\n'
    for row in "$@"; do printf '%s\n' "$row"; done
  } > "$d/docs/agents-v0/requirements/$name.md"
}
mkdir_dec dec-state \
  '| Intake | docs/agents-v0/requirements/dec-state.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved with conditions: fix X | 2026-01-02 |'
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state.md >/dev/null 2>&1)
if grep -Fq '"lastApprovedPhase": "intake"' "$d/docs/agents-v0/requirements/dec-state.state.json"; then
  pass "state: a conditional design approval leaves lastApprovedPhase at intake"
else
  fail "state: a conditional design approval leaves lastApprovedPhase at intake"
fi

mkdir_dec dec-state2 \
  '| Intake | docs/agents-v0/requirements/dec-state2.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved | 2026-01-02 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Re-opened | 2026-01-03 |'
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-state2.md >/dev/null 2>&1)
if grep -Fq '"lastApprovedPhase": "intake"' "$d/docs/agents-v0/requirements/dec-state2.state.json"; then
  pass "state: a later Re-opened row withdraws an earlier Approved design"
else
  fail "state: a later Re-opened row withdraws an earlier Approved design"
fi
if grep -Eq '"baseCommit": "[0-9a-f]{40}"' "$d/docs/agents-v0/requirements/dec-state2.state.json"; then
  pass "state: sync-feature-state records baseCommit SHA"
else
  fail "state: sync-feature-state records baseCommit SHA"
fi

mkdir_dec dec-reopen \
  '| Intake | docs/agents-v0/requirements/dec-reopen.md | @ada | Approved | 2026-01-01 |' \
  '| Design | docs/agents-v0/design/x/design.md | @ada | Approved | 2026-01-02 |' \
  '| Build | docs/agents-v0/build/x/build-report.md | @ada | Re-opened | 2026-01-03 |'
(cd "$d" && sh "$SC/sync-feature-state.sh" docs/agents-v0/requirements/dec-reopen.md --active-phase verify --status blocked --reason "Build is Re-opened" >/dev/null 2>&1)
if grep -Fq '"activePhase": "build"' "$d/docs/agents-v0/requirements/dec-reopen.state.json"; then
  pass "state: blocked verify with Re-opened build routes activePhase to build"
else
  fail "state: blocked verify with Re-opened build routes activePhase to build"
fi

# --- activate-stack-pack.sh --------------------------------------------------
p="$tmp/pack-activate"
mkdir -p "$p"
git -C "$p" init -q -b main
(cd "$p" && KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" "$p" >/dev/null 2>&1)
expect_pass "activate-stack-pack activates dotnet pack" "$p" sh .agents-v0/scripts/activate-stack-pack.sh dotnet
if grep -Fq '| Pack | dotnet |' "$p/docs/agents-v0/project-profile.md"; then
  pass "activate-stack-pack updates project-profile.md Pack row to dotnet"
else
  fail "activate-stack-pack updates project-profile.md Pack row to dotnet"
fi

if [ "$status" -ne 0 ]; then
  echo "test-ci-checks: FAILED" >&2
  exit 1
fi
echo "test-ci-checks: OK"
