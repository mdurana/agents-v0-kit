# Feature: P2-A — Funding Cost SAP Export

Milestone: P2 — MVP Core Features
Story: P2-A
Surfaces: backend
Material: no
Open questions: none

As a finance operator, I want to execute funding cost transformation batches and export balanced SAP journal vouchers, so that monthly partner commissions settle accurately in SAP FI.

## Preconditions

- `P0-A`, `P1-A`, and `P1-B` are verified and released on `main`.
- Operator is authenticated with role `FINANCE_OPERATOR` or `PLATFORM_ADMIN`.

## Acceptance Criteria

### AC-1 — Generate Balanced SAP Export Batch
Kind: happy
```gherkin
Given an authenticated finance operator and an active recipe "COMMISSION_CALC_V1"
When they POST a funding cost batch request for period "2026-10" to /api/v1/funding-cost-exports
Then HTTP 201 Created is returned with batch status "BALANCED" and zero net journal delta
```

### AC-2 — Retrieve SAP Export Batch Status
Kind: happy
```gherkin
Given an existing funding cost export batch for period "2026-10"
When an authenticated finance operator sends GET /api/v1/funding-cost-exports/2026-10
Then HTTP 200 OK is returned with the period, recipeCode, and BALANCED status
```

### AC-3 — Reject Export Request with Blank Period
Kind: negative
```gherkin
Given an authenticated finance operator
When they POST a funding cost export payload with a blank period to /api/v1/funding-cost-exports
Then HTTP 400 Bad Request is returned as RFC 7807 Problem Details without persisting any batch
```

## Desk check

- Verified `AC-1`..`AC-3` cover happy export creation, happy retrieval, and negative input validation on `Surfaces: backend` (`Size: 3`).

## Non-Functional Requirements

- p95 response latency <= 250 ms (`docs/agents-v0/design/system/nfr-slo.md`).
- Explicit `@PreAuthorize` annotation on all `/api/v1/funding-cost-exports` endpoints.

## Regulations & Security-Review Triggers

- **Regulations**: SOX financial journal balance integrity (`debit == credit`).
- **Security Triggers**: RBAC endpoint authorization (`F4`), input validation (`F1`).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| intake | docs/agents-v0/requirements/p2-a-funding-cost-sap-export.md | mdurana | Approved | 2026-10-28 |
| design | docs/agents-v0/design/p2-a-funding-cost-sap-export/design.md | mdurana | Approved | 2026-10-28 |
| build | docs/agents-v0/build/p2-a-funding-cost-sap-export/build-report.md | mdurana | Approved | 2026-10-28 |
