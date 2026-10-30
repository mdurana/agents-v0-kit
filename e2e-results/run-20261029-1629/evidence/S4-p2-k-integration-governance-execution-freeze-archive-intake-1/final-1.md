I have launched the `requirements-analyst` subagent (`spec-intake`) to draft `docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.md` for Story `P2-K`. Waiting for the subagent to complete.
The **Intake** phase for Story **P2-K** (`p2-k-integration-governance-execution-freeze-archive`) is complete and awaiting your approval.

### Artifacts Produced
- [p2-k-integration-governance-execution-freeze-archive.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.md)
- [p2-k-integration-governance-execution-freeze-archive.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.phase-result.md)
- [p2-k-integration-governance-execution-freeze-archive.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), Story `P2-K`
- **Surface & Materiality**: `Surfaces: backend`, `Material: no`, `Size: 7` (`AC-1` through `AC-7`)
- **User Story**:
  > As a finance approver, I want governance ticket approvals to enforce the runtime execution freeze via ExecutionFreezePort by rejecting configuration cutovers with HTTP 409 when targeted definitions have JOB_QUEUED or RUNNING runs, and to execute atomic S3 archival and log-only SAP connector handoff via ExecutionArchivePort on SAP_REPORT_POSTING approval while keeping SUCCESS runs valid on ticket rejection or cancellation, so that in-flight runs are never corrupted and ledger postings are 100% ticket-governed.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **AC-1 (`Kind: happy`)**: Reject configuration governance ticket approvals (`POST /api/v1/tickets/{id}/approve` across `REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`, `RECIPE_VERSION_PUBLISH`, `REFERENCE_TABLE_CREATE`, `REFERENCE_TABLE_
<truncated 2082 bytes>
ED_CSV` and `/api/v1/runs/{targetRunId}/artifacts/ARCHIVED_CSV`.
  - **AC-4 (`Kind: happy`)**: Preserve `SUCCESS` report run validity and draft artifacts when an `SAP_REPORT_POSTING` ticket is rejected (`POST /api/v1/tickets/{id}/reject`) or cancelled (`POST /api/v1/tickets/{id}/cancel`), and allow re-endorsement (`POST /api/v1/runs/{targetRunId}/endorse`) under a new `SAP_REPORT_POSTING` ticket without re-executing the transformation worker.
  - **AC-5 (`Kind: edge`)**: Enforce `_v2` and `_<epoch_ms>` collision-safe S3 archive naming via [`ExecutionArchivePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/execution/port/ExecutionArchivePort.java) and execute compensating S3 `deleteObject` with PostgreSQL transaction rollback if database persistence or connector handoff fails mid-approval.
  - **AC-6 (`Kind: negative`)**: Refuse unauthenticated callers (`HTTP 401 AUTH_UNAUTHENTICATED`), unauthorized callers and BOLA cancellations (`HTTP 403 AUTH_FORBIDDEN`), maker-checker self-approvals (`HTTP 403 SOD_MAKER_CHECKER_VIOLATION`), and mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`) with persistent refusal audit rows (`L-004`/`L-005`).
  - **AC-7 (`Kind: negative`)**: Refuse `SAP_REPORT_POSTING` approval for missing/non-`SUCCESS` runs or missing `DRAFT_SAP_CSV` artifacts (`HTTP 409 CONCURRENCY_CONFLICT` / `HTTP 422 VALIDATION_ERROR`), stale `If-Match` / `version` values (`HTTP 412 PRECONDITION_FAILED`), terminal ticket transitions (`HTTP 409 CONCURRENCY_CONFLICT`), and S3 archival failures (`HTTP 502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

---

### Approval Gate
Please confirm:
1. Do you **approve** the **Intake** artifact for `p2-k-integration-governance-execution-freeze-archive`?
2. Do you **authorize** creating the feature worktree branch `feature/p2-k-integration-governance-execution-freeze-archive` via `sh .agents-v0/scripts/feature-worktree.sh p2-k-integration-governance-execution-freeze-archive`?
The **Intake** phase for Story **P2-K** (`p2-k-integration-governance-execution-freeze-archive`) is complete and awaiting your approval.

### Artifacts Produced
- [p2-k-integration-governance-execution-freeze-archive.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.md)
- [p2-k-integration-governance-execution-freeze-archive.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.phase-result.md)
- [p2-k-integration-governance-execution-freeze-archive.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), Story `P2-K`
- **Surface & Materiality**: `Surfaces: backend`, `Material: no`, `Size: 7` (`AC-1` through `AC-7`)
- **User Story**:
  > As a finance approver, I want governance ticket approvals to enforce the runtime execution freeze via ExecutionFreezePort by rejecting configuration cutovers with HTTP 409 when targeted definitions have JOB_QUEUED or RUNNING runs, and to execute atomic S3 archival and log-only SAP connector handoff via ExecutionArchivePort on SAP_REPORT_POSTING approval while keeping SUCCESS runs valid on ticket rejection or cancellation, so that in-flight runs are never corrupted and ledger postings are 100% ticket-governed.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **AC-1 (`Kind: happy`)**: Reject configuration governance ticket approvals (`POST /api/v1/tickets/{id}/approve` across `REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`, `RECIPE_VERSION_PUBLISH`, `REFERENCE_TABLE_CREATE`, `REFERENCE_TABLE_
<truncated 2082 bytes>
ED_CSV` and `/api/v1/runs/{targetRunId}/artifacts/ARCHIVED_CSV`.
  - **AC-4 (`Kind: happy`)**: Preserve `SUCCESS` report run validity and draft artifacts when an `SAP_REPORT_POSTING` ticket is rejected (`POST /api/v1/tickets/{id}/reject`) or cancelled (`POST /api/v1/tickets/{id}/cancel`), and allow re-endorsement (`POST /api/v1/runs/{targetRunId}/endorse`) under a new `SAP_REPORT_POSTING` ticket without re-executing the transformation worker.
  - **AC-5 (`Kind: edge`)**: Enforce `_v2` and `_<epoch_ms>` collision-safe S3 archive naming via [`ExecutionArchivePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/execution/port/ExecutionArchivePort.java) and execute compensating S3 `deleteObject` with PostgreSQL transaction rollback if database persistence or connector handoff fails mid-approval.
  - **AC-6 (`Kind: negative`)**: Refuse unauthenticated callers (`HTTP 401 AUTH_UNAUTHENTICATED`), unauthorized callers and BOLA cancellations (`HTTP 403 AUTH_FORBIDDEN`), maker-checker self-approvals (`HTTP 403 SOD_MAKER_CHECKER_VIOLATION`), and mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`) with persistent refusal audit rows (`L-004`/`L-005`).
  - **AC-7 (`Kind: negative`)**: Refuse `SAP_REPORT_POSTING` approval for missing/non-`SUCCESS` runs or missing `DRAFT_SAP_CSV` artifacts (`HTTP 409 CONCURRENCY_CONFLICT` / `HTTP 422 VALIDATION_ERROR`), stale `If-Match` / `version` values (`HTTP 412 PRECONDITION_FAILED`), terminal ticket transitions (`HTTP 409 CONCURRENCY_CONFLICT`), and S3 archival failures (`HTTP 502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

---

### Approval Gate
Please confirm:
1. Do you **approve** the **Intake** artifact for `p2-k-integration-governance-execution-freeze-archive`?
2. Do you **authorize** creating the feature worktree branch `feature/p2-k-integration-governance-execution-freeze-archive` via `sh .agents-v0/scripts/feature-worktree.sh p2-k-integration-governance-execution-freeze-archive`?
