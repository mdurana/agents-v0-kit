#!/bin/sh
# Fast single-fixture functional tests for guard-export.sh and guard-deck.sh (Step 5.2, Design: DEX8).
# Reuses ONE pre-seeded temporary git repository across all export and deck checks (~1s runtime, zero upstream command runs).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/v0-export-deck.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf '  PASS: %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL: %s\n' "$1" >&2; }

printf '=== test-guard-export-deck.sh (single shared repo fixture) ===\n'

# Initialize a single lightweight git repo fixture with only the files needed by guard-export.sh and guard-deck.sh
REPO="$TMP/repo"
mkdir -p \
  "$REPO/.agents-v0/scripts" \
  "$REPO/docs/agents-v0/backlog" \
  "$REPO/docs/agents-v0/presentations" \
  "$REPO/docs/agents-v0/milestones" \
  "$REPO/docs/agents-v0/requirements" \
  "$REPO/docs/agents-v0/roadmap" \
  "$REPO/docs/agents-v0/discovery" \
  "$REPO/docs/agents-v0/design/system" \
  "$REPO/docs/agents-v0/verify/orders" \
  "$REPO/docs/agents-v0/build/orders"

cp "$ROOT/templates/.agents-v0/gate-rules" "$REPO/.agents-v0/gate-rules"
cp "$ROOT/templates/.agents-v0/secret-allowlist.json" "$REPO/.agents-v0/secret-allowlist.json"
export AGENTS_V0_APPROVALS_DIR="$TMP/approvals"
for s in guard-common.sh guard-export.sh guard-deck.sh sync-feature-state.sh secret_scan.py; do
  cp "$ROOT/templates/.agents-v0/scripts/$s" "$REPO/.agents-v0/scripts/$s"
  chmod +x "$REPO/.agents-v0/scripts/$s" 2>/dev/null || true
done
cp "$ROOT/templates/docs/agents-v0/backlog/export-params.md" "$REPO/docs/agents-v0/backlog/export-params.md"
cp "$ROOT/templates/docs/agents-v0/backlog/tickets-sources.md" "$REPO/docs/agents-v0/backlog/tickets-sources.md"
cp "$ROOT/templates/docs/agents-v0/presentations/_params.md" "$REPO/docs/agents-v0/presentations/_params.md"

cd "$REPO"
git init -q -b main
git config user.name "Test User"
git config user.email "test@example.com"
git add -A
git commit -q -m "chore: initial fixture"

# --- Part 1: guard-export.sh negative & positive checks on the shared repo ---

# 1. Refuses check when Project key or Issue type is empty
if sh .agents-v0/scripts/guard-export.sh check >/dev/null 2>&1; then
  bad "guard-export.sh check should refuse when Project key and Issue type are empty"
else
  ok "guard-export.sh check refuses empty Project key and Issue type"
fi

cat > docs/agents-v0/backlog/export-params.md <<'EOF'
# Jira export params

Project key: ORD
Issue type: Story
Output path: docs/agents-v0/backlog/tickets.csv
EOF

# 2. Refuses check when no approved plan manifest exists
if sh .agents-v0/scripts/guard-export.sh check >/dev/null 2>&1; then
  bad "guard-export.sh check should refuse when no approved plan manifest exists"
else
  ok "guard-export.sh check refuses when no approved plan manifest exists"
fi

# Seed approved program.state.json, roadmap, discovery, context-map, arc-record, milestone m1.md, and story orders
cat > docs/agents-v0/program.state.json <<'EOF'
{
  "schemaVersion": 1,
  "approvedPhases": ["roadmap", "architecture", "plan"],
  "phaseDates": {
    "roadmap": "2026-11-01",
    "architecture": "2026-11-02",
    "plan": "2026-11-03"
  },
  "updatedAt": "2026-11-03T12:00:00Z"
}
EOF

cat > docs/agents-v0/discovery/q4-brief.md <<'EOF'
# Q4 Discovery Brief
Problem: Order checkout latency exceeds 800ms.
Success metric: p95 latency <= 200ms.
EOF

