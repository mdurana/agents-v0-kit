#!/bin/sh
# test-release.sh — behavior tests for the Release scripts (no network).
# Covers: scripts/render-mr-body.sh and scripts/release-notes.sh. Run by validate-kit.sh.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rc=$?; rm -rf "$tmp"; exit $rc' EXIT INT TERM
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
has "mr body: the reviewer's checkboxes stay unticked" "$tmp/body.md" "- [ ] Logout clears in-memory token, refresh cookie, and leftover client state"
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

# --- local release checkpoint ------------------------------------------------
cat > "$r/docs/agents-v0/requirements/local-story.md" <<'EOF'
# Local story

As a developer, I want a local checkpoint, so that the next story can start.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| verify | docs/agents-v0/verify/local-story/test-report.md | @ada | Approved | 2026-02-01 |
| release | feature/local-story abcdef1234567890 | @ada | Local | 2026-02-02 |
EOF
state_sh="$KIT/templates/.agents-v0/scripts/sync-feature-state.sh"
(cd "$r" && sh "$state_sh" docs/agents-v0/requirements/local-story.md --active-phase release --status in_progress >/dev/null)
has "local release: checkpoint keeps the release phase in flight" "$r/docs/agents-v0/requirements/local-story.state.json" '"activePhase": "release"'
(cd "$r" && sh "$state_sh" --clear-active docs/agents-v0/requirements/local-story.md >/dev/null)
has "local release: clear-active leaves lastApprovedPhase on verify" "$r/docs/agents-v0/requirements/local-story.state.json" '"lastApprovedPhase": "verify"'
has "local release: clear-active drops the phase in flight" "$r/docs/agents-v0/requirements/local-story.state.json" '"activePhase": ""'
exit_is 1 "local release: Decision Local is not an Approved release row" sh "$KIT/templates/.agents-v0/ci/check-approvals.sh" "$r/docs/agents-v0/requirements/local-story.md" release
exit_is 0 "local release: the verify row is still approved" sh "$KIT/templates/.agents-v0/ci/check-approvals.sh" "$r/docs/agents-v0/requirements/local-story.md" verify

# P0-A batch approval writing Approved for first 4 rows and Local for release
cat > "$r/docs/agents-v0/requirements/p0-a-platform-skeleton.md" <<'EOF'
# Story: P0-A
Milestone: P0 — Platform Skeleton

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p0-a-platform-skeleton.md | @ada | Approved | 2026-02-01 |
| design | docs/agents-v0/design/p0-a-platform-skeleton/design.md | @ada | Approved | 2026-02-01 |
| build | docs/agents-v0/build/p0-a-platform-skeleton/build-report.md | @ada | Approved | 2026-02-01 |
| verify | docs/agents-v0/verify/p0-a-platform-skeleton/test-report.md | @ada | Approved | 2026-02-01 |
| release | feature/p0-a 1234567890abcdef | @ada | Local | 2026-02-01 |
EOF
(cd "$r" && sh "$state_sh" --clear-active docs/agents-v0/requirements/p0-a-platform-skeleton.md >/dev/null)
has "local release: P0-A four approved rows advance lastApprovedPhase to verify" "$r/docs/agents-v0/requirements/p0-a-platform-skeleton.state.json" '"lastApprovedPhase": "verify"'
exit_is 0 "local release: P0-A build row is approved" sh "$KIT/templates/.agents-v0/ci/check-approvals.sh" "$r/docs/agents-v0/requirements/p0-a-platform-skeleton.md" build
exit_is 0 "local release: P0-A verify row is approved" sh "$KIT/templates/.agents-v0/ci/check-approvals.sh" "$r/docs/agents-v0/requirements/p0-a-platform-skeleton.md" verify
exit_is 1 "local release: Decision Local is rejected for build row" sh -c "printf '| build | ... | @ada | Local | 2026-02-01 |\n' | grep -i '|[[:space:]]*build[[:space:]]*|' | awk -F'|' '{print tolower(\$5)}' | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)'"

