# Design: p1-a-lookup-table-registry

ADR: N/A: no new architectural decision beyond ADR 0001

## Traceability

Every acceptance criterion and NFR of `docs/agents-v0/requirements/p1-a-lookup-table-registry.md` maps to what satisfies it.

| Requirement | Satisfied by | Notes |
|-------------|--------------|-------|
| AC-1 | operationId `createLookupTable`, `listLookupTables` | Persists `lookup_table_def`, immutable `lookup_table_version` with SHA-256 `content_hash`, and `lookup_table_entry` rows |
| AC-2 | operationId `createLookupTable` (`409 Conflict` `ProblemDetail`) | Rejects duplicate `entry_key` combinations in atomic transaction |
| AC-3 | operationId `createLookupTable` | Creates `version_no = N + 1` while keeping prior version `N` immutable |
| Performance (`p95 <= 400 ms`) | Indexed `(version_id, entry_key)` lookup and batch insert | Validated in controller/service integration tests |
| Auditability | `content_hash` SHA-256 + `created_by` on `lookup_table_version` | Immutable snapshot audit trail |

## Data model

- `lookup_table_def(id UUID PK, code VARCHAR(64) UNIQUE NOT NULL, name VARCHAR(128) NOT NULL, key_schema JSONB NOT NULL, value_schema JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL)`
- `lookup_table_version(id UUID PK, table_def_id UUID NOT NULL REFERENCES lookup_table_def(id), version_no INT NOT NULL, content_hash CHAR(64) NOT NULL, active BOOLEAN NOT NULL, created_by VARCHAR(128) NOT NULL, created_at TIMESTAMPTZ NOT NULL, UNIQUE(table_def_id, version_no))`
- `lookup_table_entry(id UUID PK, version_id UUID NOT NULL REFERENCES lookup_table_version(id), entry_key JSONB NOT NULL, entry_value JSONB NOT NULL)`
- No PII columns; financial reference codes and mapping tables only. Retention: 7 years for audit reproducibility.

## Authorization

| operationId | Roles or scopes | Resource rule | Notes |
|-------------|-----------------|---------------|-------|
| createLookupTable | `ROLE_ADMIN`, `ROLE_FINANCE_OPERATOR` | Authenticated operator or admin may create/version lookup tables | `@PreAuthorize("hasAnyRole('ADMIN','FINANCE_OPERATOR')")` |
| listLookupTables | `ROLE_ADMIN`, `ROLE_FINANCE_OPERATOR`, `ROLE_AUDITOR` | Authenticated portal roles may inspect registered lookup tables | `@PreAuthorize("hasAnyRole('ADMIN','FINANCE_OPERATOR','AUDITOR')")` |

## Events

N/A: no event contract

## Failure modes

- **AC-2 (Kind: negative — duplicate `entry_key` in payload):** `LookupTableService` validates uniqueness of canonicalized `entryKey` maps before committing; throws `DuplicateLookupKeyException` mapped to HTTP `409 Conflict` (`application/problem+json` RFC 9457 `ProblemDetail`) with the offending key.
- **AC-3 (Kind: edge — concurrent or sequential version upload for existing `code`):** Increments `version_no = N + 1`, marks prior version `active = false` without mutating its `content_hash` or entries, and activates the new version atomically.
- **Database timeout or transient unavailability:** Transaction rolls back cleanly; client receives RFC 9457 `503 Service Unavailable` problem response.

## Observability

- Metrics: `portal.lookup_table.versions.created` counter and `http.server.requests` histogram on `/api/v1/lookup-tables`.
- Structured JSON logs: `tableCode`, `versionNo`, `rowCount`, `contentHash`, `correlationId`.
- OpenTelemetry span around lookup version creation and batch entry persistence.

## Rollout

- Backward-compatible additive REST endpoints (`/api/v1/lookup-tables`) and schema tables (`lookup_table_def`, `lookup_table_version`, `lookup_table_entry`).
- Rollback: disable route or revert feature branch before release merge; no destructive schema changes.
