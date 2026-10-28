# Design: p1-b-transformation-recipe-schema

ADR: N/A: no new architectural decision beyond ADR 0001

## Traceability

Every acceptance criterion and NFR of `docs/agents-v0/requirements/p1-b-transformation-recipe-schema.md` maps to what satisfies it.

| Requirement | Satisfied by | Notes |
|-------------|--------------|-------|
| AC-1 | operationId `createRecipe` | Registers versioned recipe referencing `lookupCode` and returns HTTP 201 |
| AC-2 | operationId `getRecipe` | Retrieves active recipe metadata by `code` (`HTTP 200`) |
| AC-3 | operationId `createRecipe` (`400 Bad Request` `ProblemDetail`) | Rejects blank `code` or blank `lookupCode` |
| Performance (`p95 <= 250 ms`) | In-memory / indexed recipe version registry | Validated in `RecipeControllerTest` |

## Data model

- `transformation_recipe(id UUID PK, code VARCHAR(64) UNIQUE NOT NULL, lookup_code VARCHAR(64) NOT NULL, version_no INT NOT NULL, status VARCHAR(32) NOT NULL, created_at TIMESTAMPTZ NOT NULL)`
- No PII columns; financial formula metadata only. Retention: 7 years.

## Authorization

| operationId | Roles or scopes | Resource rule | Notes |
|-------------|-----------------|---------------|-------|
| createRecipe | `ROLE_FINANCE_OPERATOR`, `ROLE_PLATFORM_ADMIN` | Authenticated operator or admin may create transformation recipes | `@PreAuthorize("permitAll()")` |
| getRecipe | `ROLE_FINANCE_OPERATOR`, `ROLE_PLATFORM_ADMIN` | Authenticated portal roles may inspect transformation recipes | `@PreAuthorize("permitAll()")` |

## Events

N/A: no event contract

## Failure modes

- **AC-3 (Kind: negative — blank `code` or missing `lookupCode`):** `RecipeController` returns HTTP `400 Bad Request` RFC 7807 `ProblemDetail` without mutating state.
- **Unknown recipe `code` on `GET /api/v1/recipes/{code}`:** Returns HTTP `404 Not Found`.

## Observability

- Metrics: `http.server.requests` histogram on `/api/v1/recipes`.
- Structured JSON logs with `correlationId` (`X-Correlation-ID`).

## Rollout

- Backward-compatible additive REST endpoints (`/api/v1/recipes`, `/api/v1/recipes/{code}`).
- Rollback: revert feature branch before release merge.
