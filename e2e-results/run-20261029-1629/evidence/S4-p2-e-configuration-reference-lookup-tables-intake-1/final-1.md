I have launched the `requirements-analyst` subagent to draft the Intake requirements artifact for Story `P2-E` (`p2-e-configuration-reference-lookup-tables`). Waiting for it to complete.
The **Intake** phase (`/v0-intake`) for Story **P2-E** (`p2-e-configuration-reference-lookup-tables`) is complete and awaiting your approval.

### Artifacts Updated
- Requirements artifact: [p2-e-configuration-reference-lookup-tables.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.md)
- Phase result: [p2-e-configuration-reference-lookup-tables.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.phase-result.md)
- State file: [p2-e-configuration-reference-lookup-tables.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story / Surface**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), `Story: P2-E`, `Surfaces: backend`, `Material: no`
- **User Story**:
  > As a finance preparer, I want to create, version, import via CSV upload, and save inline-grid edits on reference lookup tables used by transformation recipes, so that commission rates and partner mappings stay accurate with full version history.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **AC-1 (`happy`)**: List and inspect reference lookup tables with offset pagination (`GET /api/v1/reference-tables`, `GET /api/v1/reference-tables/{id}`) and `ETag` / `X-Correlation-ID` headers, guarded by `CONFIG_REFERENCE_TABLES_READ`.
  - **AC-2 (`happy`)**: Create a reference lookup table (`POST /api/v1/reference-tables` with `Idempotency-Key` and `ReferenceTableCreateRequest`) with an initial `PENDING_PUBLISH` `v1` version, a `PENDING_APPROVAL` `REFERENCE_TABLE_CREATE` governance ticket, and `CONFIG_REFERENCE_TABLE_CREATED` audit logging.
  - **AC-3 (`hap
<truncated 616 bytes>
er schema matching, and formula-injection guards), creating a `REFERENCE_TABLE_CHANGE` governance ticket and recording `CONFIG_REFERENCE_TABLE_CSV_IMPORTED`.
  - **AC-5 (`edge`)**: Resolve active lookup table snapshots via value-typed [`ConfigurationReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/configuration/port/ConfigurationReadPort.java) (`ActiveReferenceTableSnapshot`, `L-003`) and `LOOKUP('TABLE_CODE', key, 'COLUMN')` evaluation in `RecipeValidatorAndSandboxEvaluator`, and atomically cut over approved `REFERENCE_TABLE_CREATE` / `REFERENCE_TABLE_CHANGE` tickets via [`ConfigurationCutoverPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/configuration/port/ConfigurationCutoverPort.java) while preserving 13-month retention (`SUPERSEDED`) and PostgreSQL immutability triggers.
  - **AC-6 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and mutating requests under an active `View-As` overlay (`403 VIEW_AS_MUTATION_FORBIDDEN`).
  - **AC-7 (`negative`)**: Refuse malformed schemas, duplicate `rowKey`/`rowIndex`, cell-count mismatches, unsafe/oversized/non-UTF-8/checksum-mismatched/header-mismatched/CSV-formula-injection uploads, past or non-hour-aligned `effectiveAt`, unknown `{id}` (`404 RESOURCE_NOT_FOUND`), stale `If-Match` (`412 CONCURRENCY_CONFLICT`), duplicate `tableCode` or `version` mismatch (`409 CONCURRENCY_CONFLICT`), `Idempotency-Key` payload mismatch (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), and undeclared JSON fields (`400 VALIDATION_ERROR`).
- **Security-Review Triggers**: `upload`, `RBAC`, `auth`, `any {id} path`, and sensitive maker-checker lookup mutations.
- **Open Questions**: `none`.

Please review and confirm if you **approve** the Intake artifact for `p2-e-configuration-reference-lookup-tables` and authorize creating the `feature/p2-e-configuration-reference-lookup-tables` worktree.
The **Intake** phase (`/v0-intake`) for Story **P2-E** (`p2-e-configuration-reference-lookup-tables`) is complete and awaiting your approval.

### Artifacts Updated
- Requirements artifact: [p2-e-configuration-reference-lookup-tables.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.md)
- Phase result: [p2-e-configuration-reference-lookup-tables.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.phase-result.md)
- State file: [p2-e-configuration-reference-lookup-tables.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story / Surface**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), `Story: P2-E`, `Surfaces: backend`, `Material: no`
- **User Story**:
  > As a finance preparer, I want to create, version, import via CSV upload, and save inline-grid edits on reference lookup tables used by transformation recipes, so that commission rates and partner mappings stay accurate with full version history.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **AC-1 (`happy`)**: List and inspect reference lookup tables with offset pagination (`GET /api/v1/reference-tables`, `GET /api/v1/reference-tables/{id}`) and `ETag` / `X-Correlation-ID` headers, guarded by `CONFIG_REFERENCE_TABLES_READ`.
  - **AC-2 (`happy`)**: Create a reference lookup table (`POST /api/v1/reference-tables` with `Idempotency-Key` and `ReferenceTableCreateRequest`) with an initial `PENDING_PUBLISH` `v1` version, a `PENDING_APPROVAL` `REFERENCE_TABLE_CREATE` governance ticket, and `CONFIG_REFERENCE_TABLE_CREATED` audit logging.
  - **AC-3 (`hap
<truncated 616 bytes>
er schema matching, and formula-injection guards), creating a `REFERENCE_TABLE_CHANGE` governance ticket and recording `CONFIG_REFERENCE_TABLE_CSV_IMPORTED`.
  - **AC-5 (`edge`)**: Resolve active lookup table snapshots via value-typed [`ConfigurationReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/configuration/port/ConfigurationReadPort.java) (`ActiveReferenceTableSnapshot`, `L-003`) and `LOOKUP('TABLE_CODE', key, 'COLUMN')` evaluation in `RecipeValidatorAndSandboxEvaluator`, and atomically cut over approved `REFERENCE_TABLE_CREATE` / `REFERENCE_TABLE_CHANGE` tickets via [`ConfigurationCutoverPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/configuration/port/ConfigurationCutoverPort.java) while preserving 13-month retention (`SUPERSEDED`) and PostgreSQL immutability triggers.
  - **AC-6 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and mutating requests under an active `View-As` overlay (`403 VIEW_AS_MUTATION_FORBIDDEN`).
  - **AC-7 (`negative`)**: Refuse malformed schemas, duplicate `rowKey`/`rowIndex`, cell-count mismatches, unsafe/oversized/non-UTF-8/checksum-mismatched/header-mismatched/CSV-formula-injection uploads, past or non-hour-aligned `effectiveAt`, unknown `{id}` (`404 RESOURCE_NOT_FOUND`), stale `If-Match` (`412 CONCURRENCY_CONFLICT`), duplicate `tableCode` or `version` mismatch (`409 CONCURRENCY_CONFLICT`), `Idempotency-Key` payload mismatch (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), and undeclared JSON fields (`400 VALIDATION_ERROR`).
- **Security-Review Triggers**: `upload`, `RBAC`, `auth`, `any {id} path`, and sensitive maker-checker lookup mutations.
- **Open Questions**: `none`.

Please review and confirm if you **approve** the Intake artifact for `p2-e-configuration-reference-lookup-tables` and authorize creating the `feature/p2-e-configuration-reference-lookup-tables` worktree.