cat > docs/agents-v0/roadmap/q4-roadmap.md <<'EOF'
# Q4 Roadmap
Discovery: docs/agents-v0/discovery/q4-roadmap-disc.md
EOF
sed -i 's|q4-roadmap-disc.md|q4-brief.md|' docs/agents-v0/roadmap/q4-roadmap.md

cat > docs/agents-v0/design/system/context-map.md <<'EOF'
# System Context Map
Orders BFF -> Orders Service.
EOF

cat > docs/agents-v0/design/system/arc-record.md <<'EOF'
# ARC Record
Decision: Keep synchronous REST between BFF and Orders Service.
EOF

cat > docs/agents-v0/milestones/m1.md <<'EOF'
# Milestone M1
| Story ID | Summary | Surface | Size | Feature artifact |
|---|---|---|---|---|
| S-101 | Fast order checkout | api | S | docs/agents-v0/requirements/orders.md |
| S-102 | Order audit trail | api | S | docs/agents-v0/requirements/audit.md |
EOF

cat > docs/agents-v0/requirements/orders.md <<'EOF'
# Orders Requirements
Story: S-101
Milestone file: docs/agents-v0/milestones/m1.md
Material: no

### AC-1 — Checkout succeeds under 200ms
Kind: happy-path
Given a valid cart
When the customer submits checkout
Then order confirmation is returned within 200ms
EOF

cat > docs/agents-v0/requirements/orders.state.json <<'EOF'
{
  "schemaVersion": 1,
  "feature": "orders",
  "storyId": "S-101",
  "approvedPhases": ["intake", "design", "build", "verify", "release"],
  "phaseDates": {
    "intake": "2026-11-04",
    "release": "2026-11-05"
  },
  "artifacts": {
    "verify": "docs/agents-v0/verify/orders/quality-gate.md",
    "buildReport": "docs/agents-v0/build/orders/build-report.md"
  },
  "updatedAt": "2026-11-05T10:00:00Z"
}
EOF

cat > docs/agents-v0/requirements/orders.phase-result.md <<'EOF'
# Orders Phase Result
All 5 phases approved.
EOF
cat > docs/agents-v0/verify/orders/quality-gate.md <<'EOF'
# Quality Gate
Coverage: 92%. CVEs: 0.
EOF
cat > docs/agents-v0/build/orders/build-report.md <<'EOF'
# Build Report
12 tests passing.
EOF

# Unapproved story audit.md (in manifest, but intake not yet approved)
cat > docs/agents-v0/requirements/audit.md <<'EOF'
# Audit Requirements
Story: S-102
EOF

git add -A
git commit -q -m "chore: seed approved program and orders artifacts"

# 3. guard-export.sh check succeeds and returns JSON manifest
chk_out="$(sh .agents-v0/scripts/guard-export.sh check)"
if printf '%s\n' "$chk_out" | grep -Fq "OK check:" && printf '%s\n' "$chk_out" | grep -Fq '"projectKey": "ORD"'; then
  ok "guard-export.sh check emits deterministic JSON of approved sources"
else
  bad "guard-export.sh check failed to emit expected JSON ($chk_out)"
fi

# 4. guard-export.sh verify refuses bad CSV header / preamble
cat > docs/agents-v0/backlog/tickets-sources.md <<'EOF'
# Ticket export sources
- docs/agents-v0/backlog/export-params.md (2026-11-05, Project key: ORD)
- docs/agents-v0/milestones/m1.md (2026-11-03)
- docs/agents-v0/requirements/orders.md (2026-11-04)
EOF
cat > docs/agents-v0/backlog/tickets.csv <<'EOF'
# Preamble not allowed
Issue Type,Parent ID,Summary
EOF
if sh .agents-v0/scripts/guard-export.sh verify >/dev/null 2>&1; then
  bad "guard-export.sh verify should refuse CSV preamble / wrong header"
