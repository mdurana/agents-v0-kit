#!/bin/sh
# test-release.sh — behavior tests for the Release scripts (no network).
# Covers: scripts/render-mr-body.sh and scripts/release-notes.sh. Run by validate-kit.sh.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
status=0

pass() { printf 'ok: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; status=1; }
has() { if grep -Fq -- "$3" "$2"; then pass "$1"; else fail "$1 (missing '$3')"; fi; }
lacks() { if grep -Fq -- "$3" "$2"; then fail "$1 ('$3' found)"; else pass "$1"; fi; }
exit_is() { # want description command...
  want="$1"; desc="$2"; shift 2
  if "$@" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then pass "$desc"; else fail "$desc (exit $got, wanted $want)"; fi
}

r="$tmp/repo"
mkdir -p "$r/.agents-v0/scripts" "$r/.gitlab/merge_request_templates" "$r/docs/agents-v0/requirements" "$r/docs/agents-v0/verify/orders" "$r/docs/agents-v0/build/orders" "$r/docs/agents-v0/maintain/fix-1" "$r/docs/agents-v0/milestones"
cp "$KIT"/templates/.agents-v0/scripts/render-mr-body.sh "$KIT"/templates/.agents-v0/scripts/release-notes.sh "$r/.agents-v0/scripts/"
cp "$KIT"/templates/.gitlab/merge_request_templates/default.md "$r/.gitlab/merge_request_templates/default.md"

cat > "$r/docs/agents-v0/requirements/orders.md" <<'EOF'
# Orders

As a customer, I want to place an order, so that I can buy goods.

| ID | Criterion |
|----|-----------|
| AC-1 | An order is created with a 201 |
| AC-2 | A duplicate Idempotency-Key replays the response |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Release | docs/agents-v0/requirements/orders.md | @ada | Approved | 2026-02-01 |
EOF
cat > "$r/docs/agents-v0/requirements/refunds.md" <<'EOF'
# Refunds

As a customer, I want a refund, so that I get my money back.

- AC-1: A refund is created

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| Build | docs/agents-v0/requirements/refunds.md | @ada | Approved | 2026-02-02 |
EOF
printf 'commit: aaaaaaa1111111\n' > "$r/docs/agents-v0/build/orders/build-report.md"
printf 'commit: bbbbbbb2222222\n\nLine coverage 91%%\nNo new high or critical CVE\n' > "$r/docs/agents-v0/verify/orders/test-report.md"
cat > "$r/docs/agents-v0/verify/orders/vapt-checklist.md" <<'EOF'
commit: bbbbbbb2222222
agent: security-reviewer

| Finding | Result | Evidence | Retest |
|---------|--------|----------|--------|
| F4 | pass | OrderController.java:20 | 403 test |
| F1 | N/A: no logout in this change | - | - |
EOF
# no review-notes.md on purpose

# --- render-mr-body.sh -------------------------------------------------------
(cd "$r" && sh .agents-v0/scripts/render-mr-body.sh orders > "$tmp/body.md")
has "mr body: Feature-Artifact line is set" "$tmp/body.md" "**Feature-Artifact:** docs/agents-v0/requirements/orders.md"
if [ "$(grep -c '^\*\*Feature-Artifact' "$tmp/body.md")" = 1 ]; then pass "mr body: exactly one Feature-Artifact line"; else fail "mr body: exactly one Feature-Artifact line"; fi
has "mr body: summary is the user story" "$tmp/body.md" "As a customer, I want to place an order, so that I can buy goods."
has "mr body: VAPT rows are copied verbatim" "$tmp/body.md" "| F4 | pass | OrderController.java:20 | 403 test |"
has "mr body: a report's commit stamp is listed" "$tmp/body.md" "bbbbbbb2222222"
has "mr body: a missing report is marked MISSING" "$tmp/body.md" "MISSING"
has "mr body: coverage lines come from the test report" "$tmp/body.md" "Line coverage 91%"
has "mr body: the reviewer's checkboxes stay unticked" "$tmp/body.md" "- [ ] Logout clears all client state"
lacks "mr body: the placeholder path is gone" "$tmp/body.md" "<feature>.md"

cat > "$r/docs/agents-v0/maintain/fix-1/note.md" <<'EOF'
# Maintenance note: Bump lib to 3.2.6

Id: fix-1
Tier: trivial
EOF
(cd "$r" && sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/fix-1/note.md > "$tmp/note-body.md")
has "mr body (note): Maintain-Note line is set" "$tmp/note-body.md" "**Maintain-Note:** docs/agents-v0/maintain/fix-1/note.md"
lacks "mr body (note): no Feature-Artifact line" "$tmp/note-body.md" "**Feature-Artifact:**"
has "mr body (note): summary is the note title" "$tmp/note-body.md" "Bump lib to 3.2.6"
exit_is 1 "mr body: a feature and a note together are rejected" sh -c "cd '$r' && sh .agents-v0/scripts/render-mr-body.sh orders --note docs/agents-v0/maintain/fix-1/note.md"
exit_is 1 "mr body: no argument is rejected" sh -c "cd '$r' && sh .agents-v0/scripts/render-mr-body.sh"

# --- release-notes.sh --------------------------------------------------------
cat > "$r/docs/agents-v0/milestones/m2.md" <<'EOF'
# Milestone: M2

## Stories

| Story ID | User story | Feature artifact | Status | Dependency |
|----------|-----------|------------------|--------|------------|
| M2-A | As a customer, I want to place an order, so that I can buy goods. | docs/agents-v0/requirements/orders.md | done | — |
| M2-B | As a customer, I want a refund, so that I get my money back. | docs/agents-v0/requirements/refunds.md | planned | M2-A |
EOF
(cd "$r" && sh .agents-v0/scripts/release-notes.sh docs/agents-v0/milestones/m2.md --version 1.2.0 > "$tmp/notes.md" 2> "$tmp/notes.err")
has "release notes: versioned heading" "$tmp/notes.md" "## [1.2.0] - "
has "release notes: a released story is listed with its sentence" "$tmp/notes.md" "### M2-A: As a customer, I want to place an order, so that I can buy goods."
has "release notes: acceptance criteria are listed" "$tmp/notes.md" "- AC-2: A duplicate Idempotency-Key replays the response"
has "release notes: the release approver and date are listed" "$tmp/notes.md" "approved by @ada"
lacks "release notes: an unreleased story is left out" "$tmp/notes.md" "M2-B"
has "release notes: the skipped story is named on stderr" "$tmp/notes.err" "M2-B"
(cd "$r" && sh .agents-v0/scripts/release-notes.sh docs/agents-v0/milestones/m2.md --include-unreleased > "$tmp/all.md" 2>/dev/null)
has "release notes: --include-unreleased lists the other story" "$tmp/all.md" "M2-B"
has "release notes: Unreleased heading without a version" "$tmp/all.md" "## [Unreleased]"

cp "$KIT/templates/CHANGELOG.md" "$r/CHANGELOG.md"
(cd "$r" && sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/orders.md --insert CHANGELOG.md >/dev/null 2>&1)
has "release notes: --insert adds the entry to the changelog" "$r/CHANGELOG.md" "### orders: As a customer, I want to place an order"
if [ "$(grep -c '^## \[Unreleased\]' "$r/CHANGELOG.md")" = 1 ]; then pass "release notes: --insert keeps one Unreleased heading"; else fail "release notes: --insert keeps one Unreleased heading"; fi
exit_is 1 "release notes: a missing file is an error" sh -c "cd '$r' && sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/nope.md"

if [ "$status" -ne 0 ]; then
  echo "test-release: FAILED" >&2
  exit 1
fi
echo "test-release: OK"
