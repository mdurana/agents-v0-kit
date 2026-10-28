# Feature: P1-A — Lookup Table Registry

Milestone: P1 — Contracts and Data Models
Story: P1-A
Surfaces: backend
Material: no
Open questions: none

As a finance operator, I want to create and query versioned reference lookup tables, so that transformation recipes validate commission rates against governed reference data.

## Preconditions

- `P0-A` platform skeleton is verified and released on `main`.
- Operator is authenticated with role `FINANCE_OPERATOR` or `PLATFORM_ADMIN`.

## Acceptance Criteria

### AC-1 — Create Versioned Lookup Table
Kind: happy
```gherkin
Given an authenticated finance operator with lookup management permission
When they POST a valid lookup table definition with code "PARTNER_RATE_GRID" and versioned rows to /api/v1/lookup-tables
Then HTTP 201 Created is returned with version 1 and the persisted lookup table metadata
```

### AC-2 — Retrieve Lookup Table by Code
Kind: happy
```gherkin
Given an existing lookup table with code "PARTNER_RATE_GRID"
When an authenticated finance operator sends GET /api/v1/lookup-tables/PARTNER_RATE_GRID
Then HTTP 200 OK is returned with the active version number, column schema, and rows
```

### AC-3 — Reject Blank Lookup Code or Empty Schema
Kind: negative
```gherkin
Given an authenticated finance operator
When they POST a lookup table payload with a blank code or empty columns list to /api/v1/lookup-tables
Then HTTP 400 Bad Request is returned as RFC 7807 Problem Details without persisting any record
```

## Desk check

- Verified `AC-1`..`AC-3` cover happy creation, happy retrieval, and negative input validation on `Surfaces: backend` (`Size: 3`).

## Non-Functional Requirements

- p95 response latency <= 250 ms (`docs/agents-v0/design/system/nfr-slo.md`).
- Explicit `@PreAuthorize` annotation on all `/api/v1/lookup-tables` endpoints.

## Regulations & Security-Review Triggers

- **Regulations**: Internal financial audit trail & SOX maker-checker readiness.
- **Security Triggers**: RBAC endpoint authorization (`F4`), input validation (`F1`).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p1-a-lookup-table-registry.md | mdurana | Approved | 2026-10-28 |
| design | docs/agents-v0/design/p1-a-lookup-table-registry/design.md | mdurana | Approved | 2026-10-28 |
| build | docs/agents-v0/build/p1-a-lookup-table-registry/build-report.md | mdurana | Approved | 2026-10-28 |
| verify | docs/agents-v0/verify/p1-a-lookup-table-registry/quality-gate.md | mdurana | Approved | 2026-10-28 |
| release | docs/agents-v0/requirements/p1-a-lookup-table-registry.state.json | mdurana | Approved | 2026-10-28 |