resolve="$KIT/templates/.agents-v0/scripts/resolve-integration-branch.sh"
prof="$tmp/profile"
mkdir -p "$prof/docs/agents-v0"
printf '| Integration branch | develop |\n' > "$prof/docs/agents-v0/project-profile.md"
got="$(cd "$prof" && sh "$resolve")"
if [ "$got" = "develop" ]; then pass "integration branch: profile row wins"; else fail "integration branch: profile row wins (got $got)"; fi
printf '| Integration branch | <!-- e.g. main --> |\n' > "$prof/docs/agents-v0/project-profile.md"
got="$(cd "$prof" && sh "$resolve")"
if [ "$got" = "HEAD" ]; then pass "integration branch: a placeholder falls through to HEAD"; else fail "integration branch: a placeholder falls through to HEAD (got $got)"; fi

# --- local gate on main: untracked reports & merge-base(main, HEAD) == HEAD --
gr="$tmp/git-local-gate"
mkdir -p "$gr"
(
  cd "$gr"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  mkdir -p .agents-v0/ci .agents-v0/scripts .agents-v0/packs/dotnet .gitlab/merge_request_templates \
    docs/agents-v0/requirements \
    docs/agents-v0/build/p1-a-catalog-contract docs/agents-v0/verify/p1-a-catalog-contract src tests
  cp "$KIT"/templates/.agents-v0/ci/*.sh "$KIT"/templates/.agents-v0/ci/*.py .agents-v0/ci/
  cp "$KIT"/templates/.agents-v0/scripts/*.sh .agents-v0/scripts/
  cp "$KIT"/core/dotnet/pack.json .agents-v0/packs/dotnet/pack.json
  cp "$KIT"/templates/.gitlab/merge_request_templates/default.md .gitlab/merge_request_templates/default.md
  printf '## Stack\n| Field | Value |\n|---|---|\n| Pack | dotnet |\n| Integration branch | <!-- e.g. main --> |\n' > docs/agents-v0/project-profile.md
  git add .
  git commit -qm "chore: base"
)
(
  cd "$gr"
  cat > docs/agents-v0/requirements/p1-a-catalog-contract.md <<'EOF'
# P1-A Catalog Contract
Story: P0-A

As a consumer, I want a catalog contract, so that I can query items.

### AC-1: GET /api/v1/items returns 200

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p1-a-catalog-contract.md | @ada | Approved | 2026-02-01 |
EOF
  cat > docs/agents-v0/build/p1-a-catalog-contract/plan.md <<'EOF'
| AC | Status | Test |
|----|--------|------|
| AC-1 | done | CatalogTests#GetItems |
EOF
  printf 'public class Catalog {}\n' > src/Catalog.cs
  printf 'public class CatalogTests { public void GetItems() {} }\n' > tests/CatalogTests.cs
  git add docs/agents-v0/requirements/p1-a-catalog-contract.md docs/agents-v0/build/p1-a-catalog-contract/plan.md src/Catalog.cs tests/CatalogTests.cs
  git commit -qm "feat: catalog code"
  code_sha="$(git rev-parse HEAD)"
  cat > docs/agents-v0/build/p1-a-catalog-contract/build-report.md <<EOF
commit: $code_sha

| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| dotnet test | 1 | 1 | CatalogTests#GetItems | src/Catalog.cs:1 |
| dotnet test | 0 | 2 | - | - |
EOF
  printf '| build | docs/agents-v0/build/p1-a-catalog-contract/build-report.md | @ada | Approved | 2026-02-01 |\n' >> docs/agents-v0/requirements/p1-a-catalog-contract.md
  git add docs/agents-v0/build/p1-a-catalog-contract/build-report.md docs/agents-v0/requirements/p1-a-catalog-contract.md
  git commit -qm "docs: build report"
  head_sha="$(git rev-parse HEAD)"
  # Create untracked verify reports stamped with HEAD and uncommitted verify row
  for f in test-report.md vapt-checklist.md review-notes.md; do
    printf 'commit: %s\nLine coverage 90%%\nNo new high or critical CVE\n' "$head_sha" > "docs/agents-v0/verify/p1-a-catalog-contract/$f"
  done
  printf '| verify | docs/agents-v0/verify/p1-a-catalog-contract/test-report.md, docs/agents-v0/verify/p1-a-catalog-contract/vapt-checklist.md, docs/agents-v0/verify/p1-a-catalog-contract/review-notes.md | @ada | Approved | 2026-02-01 |\n' >> docs/agents-v0/requirements/p1-a-catalog-contract.md
)
exit_is 1 "local gate: untracked verify report stamped with HEAD is rejected by check-evidence" sh -c "cd '$gr' && sh .agents-v0/ci/check-evidence.sh docs/agents-v0/requirements/p1-a-catalog-contract.md verify"
exit_is 1 "local gate: uncommitted verify row and untracked verify reports on main fail check-delivery-gate-local" sh -c "cd '$gr' && sh .agents-v0/scripts/check-delivery-gate-local.sh p1-a-catalog-contract --base main"
(
  cd "$gr"
  # Also introduce a build-plan failure to verify multiple checks run even when linkage fails first
  cp docs/agents-v0/build/p1-a-catalog-contract/plan.md docs/agents-v0/build/p1-a-catalog-contract/plan.md.bak
  printf '| AC-1 | done | CatalogTests#NoSuchTest |\n' > docs/agents-v0/build/p1-a-catalog-contract/plan.md
  sh .agents-v0/scripts/check-delivery-gate-local.sh p1-a-catalog-contract --base main > "$tmp/gate-multi-fail.out" 2>&1 || true
  mv docs/agents-v0/build/p1-a-catalog-contract/plan.md.bak docs/agents-v0/build/p1-a-catalog-contract/plan.md
)
has "local gate reports earlier failure" "$tmp/gate-multi-fail.out" "FAIL check-delivery-linkage"
has "local gate still reports later failure when earlier failed" "$tmp/gate-multi-fail.out" "FAIL check-build-plan"

(
  cd "$gr"
  git add docs/agents-v0/verify/p1-a-catalog-contract docs/agents-v0/requirements/p1-a-catalog-contract.md
  git commit -qm "docs: record verify evidence and approval"
  sh .agents-v0/scripts/check-delivery-gate-local.sh p1-a-catalog-contract --base main > "$tmp/gate-main.out" 2>&1 || { cat "$tmp/gate-main.out" >&2; exit 1; }
)
exit_is 0 "local gate: committed verify reports with earlier code/doc commit stamp pass check-evidence" sh -c "cd '$gr' && sh .agents-v0/ci/check-evidence.sh docs/agents-v0/requirements/p1-a-catalog-contract.md verify"
has "local gate: on main (merge-base == HEAD) resolves pre-story base and checks code + verify linkage" "$tmp/gate-main.out" "OK: code changes linked to docs/agents-v0/requirements/p1-a-catalog-contract.md with build approval"
lacks "local gate: on main does not take the empty-range docs-only shortcut" "$tmp/gate-main.out" "OK: docs-only PR"

# --- whole-repo upgrade compatibility (install.sh --update) ------------------
upg="$tmp/git-upgrade-compat"
mkdir -p "$upg"
(
  cd "$upg"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" "$upg" >/dev/null
  # Simulate pre-upgrade project-profile.md (no -Pci-security) and custom model-config.json
  cat > docs/agents-v0/project-profile.md <<'EOF'
# Project profile

## Stack

| Layer | Value |
|-------|-------|
| Pack | java |
| Integration branch | main |

## Commands

| Purpose | Command |
|---------|---------|
| Backend verify | cd app/backend && ./mvnw -B clean verify |
| Service verify | ./mvnw -B -f {root}/pom.xml clean verify |
EOF
  python3 - .cursor/model-config.json <<'PY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p, encoding="utf-8"))
for k in ("plan", "review", "debug"):
    if k in cfg:
        cfg[k] = cfg[k].replace("reasoning_effort=xhigh", "reasoning_effort=high")
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2)
PY
  sh .agents-v0/scripts/update-agents-model.sh >/dev/null
  mkdir -p openapi docs/agents-v0/adr docs/agents-v0/design/p1-a-catalog-contract \
    docs/agents-v0/requirements docs/agents-v0/build/p1-a-catalog-contract \
    docs/agents-v0/verify/p1-a-catalog-contract app/backend/src/main/java/com/acme \
    app/backend/src/test/java/com/acme
  git add .
  git commit -qm "chore: initial kit install"
)
(
  cd "$upg"
  mkdir -p docs/agents-v0/milestones
  cat > docs/agents-v0/milestones/p1.md <<'EOF'
| P1-A | As a consumer, I want a catalog contract, so that I can query items reliably. |
EOF
  cat > docs/agents-v0/adr/0002-catalog.md <<'EOF'
# ADR 0002: Catalog Contract Compatibility
- Status: Accepted
- Date: 2026-02-01

## Context
Catalog endpoints need stable versioning.

## Decision
Expose GET /api/v1/items with bearerAuth.

## Alternatives considered
- Unversioned paths: breaks compatibility guarantees.
- GraphQL endpoint: no consumer requested it.

## Consequences
Clients use /api/v1/items.
EOF
  cat > docs/agents-v0/requirements/p1-a-catalog-contract.md <<'EOF'
# Story: P1-A — Catalog Contract

As a consumer, I want a catalog contract, so that I can query items reliably.

Milestone: P1
Milestone file: docs/agents-v0/milestones/p1.md
Story: P1-A
Surfaces: backend
Material: no
Negatives: N/A: contract read stub only

## Preconditions
The caller holds a valid Bearer token for fixture TENANT-1.

## Desk check
Call GET /api/v1/items with fixture TENANT-1 and confirm the item list response.

## Acceptance criteria

### AC-1 — list catalog items
Kind: happy
Given an authenticated caller for fixture TENANT-1
When GET /api/v1/items is requested
Then HTTP 200 is returned with the catalog items list

## Out of scope
- Pagination cursors

## NFRs
The list call returns within 200ms at p95 for fixture TENANT-1.

## Regulations
N/A: catalog metadata contains no personal data.

## Security-review triggers
none

## Open questions
none

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p1-a-catalog-contract.md | @ada | Approved | 2026-02-01 |
EOF
  cat > docs/agents-v0/design/p1-a-catalog-contract/openapi.yaml <<'EOF'
openapi: 3.0.3
info:
  title: Catalog API
  version: 1.0.0
paths:
  /api/v1/items:
    get:
      operationId: listItems
      security:
        - bearerAuth: []
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemList"
        "401":
          description: unauthorized
          content:
            application/problem+json:
              schema:
                $ref: "#/components/schemas/Problem"
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  schemas:
    ItemList:
      type: object
      required: [items]
      properties:
        items:
          type: array
          items:
            type: string
    Problem:
      type: object
      required: [title, status]
      properties:
        title:
          type: string
        status:
          type: integer
EOF
  # Catalog seeded by an earlier kit: retains <resource> operations without security alongside merged real op
  cat > openapi/api-v1.yaml <<'EOF'
openapi: 3.0.3
info:
  title: Org API
  version: 1.0.0
paths:
  /api/v1/<resource>:
    get:
      summary: List <resource>
      operationId: list<resource>
      responses:
        "200":
          description: ok
        "404":
          description: not found
          content:
            application/problem+json:
              schema:
                $ref: "#/components/schemas/Problem"
    post:
      summary: Create <resource>
      operationId: create<resource>
      parameters:
        - name: Idempotency-Key
          in: header
          required: true
          schema:
            type: string
      responses:
        "201":
          description: created
  /api/v1/<resource>/{id}:
    get:
      summary: Get <resource>
      operationId: get<resource>
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          description: ok
  /api/v1/items:
    get:
      operationId: listItems
      security:
        - bearerAuth: []
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemList"
        "401":
          description: unauthorized
          content:
            application/problem+json:
              schema:
                $ref: "#/components/schemas/Problem"
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  schemas:
    ItemList:
      type: object
      required: [items]
      properties:
        items:
          type: array
          items:
            type: string
    Problem:
      type: object
      required: [title, status]
      properties:
        title:
          type: string
        status:
          type: integer
EOF
  cat > docs/agents-v0/design/p1-a-catalog-contract/design.md <<'EOF'
# Design: p1-a-catalog-contract

## Overview
Exposes GET /api/v1/items per docs/agents-v0/adr/0002-catalog.md.

## API contract
docs/agents-v0/design/p1-a-catalog-contract/openapi.yaml

## Event contract
N/A: no event contract

## UX reference
N/A: backend-only contract

## Data model and migrations
N/A: in-memory stub

## Security and authorization
Bearer JWT via Spring Security `@PreAuthorize`.

## Failure modes
Returns 401 problem+json on missing token.

## Observability
Standard HTTP metrics.

## Rollout and rollback
Stateless route.

## Traceability
| AC | Endpoint / Component | Test |
|----|----------------------|------|
| AC-1 | GET /api/v1/items | CatalogContractTest#ac1_listItems |
EOF
  lh1="$(sh .agents-v0/ci/check-design.sh p1-a-catalog-contract --legacy-hash)"
  printf '2026-02-01 %s approved\n' "$lh1" > docs/agents-v0/design/p1-a-catalog-contract/design.lock
  printf '\nAmendment 1 note.\n' >> docs/agents-v0/design/p1-a-catalog-contract/design.md
  lh2="$(sh .agents-v0/ci/check-design.sh p1-a-catalog-contract --legacy-hash)"
  lh2_short="$(printf '%s' "$lh2" | cut -c1-12)"
  printf 'agent: design-reviewer\ndesign-hash: %s\n\n| # | Label | Finding | Evidence | Status |\n|---|---|---|---|---|\n' "$lh2_short" > docs/agents-v0/design/p1-a-catalog-contract/review.md
  cat > docs/agents-v0/design/p1-a-catalog-contract/amendments.md <<EOF
# Design amendments

| # | Date | Change | Reason | Impacted AC and operations | Approver | Decision | Hash (first 12) |
|---|------|--------|--------|----------------------------|----------|----------|-----------------|
| 1 | 2026-02-01 | Clarified note | Review polish | AC-1 listItems | @ada | Approved | $lh2_short |
EOF
  printf '2026-02-01 %s amendment 1\n' "$lh2" >> docs/agents-v0/design/p1-a-catalog-contract/design.lock
  printf '| design | docs/agents-v0/design/p1-a-catalog-contract/openapi.yaml, docs/agents-v0/design/p1-a-catalog-contract/design.md, docs/agents-v0/adr/0002-catalog.md, N/A: no UX spec | @ada | Approved | 2026-02-01 |\n' >> docs/agents-v0/requirements/p1-a-catalog-contract.md
  cat > docs/agents-v0/build/p1-a-catalog-contract/plan.md <<'EOF'
# Build plan

| AC | Status | Test |
|----|--------|------|
| AC-1 | done | CatalogContractTest#ac1_listItems |
EOF
  # Legacy red-tests.json: no designLockHash field
  cat > docs/agents-v0/build/p1-a-catalog-contract/red-tests.json <<'EOF'
{
  "failed": [
    "CatalogContractTest#ac1_listItems",
    "ac1_listItems"
  ],
  "sources": [
    "app/backend/target/surefire-reports/TEST-CatalogContractTest.xml"
  ]
}
EOF
  cat > app/backend/src/main/java/com/acme/CatalogController.java <<'EOF'
package com.acme;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
@RestController
public class CatalogController {
  @PreAuthorize("hasRole('USER')")
  @GetMapping("/api/v1/items")
  public String listItems() { return "{}"; }
}
EOF
  cat > app/backend/src/test/java/com/acme/CatalogContractTest.java <<'EOF'
package com.acme;
class CatalogContractTest {
  void ac1_listItems() {}
}
EOF
  git add .
  git commit -qm "feat: p1-a catalog implementation and amended design lock"
  build_sha="$(git rev-parse HEAD)"
  cat > docs/agents-v0/build/p1-a-catalog-contract/build-report.md <<EOF
commit: $build_sha

| Command | Exit | Attempt | Failing test | Location |
|---------|------|---------|--------------|----------|
| ./mvnw test | 1 | 1 | CatalogContractTest#ac1_listItems | CatalogController.java:1 |
| ./mvnw test | 1 | 2 | CatalogContractTest#ac1_listItems | CatalogController.java:1 |
| ./mvnw test | 0 | 3 | - | - |
EOF
  printf '| build | docs/agents-v0/build/p1-a-catalog-contract/build-report.md commit: %s | @ada | Approved | 2026-02-01 |\n' "$build_sha" >> docs/agents-v0/requirements/p1-a-catalog-contract.md
  git add docs/agents-v0/build/p1-a-catalog-contract/build-report.md docs/agents-v0/requirements/p1-a-catalog-contract.md
  git commit -qm "docs: record p1-a build approval"
  verify_sha="$(git rev-parse HEAD)"
  for f in test-report.md vapt-checklist.md review-notes.md; do
    printf 'commit: %s\nLine coverage 92%%\nNo new high or critical CVE\n' "$verify_sha" > "docs/agents-v0/verify/p1-a-catalog-contract/$f"
  done
  printf '| verify | docs/agents-v0/verify/p1-a-catalog-contract/test-report.md, docs/agents-v0/verify/p1-a-catalog-contract/vapt-checklist.md, docs/agents-v0/verify/p1-a-catalog-contract/review-notes.md commit: %s | @ada | Approved | 2026-02-01 |\n' "$verify_sha" >> docs/agents-v0/requirements/p1-a-catalog-contract.md
  printf '| release | main %s | @ada | Local | 2026-02-01 |\n' "$verify_sha" >> docs/agents-v0/requirements/p1-a-catalog-contract.md
  sh .agents-v0/scripts/sync-feature-state.sh --clear-active docs/agents-v0/requirements/p1-a-catalog-contract.md >/dev/null
  git add docs/agents-v0/verify/p1-a-catalog-contract docs/agents-v0/requirements/p1-a-catalog-contract.md docs/agents-v0/requirements/p1-a-catalog-contract.state.json
  git commit -qm "docs: verify and local release p1-a"
)
# Run install.sh --update --quick against the repo and commit the kit refresh
KIT_VALIDATING=1 sh "$KIT/scripts/install.sh" --update --quick "$upg" > "$tmp/upg-install.out" 2>&1 || { cat "$tmp/upg-install.out" >&2; fail "upgrade: install.sh --update --quick exited non-zero"; }
has "upgrade: announces project-profile.md -Pci-security migration" "$tmp/upg-install.out" "MIGRATED (project-owned file edited): docs/agents-v0/project-profile.md"
has "upgrade: stamps kit version with commit SHA" "$upg/.agents-kit-version" "+"
has "upgrade: preserves custom reasoning_effort=high on remapped agents" "$upg/.cursor/agents/solution-architect.md" "reasoning_effort=high"
(cd "$upg" && git add -A && git commit -qm "chore: update agents-v0 kit")
exit_is 0 "upgrade: check-design-contracts passes on pre-existing legacy lock and seed catalog" sh -c "cd '$upg' && sh .agents-v0/ci/check-design-contracts.sh"
exit_is 0 "upgrade: direct check-openapi.sh lint passes on legacy seed catalog alongside real operations" sh -c "cd '$upg' && sh .agents-v0/ci/check-openapi.sh lint openapi/api-v1.yaml"
exit_is 0 "upgrade: check-build-plan --complete passes on sealed legacy red-tests.json" sh -c "cd '$upg' && sh .agents-v0/ci/check-build-plan.sh p1-a-catalog-contract --complete"
exit_is 0 "upgrade: local delivery gate stays green after kit update" sh -c "cd '$upg' && sh .agents-v0/scripts/check-delivery-gate-local.sh p1-a-catalog-contract --base main"
# Verify that when a subsequent story (P1-B) adds code after P1-A's Local release checkpoint, P1-A's evidence still passes at its release checkpoint commit
(
  cd "$upg"
  cat > docs/agents-v0/requirements/p1-b-next-story.md <<'EOF'
# Story: P1-B — Next Story
EOF
  printf '// p1-b code\n' >> app/backend/src/main/java/com/acme/CatalogController.java
  git add docs/agents-v0/requirements/p1-b-next-story.md app/backend/src/main/java/com/acme/CatalogController.java
  git commit -qm "feat: p1-b starts after p1-a local release"
)
exit_is 0 "upgrade: check-evidence passes for locally-released p1-a after subsequent story p1-b modifies code" sh -c "cd '$upg' && sh .agents-v0/ci/check-evidence.sh docs/agents-v0/requirements/p1-a-catalog-contract.md build && sh .agents-v0/ci/check-evidence.sh docs/agents-v0/requirements/p1-a-catalog-contract.md verify"
# Re-opening the build enforces both the new designLockHash rule and current HEAD evidence staleness
(
  cd "$upg"
  sed -i.bak '/^| build /s/| Approved |/| Re-opened |/' docs/agents-v0/requirements/p1-a-catalog-contract.md
  rm -f docs/agents-v0/requirements/p1-a-catalog-contract.md.bak
)
exit_is 1 "upgrade: re-opening build enforces designLockHash on legacy red-tests.json" sh -c "cd '$upg' && sh .agents-v0/ci/check-build-plan.sh p1-a-catalog-contract --complete"
exit_is 1 "upgrade: re-opening build enforces HEAD staleness on check-evidence" sh -c "cd '$upg' && sh .agents-v0/ci/check-evidence.sh docs/agents-v0/requirements/p1-a-catalog-contract.md build"

if [ "$status" -ne 0 ]; then
  echo "test-release: FAILED" >&2
  exit 1
fi
echo "test-release: OK"
