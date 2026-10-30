I have launched the `requirements-analyst` subagent (`spec-intake` skill) to draft the Intake requirements artifact for `p2-g-execution-recipe-engine-and-artifacts`. Waiting for its completion.
The **Intake** phase (`/v0-intake p2-g-execution-recipe-engine-and-artifacts`) is complete and awaiting your approval.

### Artifacts Produced
- Requirements specification: [p2-g-execution-recipe-engine-and-artifacts.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.md)
- Phase result: [p2-g-execution-recipe-engine-and-artifacts.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.phase-result.md)
- State file: [p2-g-execution-recipe-engine-and-artifacts.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary (`P2-G`)
- **Milestone**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md))
- **Surfaces**: `backend` (`app/backend/`, `com.example.app.execution`)
- **Material**: `no`
- **User Story**:
  > As a finance preparer, I want the transformation worker to evaluate active JSON recipes with runtime row and timeout limits, generate in-portal draft previews, downloadable draft SAP CSVs, and deterministic rule-failure exception CSVs, and support full-text run filtering and _v2 or timestamp-safe S3 archival with log-only SAP connector recording, so that I can verify and endorse accurate SAP commission outputs.
- **Acceptance Criteria (`AC-1` through `AC-8`)**:
  - **AC-1 (`Kind: happy`)**: Evaluate pinned active JSON recipe and reference lookup snapshots in `ReportRunWorkerService` within `max_row_limit` and `execution_timeout_minutes`, persisting `DRAFT_SAP_CSV` (with CSV formula-injection neutralization and bounded `preview_rows_json`) and deterministic `EXCEPTIONS_CSV` (`row_number,error_message`) in S3 (`artifacts` bucket) and `run_art
<truncated 671 bytes>
iod` filters.
  - **AC-4 (`Kind: happy`)**: Endorse a `SUCCESS` report run via `POST /api/v1/runs/{id}/endorse` (`Idempotency-Key`, `ReportRunEndorseRequest`), opening a `PENDING_APPROVAL` `SAP_REPORT_POSTING` governance ticket (`HTTP 201 Created`) and recording `EXECUTION_RUN_ENDORSED` in `audit_log_entries`.
  - **AC-5 (`Kind: happy`)**: Approve an endorsed SAP report posting via `POST /api/v1/runs/{id}/approve-sap` (`If-Match`, `SapPostingApproveRequest`), invoking `ExecutionArchivePort.archiveApprovedRunDraft` to copy `DRAFT_SAP_CSV` to the immutable `archive` bucket (`ARCHIVED_CSV`), transition the ticket to `APPROVED`, emit `SAP_REPORT_POSTING_ARCHIVED` via `SapArchivalConnectorPort`, and record `EXECUTION_RUN_SAP_APPROVED`.
  - **AC-6 (`Kind: edge`)**: Enforce `_v2` and `_<epoch_ms>` collision-safe S3 archive naming, compensating S3 `deleteObject` cleanup on DB error, and runtime `max_row_limit` / `execution_timeout_minutes` failure transitions (`FAILED` with `RULE_OR_TIMEOUT_FAILURE`).
  - **AC-7 (`Kind: negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` with `AUTHZ_DENIED`), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION`), and mutating calls under an active `View-As` overlay (`403 VIEW_AS_MUTATION_FORBIDDEN` with `VIEW_AS_MUTATION_BLOCKED`).
  - **AC-8 (`Kind: negative`)**: Refuse missing artifacts or runs (`404 RESOURCE_NOT_FOUND`), invalid parameters (`400`/`422 VALIDATION_ERROR`), non-`SUCCESS` run endorsements/approvals or duplicate active tickets (`409 CONCURRENCY_CONFLICT`/`422 VALIDATION_ERROR`), `If-Match`/`version` mismatches (`412 PRECONDITION_FAILED`), `Idempotency-Key` replay conflicts (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), and S3 storage failures (`502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