else
  ok "guard-export.sh verify refuses CSV preamble / wrong header"
fi

# 5. Write valid tickets.csv, then test read-only source protection outside docs/agents-v0/backlog/
cat > docs/agents-v0/backlog/tickets.csv <<'EOF'
Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact
Story,,Fast order checkout,Checkout story,"Given a valid cart When the customer submits checkout Then order confirmation is returned within 200ms",High,S-101,api,S,docs/agents-v0/milestones/m1.md,docs/agents-v0/requirements/orders.md
Story,,Order audit trail,Audit story,As an auditor I want an order audit trail,Medium,S-102,api,S,docs/agents-v0/milestones/m1.md,docs/agents-v0/requirements/audit.md
EOF

echo "unauthorized edit" >> docs/agents-v0/requirements/orders.md
if sh .agents-v0/scripts/guard-export.sh verify >/dev/null 2>&1; then
  bad "guard-export.sh verify should refuse when a source file outside backlog/ is modified"
else
  ok "guard-export.sh verify refuses modification outside docs/agents-v0/backlog/"
fi
git checkout -- docs/agents-v0/requirements/orders.md

# 6. guard-export.sh verify and commit succeed on clean source tree
if sh .agents-v0/scripts/guard-export.sh verify >/dev/null 2>&1 && sh .agents-v0/scripts/guard-export.sh commit >/dev/null 2>&1; then
  last_msg="$(git log -1 --format=%s)"
  if [ "$last_msg" = "v0(export): regenerate tickets.csv" ]; then
    ok "guard-export.sh verify and commit succeed with v0(export): regenerate tickets.csv"
  else
    bad "unexpected export commit message: $last_msg"
  fi
else
  bad "guard-export.sh verify or commit failed on valid export"
fi

# --- Part 2: guard-deck.sh negative & positive checks on the SAME repo ---

# 7. Refuses invalid audience or unapproved intake story
if sh .agents-v0/scripts/guard-deck.sh check intake orders Executive "Approve scope?" >/dev/null 2>&1; then
  bad "guard-deck.sh check should refuse invalid audience 'Executive'"
else
  ok "guard-deck.sh check refuses invalid audience"
fi

if sh .agents-v0/scripts/guard-deck.sh check intake audit Technical "Approve audit scope?" >/dev/null 2>&1; then
  bad "guard-deck.sh check should refuse unapproved intake story 'audit'"
else
  ok "guard-deck.sh check refuses unapproved intake story"
fi

# 8. Intake deck check, verify, and commit
if sh .agents-v0/scripts/guard-deck.sh check intake orders Technical "Approve orders intake scope?" >/dev/null 2>&1; then
  ok "guard-deck.sh check intake orders succeeds"
else
  bad "guard-deck.sh check intake orders failed"
fi

cat > docs/agents-v0/presentations/orders-intake.md <<'EOF'
# Orders Intake Briefing
Decision: Approve orders intake scope?
### AC-1 — Checkout succeeds under 200ms
Kind: happy-path
Then order confirmation is returned within 200ms
EOF
cat > docs/agents-v0/presentations/orders-intake.params.md <<'EOF'
# Deck params

Kind: intake
Audience: Technical
Decision: Approve orders intake scope?

## Sources

| Path | Approval date |
|------|----------------|
| docs/agents-v0/requirements/orders.md | 2026-11-04 |
| docs/agents-v0/milestones/m1.md | 2026-11-03 |
EOF

if sh .agents-v0/scripts/guard-deck.sh verify intake orders >/dev/null 2>&1 && \
   sh .agents-v0/scripts/guard-deck.sh commit intake orders >/dev/null 2>&1; then
  ok "guard-deck.sh verify and commit succeed for intake briefing"
else
  bad "guard-deck.sh verify or commit failed for intake briefing"
fi

# 9. Product deck check, read-only violation refusal, verify, and commit
if sh .agents-v0/scripts/guard-deck.sh check product Mixed "Approve Q4 product plan?" >/dev/null 2>&1; then
  ok "guard-deck.sh check product succeeds"
