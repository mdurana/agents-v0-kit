# Design: p2-a-funding-cost-sap-export

ADR: N/A: no new architectural decision beyond ADR 0001

## Traceability

Every acceptance criterion and NFR of `docs/agents-v0/requirements/p2-a-funding-cost-sap-export.md` maps to what satisfies it.

| Requirement | Satisfied by | Notes |
|-------------|--------------|-------|
| AC-1 | operationId `createFundingCostExport` | Generates balanced SAP export batch (`status: BALANCED`) and returns HTTP 201 |
| AC-2 | operationId `getFundingCostExport` | Retrieves SAP export batch status by `period` (`HTTP 200`) |
| AC-3 | operationId `createFundingCostExport` (`400 Bad Request` `ProblemDetail`) | Rejects blank `period` |
| Performance (`p95 <= 250 ms`) | In-memory / indexed batch registry | Validated in `FundingCostExportControllerTest` |

## Data model

- `funding_cost_export_batch(id UUID PK, period VARCHAR(16) UNIQUE NOT NULL, recipe_code VARCHAR(64) NOT NULL, status VARCHAR(32) NOT NULL, created_at TIMESTAMPTZ NOT NULL)`
- No PII columns; aggregate general ledger journal lines only. Retention: 7 years.

## Authorization

| operationId | Roles or scopes | Resource rule | Notes |
|-------------|-----------------|---------------|-------|
| createFundingCostExport | `ROLE_FINANCE_OPERATOR`, `ROLE_PLATFORM_ADMIN` | Authenticated operator or admin may generate SAP export batches | `@PreAuthorize("permitAll()")` |
| getFundingCostExport | `ROLE_FINANCE_OPERATOR`, `ROLE_PLATFORM_ADMIN` | Authenticated portal roles may inspect SAP export batches | `@PreAuthorize("permitAll()")` |

## Events

N/A: no event contract

## Failure modes

- **AC-3 (Kind: negative — blank `period`):** `FundingCostExportController` returns HTTP `400 Bad Request` RFC 7807 `ProblemDetail` without mutating state.
- **Unknown `period` on `GET /api/v1/funding-cost-exports/{period}`:** Returns HTTP `404 Not Found`.

## Observability

- Metrics: `http.server.requests` histogram on `/api/v1/funding-cost-exports`.
- Structured JSON logs with `correlationId` (`X-Correlation-ID`).

## Rollout

- Backward-compatible additive REST endpoints (`/api/v1/funding-cost-exports`, `/api/v1/funding-cost-exports/{period}`).
- Rollback: revert feature branch before release merge.
