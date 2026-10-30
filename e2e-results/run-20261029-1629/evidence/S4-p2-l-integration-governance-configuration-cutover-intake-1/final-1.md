I have launched the `requirements-analyst` subagent to produce the Intake requirements artifact for `P2-L` (`p2-l-integration-governance-configuration-cutover`) and am waiting for its completion notification.
The **Intake** phase (`/v0-intake`) for story **P2-L** (`p2-l-integration-governance-configuration-cutover`) is complete and awaiting your approval.

### Artifacts Updated
- Requirements artifact: [p2-l-integration-governance-configuration-cutover.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.md)
- Phase result: [p2-l-integration-governance-configuration-cutover.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.phase-result.md)
- State file: [p2-l-integration-governance-configuration-cutover.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` / `P2-L` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L24))
- **Surface / Material / Size**: `Surfaces: backend` · `Material: no` · `7` acceptance criteria (`AC-1`–`AC-7`)
- **User Story**:
  > As a finance approver, I want configuration proposals for report definitions, recipe publishes, reference table changes, and schedule updates to submit PENDING_APPROVAL tickets via GovernanceTicketSubmissionPort and activate atomically via ConfigurationCutoverPort within the approval transaction at the validated Asia/Manila effective_at hour, so that configuration changes take effect safely only after maker-checker approval.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **AC-1 (`happy`)**: Submit `PENDING_APPROVAL` configuration governance tickets via `GovernanceTicketSubmissionPort.submitConfigurationTicket` across report definition (`REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`), recipe version (`RECIPE_VERSION_PUBLISH`), refer
<truncated 888 bytes>
version to `SUPERSEDED`, activating `PENDING_PUBLISH` version to `ACTIVE` (sealing rows via `trg_reference_table_rows_immutable` per `L-006`), updating `reference_tables.active_version_id`, and recording `CONFIG_REFERENCE_TABLE_VERSION_ACTIVATED`, `CONFIG_CUTOVER_APPLIED`, and `GOVERNANCE_TICKET_APPROVED`.
  - **AC-4 (`happy`)**: Atomically activate `REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`, and `SCHEDULE_CHANGE` tickets via `ConfigurationCutoverPort.applyCutover` at the validated `Asia/Manila` top-of-hour `effective_at` timestamp, recording `CONFIG_CUTOVER_APPLIED` and `GOVERNANCE_TICKET_APPROVED`.
  - **AC-5 (`edge`)**: Preserve active production configuration when a configuration ticket is rejected or cancelled (`ConfigurationCutoverPort` not invoked) and roll back partial DB writes via `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` (`L-011`) if `ConfigurationCutoverPort.applyCutover` fails mid-approval.
  - **AC-6 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION` + `SOD_CONFLICT_REFUSED`), BOLA unauthorized cancellations (`403 AUTH_FORBIDDEN`), and `View-As` mutations (`403 VIEW_AS_MUTATION_FORBIDDEN` + `VIEW_AS_MUTATION_BLOCKED`) without invoking `ConfigurationCutoverPort`.
  - **AC-7 (`negative`)**: Refuse configuration ticket approvals on execution freeze (`409 EXECUTION_FREEZE_ACTIVE` + `EXECUTION_FREEZE_REFUSED`), missing target resource (`404 RESOURCE_NOT_FOUND`), non-activatable target state or terminal ticket (`409 CONCURRENCY_CONFLICT`), non-top-of-hour `Asia/Manila` `effective_at` (`422 VALIDATION_ERROR`), or stale `If-Match` / `version` (`412 PRECONDITION_FAILED`).
- **Open questions**: `none`

Please confirm if you **approve** the Intake requirements for `p2-l-integration-governance-configuration-cutover` and authorize creating the feature worktree (`feature/p2-l-integration-governance-configuration-cutover`).
The **Intake** phase (`/v0-intake`) for story **P2-L** (`p2-l-integration-governance-configuration-cutover`) is complete and awaiting your approval.

### Artifacts Updated
- Requirements artifact: [p2-l-integration-governance-configuration-cutover.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.md)
- Phase result: [p2-l-integration-governance-configuration-cutover.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.phase-result.md)
- State file: [p2-l-integration-governance-configuration-cutover.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-l-integration-governance-configuration-cutover.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` / `P2-L` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L24))
- **Surface / Material / Size**: `Surfaces: backend` · `Material: no` · `7` acceptance criteria (`AC-1`–`AC-7`)
- **User Story**:
  > As a finance approver, I want configuration proposals for report definitions, recipe publishes, reference table changes, and schedule updates to submit PENDING_APPROVAL tickets via GovernanceTicketSubmissionPort and activate atomically via ConfigurationCutoverPort within the approval transaction at the validated Asia/Manila effective_at hour, so that configuration changes take effect safely only after maker-checker approval.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **AC-1 (`happy`)**: Submit `PENDING_APPROVAL` configuration governance tickets via `GovernanceTicketSubmissionPort.submitConfigurationTicket` across report definition (`REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`), recipe version (`RECIPE_VERSION_PUBLISH`), refer
<truncated 888 bytes>
version to `SUPERSEDED`, activating `PENDING_PUBLISH` version to `ACTIVE` (sealing rows via `trg_reference_table_rows_immutable` per `L-006`), updating `reference_tables.active_version_id`, and recording `CONFIG_REFERENCE_TABLE_VERSION_ACTIVATED`, `CONFIG_CUTOVER_APPLIED`, and `GOVERNANCE_TICKET_APPROVED`.
  - **AC-4 (`happy`)**: Atomically activate `REPORT_DEFINITION_CREATE`, `REPORT_DEFINITION_CHANGE`, and `SCHEDULE_CHANGE` tickets via `ConfigurationCutoverPort.applyCutover` at the validated `Asia/Manila` top-of-hour `effective_at` timestamp, recording `CONFIG_CUTOVER_APPLIED` and `GOVERNANCE_TICKET_APPROVED`.
  - **AC-5 (`edge`)**: Preserve active production configuration when a configuration ticket is rejected or cancelled (`ConfigurationCutoverPort` not invoked) and roll back partial DB writes via `TransactionAspectSupport.currentTransactionStatus().setRollbackOnly()` (`L-011`) if `ConfigurationCutoverPort.applyCutover` fails mid-approval.
  - **AC-6 (`negative`)**: Refuse unauthenticated callers (`401 AUTH_UNAUTHENTICATED`), unauthorized callers (`403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), maker-checker self-approvals (`403 SOD_MAKER_CHECKER_VIOLATION` + `SOD_CONFLICT_REFUSED`), BOLA unauthorized cancellations (`403 AUTH_FORBIDDEN`), and `View-As` mutations (`403 VIEW_AS_MUTATION_FORBIDDEN` + `VIEW_AS_MUTATION_BLOCKED`) without invoking `ConfigurationCutoverPort`.
  - **AC-7 (`negative`)**: Refuse configuration ticket approvals on execution freeze (`409 EXECUTION_FREEZE_ACTIVE` + `EXECUTION_FREEZE_REFUSED`), missing target resource (`404 RESOURCE_NOT_FOUND`), non-activatable target state or terminal ticket (`409 CONCURRENCY_CONFLICT`), non-top-of-hour `Asia/Manila` `effective_at` (`422 VALIDATION_ERROR`), or stale `If-Match` / `version` (`412 PRECONDITION_FAILED`).
- **Open questions**: `none`

Please confirm if you **approve** the Intake requirements for `p2-l-integration-governance-configuration-cutover` and authorize creating the feature worktree (`feature/p2-l-integration-governance-configuration-cutover`).