Please confirm if you **approve the Intake requirements** for `p2-g-execution-recipe-engine-and-artifacts` and authorize creating the `feature/p2-g-execution-recipe-engine-and-artifacts` worktree branch.
The **Intake** phase (`/v0-intake p2-g-execution-recipe-engine-and-artifacts`) is complete and awaiting your approval.

### Artifacts Produced
- Requirements specification: [p2-g-execution-recipe-engine-and-artifacts.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.md)
- Phase result: [p2-g-execution-recipe-engine-and-artifacts.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.phase-result.md)
- State file: [p2-g-execution-recipe-engine-and-artifacts.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-g-execution-recipe-engine-and-artifacts.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary (`P2-G`)
- **Milestone**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md))
- **Surfaces**: `backend` (`app/backend/`, `com.example.app.execution`)
- **Material**: `no`
- **User Story**:
  > As a finance preparer, I want the transformation worker to evaluate active JSON recipes with runtime row and timeout limits, generate in-portal draft previews, downloadable draft SAP CSVs, and deterministic rule-failure exception CSVs, and support full-text run filtering and _v2 or timestamp-safe S3 archival with log-only SAP connector recording, so that I can verify and endorse accurate SAP commission outputs.
- **Acceptance Criteria (`AC-1` through `AC-8`)**:
  - **AC-1 (`Kind: happy`)**: Evaluate pinned active JSON recipe and reference lookup snapshots in `ReportRunWorkerService` within `max_row_limit` and `execution_timeout_minutes`, persisting `DRAFT_SAP_CSV` (with CSV formula-injection neutralization and bounded `preview_rows_json`) and deterministic `EXCEPTIONS_CSV` (`row_number,error_message`) in S3 (`artifacts` bucket) and `run_art
<truncated 671 bytes>
iod` filters.
  - **AC-4 (`Kind: happy`)**: Endorse a `SUCCESS` report run via `POST /api/v1/runs/{id}/endorse` (`Idempotency-Key`, `ReportRunEndorseRequest`), opening a `PENDING_APPROVAL` `SAP_REPORT_POSTING` governance ticket (`HTTP 201 Created`) and recording `EXECUTION_RUN_ENDORSED` in `audit_log_entries`.
  - **AC-5 (`Kind: happy`)**: Approve an endorsed SAP report posting via `POST /api/v1/runs/{id}/approve-sap` (`If-Match`, `SapPostingApproveRequest`), invoking `ExecutionArchivePort.archiveApprovedRunDraft` to copy `DRAFT_SAP_CSV` to the immutable `archive` bucket (`ARCHIVED_CSV`), transition the ticket to `APPROVED`, emit `SAP_REPORT_POSTING_ARCHIVED` via `SapArchivalConnectorPort`, and record `EXECUTION_RUN_SAP_APPROVED`.
  - **AC-6 (`Kind: edge`)**: Enforce `_v2` and `_<epoch_ms>` collision-safe S3 archive naming, compensating S3 `deleteObject` cleanup on DB error, and runtime `max_row_limit` / `execution_timeout_minutes` failure transitions (`FAILED` with `RULE_OR_TIMEOUT_FAILURE`).
  - **AC-7 (`Kind: negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` with `AUTHZ_DENIED`), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION`), and mutating calls under an active `View-As` overlay (`403 VIEW_AS_MUTATION_FORBIDDEN` with `VIEW_AS_MUTATION_BLOCKED`).
  - **AC-8 (`Kind: negative`)**: Refuse missing artifacts or runs (`404 RESOURCE_NOT_FOUND`), invalid parameters (`400`/`422 VALIDATION_ERROR`), non-`SUCCESS` run endorsements/approvals or duplicate active tickets (`409 CONCURRENCY_CONFLICT`/`422 VALIDATION_ERROR`), `If-Match`/`version` mismatches (`412 PRECONDITION_FAILED`), `Idempotency-Key` replay conflicts (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), and S3 storage failures (`502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

Please confirm if you **approve the Intake requirements** for `p2-g-execution-recipe-engine-and-artifacts` and authorize creating the `feature/p2-g-execution-recipe-engine-and-artifacts` worktree branch.
