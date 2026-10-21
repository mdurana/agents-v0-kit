#!/bin/sh
# test-design-build.sh — behavior tests for Design and Build state, artifact indexing,
# endpoint scanning, attempt budgets, failure briefs, and loop guardrails (no network).
# Run by validate-kit.sh. Needs git and python3.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$KIT/templates/.agents-v0/scripts"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
has() { if grep -Fq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1 (missing '$3' in $2)"; fi; }
run() {
  want="$1"; desc="$2"; dir="$3"; shift 3
  if (cd "$dir" && "$@") >"$tmp/out.txt" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (wanted $want, got $got: $(tail -n 2 "$tmp/out.txt" | tr '\n' ' '))"; fi
}

# --- Design & Build artifact indexing in sync-feature-state.sh ---------------
d="$tmp/design-build"
mkdir -p "$d/.agents-v0/scripts" \
         "$d/docs/agents-v0/requirements" \
         "$d/docs/agents-v0/design/orders/mockups" \
         "$d/docs/agents-v0/build/orders" \
         "$d/docs/agents-v0/verify/orders"
cp "$SC/sync-feature-state.sh" "$SC/check-attempt-budget.sh" "$SC/check-failure-brief.sh" \
   "$SC/endpoint_scan.py" "$SC/packlib.py" "$SC/resolve-layout.sh" "$d/.agents-v0/scripts/"

cat > "$d/docs/agents-v0/requirements/orders.md" <<'EOF'
# Orders
As a customer, I want to place an order, so that I can buy goods.
EOF
cat > "$d/docs/agents-v0/design/orders/design.md" <<'EOF'
# Design: orders
EOF
cat > "$d/docs/agents-v0/design/orders/openapi.yaml" <<'EOF'
openapi: 3.0.3
info: {title: Orders, version: "1.0.0"}
paths: {}
EOF
cat > "$d/docs/agents-v0/design/orders/ux-spec.md" <<'EOF'
# UX spec: orders
EOF
cat > "$d/docs/agents-v0/design/orders/review.md" <<'EOF'
agent: design-reviewer
| # | Label | Finding | Evidence | Status |
|---|---|---|---|---|
| 1 | Suggestion | clarify timeout | design.md:1 | Resolved |
EOF
cat > "$d/docs/agents-v0/build/orders/plan.md" <<'EOF'
# Build plan
| AC | Status | Test |
|----|--------|------|
| AC-1 | done | OrderServiceTest#create_valid_returnsId |
EOF
cat > "$d/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build report
| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| mvn verify | 1 | 1 | OrderServiceTest#create_valid_returnsId | OrderService.java:10 |
| mvn verify | 0 | 2 | | |
EOF

run pass "design-build: sync-feature-state approves intake and design" "$d" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --approve intake --approve design --clear-active
ST="$d/docs/agents-v0/requirements/orders.state.json"
has "state: lastApprovedPhase is design" "$ST" '"lastApprovedPhase": "design"'
has "state: artifacts map indexes design.md" "$ST" '"design": "docs/agents-v0/design/orders/design.md"'
has "state: artifacts map indexes openapi.yaml" "$ST" '"openapi": "docs/agents-v0/design/orders/openapi.yaml"'
has "state: artifacts map indexes ux-spec.md" "$ST" '"uxSpec": "docs/agents-v0/design/orders/ux-spec.md"'
has "state: artifacts map indexes review.md" "$ST" '"designReview": "docs/agents-v0/design/orders/review.md"'
has "state: artifacts map indexes build plan.md" "$ST" '"buildPlan": "docs/agents-v0/build/orders/plan.md"'
has "state: artifacts map indexes build-report.md" "$ST" '"buildReport": "docs/agents-v0/build/orders/build-report.md"'

run pass "design-build: sync-feature-state approves build" "$d" \
  sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --approve build --clear-active
has "state: lastApprovedPhase advances to build" "$ST" '"lastApprovedPhase": "build"'

# --- Reopen loop cap (reopenCount <= 3) --------------------------------------
run pass "reopen 1: allowed" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --reopen build
has "reopen 1: reopenCount is 1" "$ST" '"reopenCount": 1'
has "reopen 1: lastApprovedPhase falls back to design" "$ST" '"lastApprovedPhase": "design"'
run pass "reopen 2: allowed" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --approve build
run pass "reopen 2: trigger" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --reopen build
run pass "reopen 3: allowed" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --approve build
run pass "reopen 3: trigger" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --reopen build
has "reopen 3: reopenCount is 3" "$ST" '"reopenCount": 3'
run fail "reopen 4: exceeds cap of 3 and exits non-zero" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --reopen build

# --- Helper brief duplicate ask detection ------------------------------------
printf 'helper: explore-researcher\nask: find all callers of OrderService.create\nscope: src/\n' > "$d/docs/agents-v0/build/orders/helper-brief.md"
run pass "helper brief: first ask is recorded" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase build --status in_progress
run fail "helper brief: identical ask is blocked on next sync" "$d" sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/orders.md --active-phase build --status in_progress
rm -f "$d/docs/agents-v0/build/orders/helper-brief.md"

# --- check-failure-brief.sh --------------------------------------------------
cat > "$d/docs/agents-v0/build/orders/build-report.md" <<'EOF'
# Build report
| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| mvn verify | 1 | 1 | OrderServiceTest#create_valid_returnsId | OrderService.java:10 |
| mvn verify | 1 | 2 | OrderServiceTest#create_valid_returnsId | OrderService.java:10 |
EOF
run fail "failure brief: missing failure-brief.md fails after second red" "$d" sh .agents-v0/scripts/check-failure-brief.sh orders
cat > "$d/docs/agents-v0/build/orders/failure-brief.md" <<'EOF'
# Failure brief: orders
- **Test:** `OrderServiceTest#create_valid_returnsId`
- **Root cause:** `OrderService.java:42` returns null when SKU is missing
- **Smallest fix:** Throw `OrderNotFoundException` at `OrderService.java:42`
EOF
run pass "failure brief: valid failure-brief.md with file:line citation passes" "$d" sh .agents-v0/scripts/check-failure-brief.sh orders

if [ "$status" -ne 0 ]; then
  echo "test-design-build: FAILED" >&2
  exit 1
fi
echo "test-design-build: OK"
