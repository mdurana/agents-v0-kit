I have launched the `requirements-analyst` subagent to analyze the specification and draft `docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.md`. Waiting for the subagent to complete its work.
The **Intake** phase (`/v0-intake p2-h-governance-ticketing-queues-and-actions`) for story **P2-H — Universal Governance & Ticketing: Queues, Lifecycle Decisions, Comments, Attachments & Artifact Downloads** is complete and recorded as `awaiting_approval`.

### Artifacts Produced
- Requirements specification: [p2-h-governance-ticketing-queues-and-actions.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.md)
- Phase result: [p2-h-governance-ticketing-queues-and-actions.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.phase-result.md)
- Feature state: [p2-h-governance-ticketing-queues-and-actions.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.state.json)

### Summary
- **User Story**: `As a finance approver, I want a unified governance ticketing engine across SAP_REPORT_POSTING, REPORT_DEFINITION_CREATE, REPORT_DEFINITION_CHANGE, RECIPE_VERSION_PUBLISH, REFERENCE_TABLE_CREATE, REFERENCE_TABLE_CHANGE, SCHEDULE_CHANGE, and IAM_ROLE_APPLICATION with To Do, My Requests, All, and Manage queue views and approve, reject, cancel, reassign, change owner, comment, attachment, and direct artifact download actions, so that all operational postings, configuration updates, and access requests follow maker-checker governance.`
- **Surface & Size**: `Surfaces: backend`, `Material: no`, `AC-1` through `AC-8` (5 `happy`, 1 `edge`, 2 `negative`):
  - **AC-1 (`happy`)**: Create maker-checker governance tickets across all eight ticket types (`POST /api/v1/tickets` with `Idempotency-Key`) and inspect ticket details (`GET /api/v1/tickets/{id}` with `ETag`).
  - **AC-2 (`happy`)**: Query governance tickets across `TODO`, `MY_REQUESTS`, `ALL`, and `MANAGE` queue views (`GET /api/v1/tickets`) with status, `ticketType`, `search`, and offset pagination.
  -
<truncated 545 bytes>
with `If-Match` / `version` optimistic concurrency, system notes, and audit logging.
  - **AC-5 (`happy`)**: Add and list ticket comments (`POST/GET /api/v1/tickets/{id}/comments`), upload and list S3-backed evidence attachments (`POST/GET /api/v1/tickets/{id}/attachments` up to `25 MB` in the `tickets` bucket with SHA-256 verification), and stream attachment or linked run artifacts (`GET /api/v1/tickets/{id}/attachments/{attachmentId}`, `GET /api/v1/tickets/{id}/artifacts/{type}`, `GET /api/v1/runs/{targetRunId}/artifacts/{type}`).
  - **AC-6 (`edge`)**: Enforce 24-hour idempotent submission replay, terminal ticket and append-only comment/attachment immutability (`trg_governance_tickets_terminal_immutable`, `trg_ticket_comments_immutable`, `trg_ticket_attachments_immutable`), and compensating S3 cleanup (`ObjectStoragePort.deleteObject`) on database failure after attachment upload.
  - **AC-7 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers and BOLA cancel/owner violations (`403 AUTH_FORBIDDEN` with `AUTHZ_DENIED` audit log), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION` with `SOD_CONFLICT_REFUSED` audit log), and View-As mutations (`403 VIEW_AS_MUTATION_FORBIDDEN` with `VIEW_AS_MUTATION_BLOCKED` audit log).
  - **AC-8 (`negative`)**: Refuse unknown UUIDs (`404 RESOURCE_NOT_FOUND`), terminal-state transitions (`409 CONCURRENCY_CONFLICT`), stale `If-Match` / `version` values (`412 PRECONDITION_FAILED`), `Idempotency-Key` conflicts (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), invalid attachments (`400`/`413`/`422`), and S3 storage errors (`502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