else
  bad "guard-deck.sh check product failed"
fi

cat > docs/agents-v0/presentations/q4-roadmap.md <<'EOF'
# Q4 Product Briefing
Decision: Approve Q4 product plan?
Problem: Order checkout latency exceeds 800ms.
Success metric: p95 latency <= 200ms.
EOF
cat > docs/agents-v0/presentations/q4-roadmap.params.md <<'EOF'
# Deck params

Kind: product
Audience: Mixed
Decision: Approve Q4 product plan?

## Sources

| Path | Approval date |
|------|----------------|
| docs/agents-v0/roadmap/q4-roadmap.md | 2026-11-01 |
| docs/agents-v0/discovery/q4-brief.md | 2026-11-01 |
| docs/agents-v0/design/system/context-map.md | 2026-11-03 |
| docs/agents-v0/design/system/arc-record.md | 2026-11-02 |
| docs/agents-v0/requirements/orders.md | 2026-11-04 |
EOF

echo "stray edit" >> docs/agents-v0/roadmap/q4-roadmap.md
if sh .agents-v0/scripts/guard-deck.sh verify product >/dev/null 2>&1; then
  bad "guard-deck.sh verify should refuse when roadmap source is modified"
else
  ok "guard-deck.sh verify refuses modification outside docs/agents-v0/presentations/"
fi
git checkout -- docs/agents-v0/roadmap/q4-roadmap.md

if sh .agents-v0/scripts/guard-deck.sh verify product >/dev/null 2>&1 && \
   sh .agents-v0/scripts/guard-deck.sh commit product >/dev/null 2>&1; then
  ok "guard-deck.sh verify and commit succeed for product briefing"
else
  bad "guard-deck.sh verify or commit failed for product briefing"
fi

# 10. Delivery deck check, verify, and commit (with release evidence)
if sh .agents-v0/scripts/guard-deck.sh check delivery Non-technical "Approve M1 delivery?" >/dev/null 2>&1; then
  ok "guard-deck.sh check delivery succeeds with release evidence"
else
  bad "guard-deck.sh check delivery failed"
fi

cat > docs/agents-v0/presentations/q4-roadmap-delivery.md <<'EOF'
# Q4 Delivery Briefing
Decision: Approve M1 delivery?
### AC-1 — Checkout succeeds under 200ms
Coverage: 92%. CVEs: 0. 12 tests passing.
EOF
cat > docs/agents-v0/presentations/q4-roadmap-delivery.params.md <<'EOF'
# Deck params

Kind: delivery
Audience: Non-technical
Decision: Approve M1 delivery?

## Sources

| Path | Approval date |
|------|----------------|
| docs/agents-v0/roadmap/q4-roadmap.md | 2026-11-01 |
| docs/agents-v0/discovery/q4-brief.md | 2026-11-01 |
| docs/agents-v0/design/system/context-map.md | 2026-11-03 |
| docs/agents-v0/design/system/arc-record.md | 2026-11-02 |
| docs/agents-v0/requirements/orders.md | 2026-11-04 |
| docs/agents-v0/milestones/m1.md | 2026-11-03 |
| docs/agents-v0/verify/orders/quality-gate.md | 2026-11-05 |
| docs/agents-v0/build/orders/build-report.md | 2026-11-05 |
| docs/agents-v0/requirements/orders.phase-result.md | 2026-11-05 |
EOF

if sh .agents-v0/scripts/guard-deck.sh verify delivery >/dev/null 2>&1 && \
   sh .agents-v0/scripts/guard-deck.sh commit delivery >/dev/null 2>&1; then
  ok "guard-deck.sh verify and commit succeed for delivery briefing"
else
  bad "guard-deck.sh verify or commit failed for delivery briefing"
fi

