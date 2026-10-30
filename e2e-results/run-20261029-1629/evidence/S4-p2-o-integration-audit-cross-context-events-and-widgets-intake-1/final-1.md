Launching `requirements-analyst` (`spec-intake`) to draft `docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.md`.
The **Intake** phase (`/v0-intake`) for **`p2-o-integration-audit-cross-context-events-and-widgets`** (`Story: P2-O`) is complete and awaiting your approval.

### Artifacts Produced
- Requirements specification: [p2-o-integration-audit-cross-context-events-and-widgets.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.md)
- Phase result: [p2-o-integration-audit-cross-context-events-and-widgets.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.phase-result.md)
- Feature state: [p2-o-integration-audit-cross-context-events-and-widgets.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `Story: P2-O` · `Surfaces: backend` · `Material: no`
- **User Story**:
  > As a compliance auditor, I want security and domain mutations across iam, configuration, execution, and governance to commit sanitized audit entries and in-app or SMTP notifications via AuditEventPort and NotificationPort, and the dashboard aggregator to query live counts via ExecutionDashboardReadPort and GovernanceDashboardReadPort, so that cross-context auditability and operational alerts are complete.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **`AC-1` (`happy`)**: Commit sanitized append-only audit entries with expandable JSON mutation payloads across `iam`, `configuration`, `execution`, and `governance` via [`AuditEventPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/audit/port/Au
<truncated 716 bytes>
rchival via [`NotificationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/audit/port/NotificationPort.java).
  - **`AC-4` (`happy`)**: Reflect live cross-context `execution` and `governance` state transitions (`myOpenRuns`, `recentRuns`, `myTodoCount`, `awaitingApproval`, `failedScheduledJobs`) in `GET /api/v1/dashboard/widgets` via [`ExecutionDashboardReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/execution/port/ExecutionDashboardReadPort.java) and [`GovernanceDashboardReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/governance/port/GovernanceDashboardReadPort.java).
  - **`AC-5` (`edge`)**: Sanitize cross-context audit strings with `Encode.forJava()`, redact sensitive keys in `mutation_payload_json`, isolate async SMTP retries (`5` attempts) to `FAILED_DLQ`, and preserve refusal audit entries on domain rollback (`@Transactional(noRollbackFor = ContractProblemException.class)`).
  - **`AC-6` (`negative`)**: Refuse cross-user BOLA access (`HTTP 403 AUTH_FORBIDDEN`) to cross-context notifications and block notification mutations under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`).
  - **`AC-7` (`negative`)**: Refuse unauthenticated (`HTTP 401 AUTH_UNAUTHENTICATED`) or unauthorized (`HTTP 403 AUTH_FORBIDDEN`) access to audit, notification, and dashboard APIs and reject any `UPDATE` or `DELETE` tampering on `audit_log_entries` via `trg_audit_log_entries_immutable`.
- **Security Triggers & Regulations**: `RBAC`, `auth`, `any {id} path`, and sensitive actions documented; aligned with BSP Circular 982 / 1019, Philippines Data Privacy Act (RA 10173) & GDPR, and Internal GXI Security Baseline.
- **Open Questions**: `none`.

Please review and confirm if you **approve the Intake artifact** and **authorize creating the feature worktree branch** (`feature/p2-o-integration-audit-cross-context-events-and-widgets`).
The **Intake** phase (`/v0-intake`) for **`p2-o-integration-audit-cross-context-events-and-widgets`** (`Story: P2-O`) is complete and awaiting your approval.

### Artifacts Produced
- Requirements specification: [p2-o-integration-audit-cross-context-events-and-widgets.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.md)
- Phase result: [p2-o-integration-audit-cross-context-events-and-widgets.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.phase-result.md)
- Feature state: [p2-o-integration-audit-cross-context-events-and-widgets.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-o-integration-audit-cross-context-events-and-widgets.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `Story: P2-O` · `Surfaces: backend` · `Material: no`
- **User Story**:
  > As a compliance auditor, I want security and domain mutations across iam, configuration, execution, and governance to commit sanitized audit entries and in-app or SMTP notifications via AuditEventPort and NotificationPort, and the dashboard aggregator to query live counts via ExecutionDashboardReadPort and GovernanceDashboardReadPort, so that cross-context auditability and operational alerts are complete.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **`AC-1` (`happy`)**: Commit sanitized append-only audit entries with expandable JSON mutation payloads across `iam`, `configuration`, `execution`, and `governance` via [`AuditEventPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/audit/port/Au
<truncated 716 bytes>
rchival via [`NotificationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/audit/port/NotificationPort.java).
  - **`AC-4` (`happy`)**: Reflect live cross-context `execution` and `governance` state transitions (`myOpenRuns`, `recentRuns`, `myTodoCount`, `awaitingApproval`, `failedScheduledJobs`) in `GET /api/v1/dashboard/widgets` via [`ExecutionDashboardReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/execution/port/ExecutionDashboardReadPort.java) and [`GovernanceDashboardReadPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/governance/port/GovernanceDashboardReadPort.java).
  - **`AC-5` (`edge`)**: Sanitize cross-context audit strings with `Encode.forJava()`, redact sensitive keys in `mutation_payload_json`, isolate async SMTP retries (`5` attempts) to `FAILED_DLQ`, and preserve refusal audit entries on domain rollback (`@Transactional(noRollbackFor = ContractProblemException.class)`).
  - **`AC-6` (`negative`)**: Refuse cross-user BOLA access (`HTTP 403 AUTH_FORBIDDEN`) to cross-context notifications and block notification mutations under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`).
  - **`AC-7` (`negative`)**: Refuse unauthenticated (`HTTP 401 AUTH_UNAUTHENTICATED`) or unauthorized (`HTTP 403 AUTH_FORBIDDEN`) access to audit, notification, and dashboard APIs and reject any `UPDATE` or `DELETE` tampering on `audit_log_entries` via `trg_audit_log_entries_immutable`.
- **Security Triggers & Regulations**: `RBAC`, `auth`, `any {id} path`, and sensitive actions documented; aligned with BSP Circular 982 / 1019, Philippines Data Privacy Act (RA 10173) & GDPR, and Internal GXI Security Baseline.
- **Open Questions**: `none`.

Please review and confirm if you **approve the Intake artifact** and **authorize creating the feature worktree branch** (`feature/p2-o-integration-audit-cross-context-events-and-widgets`).
