# Feature: P1-B — Transformation Recipe Schema

Milestone: P1 — Contracts and Data Models
Story: P1-B
Surfaces: backend
Material: no
Open questions: none

As a finance operator, I want to define and validate versioned transformation recipes referencing registered lookup tables, so that partner commission calculations are deterministic and auditable.

## Preconditions

- `P0-A` and `P1-A` (`p1-a-lookup-table-registry`) are verified and released on `main`.
- Operator is authenticated with role `FINANCE_OPERATOR` or `PLATFORM_ADMIN`.

## Acceptance Criteria

### AC-1 — Create Valid Transformation Recipe
Kind: happy
```gherkin
Given an authenticated finance operator and an active lookup table "PARTNER_RATE_GRID"
When they POST a transformation recipe definition with code "COMMISSION_CALC_V1" referencing "PARTNER_RATE_GRID" to /api/v1/recipes
Then HTTP 201 Created is returned with recipe version 1 and validated step schema
```

### AC-2 — Retrieve Transformation Recipe by Code
Kind: happy
```gherkin
Given an existing transformation recipe with code "COMMISSION_CALC_V1"
When an authenticated finance operator sends GET /api/v1/recipes/COMMISSION_CALC_V1
Then HTTP 200 OK is returned with the recipe code, version, and lookup reference
```

### AC-3 — Reject Recipe with Blank Code or Missing Lookup Table Reference
Kind: negative
```gherkin
Given an authenticated finance operator
When they POST a transformation recipe payload with a blank code or missing lookupCode to /api/v1/recipes
Then HTTP 400 Bad Request is returned as RFC 7807 Problem Details without persisting any record
```

## Desk check

- Verified `AC-1`..`AC-3` cover happy creation, happy retrieval, and negative validation on `Surfaces: backend` (`Size: 3`).

## Non-Functional Requirements

- p95 response latency <= 250 ms (`docs/agents-v0/design/system/nfr-slo.md`).
- Explicit `@PreAuthorize` annotation on all `/api/v1/recipes` endpoints.

## Regulations & Security-Review Triggers

- **Regulations**: Internal financial audit trail & SOX maker-checker readiness.
- **Security Triggers**: RBAC endpoint authorization (`F4`), input validation (`F1`).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p1-b-transformation-recipe-schema.md | mdurana | Approved | 2026-10-28 |
| design | docs/agents-v0/design/p1-b-transformation-recipe-schema/design.md | mdurana | Approved | 2026-10-28 |
| build | docs/agents-v0/build/p1-b-transformation-recipe-schema/build-report.md | mdurana | Approved | 2026-10-28 |
| verify | docs/agents-v0/verify/p1-b-transformation-recipe-schema/quality-gate.md | mdurana | Approved | 2026-10-28 |
| release | docs/agents-v0/requirements/p1-b-transformation-recipe-schema.state.json | mdurana | Approved | 2026-10-28 |