### Gate Stop
Please review [p2-h-governance-ticketing-queues-and-actions.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.md) and confirm whether you **approve Intake** and authorize creating the feature worktree (`feature/p2-h-governance-ticketing-queues-and-actions`).
The **Intake** phase (`/v0-intake p2-h-governance-ticketing-queues-and-actions`) for story **P2-H — Universal Governance & Ticketing: Queues, Lifecycle Decisions, Comments, Attachments & Artifact Downloads** is complete and recorded as `awaiting_approval`.

### Artifacts Produced
- Requirements specification: [p2-h-governance-ticketing-queues-and-actions.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.md)
- Phase result: [p2-h-governance-ticketing-queues-and-actions.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.phase-result.md)
- Feature state: [p2-h-governance-ticketing-queues-and-actions.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.state.json)

### Summary
- **User Story**: `As a finance approver, I want a unified governance ticketing engine across SAP_REPORT_POSTING, REPORT_DEFINITION_CREATE, REPORT_DEFINITION_CHANGE, RECIPE_VERSION_PUBLISH, REFERENCE_TABLE_CREATE, REFERENCE_TABLE_CHANGE, SCHEDULE_CHANGE, and IAM_ROLE_APPLICATION with To Do, My Requests, All, and Manage queue views and approve, reject, cancel, reassign, change owner, comment, attachment, and direct artifact download actions, so that all operational postings, configuration updates, and access requests follow maker-checker governance.`
- **Surface & Size**: `Surfaces: backend`, `Material: no`, `AC-1` through `AC-8` (5 `happy`, 1 `edge`, 2 `negative`):
  - **AC-1 (`happy`)**: Create maker-checker governance tickets across all eight ticket types (`POST /api/v1/tickets` with `Idempotency-Key`) and inspect ticket details (`GET /api/v1/tickets/{id}` with `ETag`).
  - **AC-2 (`happy`)**: Query governance tickets across `TODO`, `MY_REQUESTS`, `ALL`, and `MANAGE` queue views (`GET /api/v1/tickets`) with status, `ticketType`, `search`, and offset pagination.
  -
<truncated 545 bytes>
with `If-Match` / `version` optimistic concurrency, system notes, and audit logging.
  - **AC-5 (`happy`)**: Add and list ticket comments (`POST/GET /api/v1/tickets/{id}/comments`), upload and list S3-backed evidence attachments (`POST/GET /api/v1/tickets/{id}/attachments` up to `25 MB` in the `tickets` bucket with SHA-256 verification), and stream attachment or linked run artifacts (`GET /api/v1/tickets/{id}/attachments/{attachmentId}`, `GET /api/v1/tickets/{id}/artifacts/{type}`, `GET /api/v1/runs/{targetRunId}/artifacts/{type}`).
  - **AC-6 (`edge`)**: Enforce 24-hour idempotent submission replay, terminal ticket and append-only comment/attachment immutability (`trg_governance_tickets_terminal_immutable`, `trg_ticket_comments_immutable`, `trg_ticket_attachments_immutable`), and compensating S3 cleanup (`ObjectStoragePort.deleteObject`) on database failure after attachment upload.
  - **AC-7 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers and BOLA cancel/owner violations (`403 AUTH_FORBIDDEN` with `AUTHZ_DENIED` audit log), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION` with `SOD_CONFLICT_REFUSED` audit log), and View-As mutations (`403 VIEW_AS_MUTATION_FORBIDDEN` with `VIEW_AS_MUTATION_BLOCKED` audit log).
  - **AC-8 (`negative`)**: Refuse unknown UUIDs (`404 RESOURCE_NOT_FOUND`), terminal-state transitions (`409 CONCURRENCY_CONFLICT`), stale `If-Match` / `version` values (`412 PRECONDITION_FAILED`), `Idempotency-Key` conflicts (`409 IDEMPOTENCY_KEY_REPLAY_CONFLICT`), invalid attachments (`400`/`413`/`422`), and S3 storage errors (`502 ARTIFACT_STORAGE_ERROR`).
- **Open Questions**: `none`

### Gate Stop
Please review [p2-h-governance-ticketing-queues-and-actions.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-h-governance-ticketing-queues-and-actions.md) and confirm whether you **approve Intake** and authorize creating the feature worktree (`feature/p2-h-governance-ticketing-queues-and-actions`).