# 16. M1 regression: non-kit *.lock files (e.g. Cargo.lock) outside allowed prefix are caught by gc_readonly_outside
echo "lock-tamper" > Cargo.lock
if sh .agents-v0/scripts/guard-export.sh verify >/dev/null 2>&1; then
  bad "guard-export.sh verify should refuse non-kit Cargo.lock outside docs/agents-v0/backlog/ (M1)"
else
  ok "guard-export.sh verify refuses non-kit Cargo.lock outside docs/agents-v0/backlog/ (M1)"
fi
rm -f Cargo.lock

# 17. C3 regression: sync-feature-state.sh --approve design refuses when guard-design.sh start was never run
rm -f docs/agents-v0/requirements/audit.state.json
if sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/audit.md >/dev/null 2>&1; then
  bad "sync-feature-state.sh --approve design should refuse without Sensei approval record even when guard start was skipped (C3)"
else
  ok "sync-feature-state.sh --approve design refuses without Sensei approval record when guard start was skipped (C3)"
fi

# 18. C2 regression: post-approval file edit under commit.paths triggers contentHash mismatch in gc_approval_ok
head_sha="$(git rev-parse HEAD)"
cat > docs/agents-v0/requirements/audit.state.json <<EOF
{
  "feature": "audit",
  "artifact": "docs/agents-v0/requirements/audit.md",
  "activePhase": "intake",
  "activeStatus": "awaiting_approval",
  "baseCommit": "$head_sha"
}
EOF
repo_id="$(GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_repo_id)"
mkdir -p "$AGENTS_V0_APPROVALS_DIR/$repo_id"
cat > "$AGENTS_V0_APPROVALS_DIR/$repo_id/intake-audit.json" <<EOF
{
  "command": "intake",
  "phase": "intake",
  "feature": "audit",
  "repo": "$REPO",
  "repoId": "$repo_id",
  "gitCommonDir": "$REPO/.git",
  "head": "$head_sha",
  "baseCommit": "$head_sha",
  "contentHash": "0000000000000000000000000000000000000000000000000000000000000000",
  "commitPaths": "docs/agents-v0/requirements/audit.md",
  "approvedAt": "2026-11-05T10:00:00Z",
  "approver": "sensei",
  "words": "Approved"
}
EOF
if (GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_ok intake audit) >/dev/null 2>&1; then
  bad "gc_approval_ok should refuse when files under commit.paths changed after approval (C2 contentHash mismatch)"
else
  ok "gc_approval_ok refuses when files under commit.paths changed after approval (C2 contentHash mismatch)"
fi

# 19. C2 regression: approval record missing contentHash is refused (fail-closed)
cat > "$AGENTS_V0_APPROVALS_DIR/$repo_id/intake-audit.json" <<EOF
{
  "command": "intake",
  "phase": "intake",
  "feature": "audit",
  "repo": "$REPO",
  "repoId": "$repo_id",
  "gitCommonDir": "$REPO/.git",
  "head": "$head_sha",
  "baseCommit": "$head_sha",
  "commitPaths": "docs/agents-v0/requirements/audit.md",
  "approvedAt": "2026-11-05T10:00:00Z",
  "approver": "sensei",
  "words": "Approved"
}
EOF
if (GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_ok intake audit) >/dev/null 2>&1; then
  bad "gc_approval_ok should refuse when approval record is missing contentHash (C2 fail-closed)"
else
  ok "gc_approval_ok refuses when approval record is missing contentHash (C2 fail-closed)"
fi

# 20. C2 regression: moving HEAD after approve before gate commit is refused (fail-closed)
git commit --allow-empty -q -m "unrelated commit moving HEAD after approve"
if (GC_HERE=.agents-v0/scripts GUARD_COMMON_LIB=1 . .agents-v0/scripts/guard-common.sh && gc_approval_ok intake audit) >/dev/null 2>&1; then
  bad "gc_approval_ok should refuse when HEAD moved after approve before the gate was committed (C2 fail-closed)"
else
  ok "gc_approval_ok refuses when HEAD moved after approve before the gate was committed (C2 fail-closed)"
fi

printf '=== test-guard-export-deck.sh: %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
