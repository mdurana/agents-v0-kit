I have initialized the Intake phase (`/v0-intake`) for `p1-d-execution-and-governance-persistence` and launched the `requirements-analyst` subagent to draft `docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.md`. Waiting for the subagent to complete.
The **Intake** phase (`/v0-intake`) for `p1-d-execution-and-governance-persistence` (**Story P1-D** in Milestone `P1 — Contracts & Data Models`) is complete and awaiting your approval.

### Requirements Artifacts
- **Requirements Spec**: [p1-d-execution-and-governance-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.md)
- **Phase Result**: [p1-d-execution-and-governance-persistence.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.phase-result.md)
- **State File**: [p1-d-execution-and-governance-persistence.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Summary of Scope & Acceptance Criteria (`Surfaces: backend`, `Material: no`, `6` ACs)
- **User Story**:
  > As a finance approver, I want Flyway physical persistence migrations for report runs, run artifacts, universal governance tickets, ticket comments, and ticket attachments with partial indexing on queued and running jobs, so that maker-checker workflows and runtime execution freeze checks operate with transactional integrity.
- **Acceptance Criteria**:
  1. **`AC-1` (`Kind: happy`)** — Migrate `report_runs` and `run_artifacts` tables (`V4__execution_and_governance_schema.sql`) with UUID primary keys, `UNIQUE` constraints (`run_number`, `idempotency_key`, `(report_run_id, artifact_type)`), foreign keys (`fk_runs_definition`, `fk_runs_recipe`, `fk_runs_triggered_by`, `fk_artifacts_run`), and optimistic concurrency `report_runs.version`.
  2. **`AC-2` (`Kind: happy`)** — Migrate partial index `idx_report_runs_active_by_def ON report_runs (report_definition_id, status) WHERE status IN ('JOB_QUEUED', 'RUNNING')` and verify `ExecutionFreezePort` (`hasInFlightRuns`) detects `JOB_QUEUED` / `RUNNING` runs while ignoring terminal runs (`SUCCESS`, `FAILED`, `CANCELLED`) under a `FOR UPDATE` row lock on `report_definitions`.
  3. **`AC-3` (`Kind: happy`)** — Migrate `governance_tickets`, `ticket_comments`, and `ticket_attachments` tables with all physical columns, `UNIQUE` constraints (`ticket_number`, `idempotency_key`), foreign keys (`fk_tickets_requester`, `fk_tickets_assignee`, `fk_tickets_owner`, `fk_tickets_decided_by`, `fk_tickets_definition`, `fk_tickets_run`, `fk_tickets_recipe_version`, `fk_tickets_reference_version`, `fk_comments_ticket`, `fk_comments_author`, `fk_attachments_ticket`, `fk_attachments_uploaded_by`), and optimistic concurrency `governance_tickets.version`.
  4. **`AC-4` (`Kind: negative`)** — Refuse invalid status/ticket-type values via `CHECK` constraints, and refuse `UPDATE` or `DELETE` on terminal `governance_tickets` (`APPROVED`, `REJECTED`, `CANCELLED` -> `"governance_tickets in terminal status"`) and append-only `run_artifacts`, `ticket_comments`, and `ticket_attachments` (`"is append-only"`).
  5. **`AC-5` (`Kind: edge`)** — Preserve `SUCCESS` `report_runs` and `run_artifacts` state when a linked `SAP_REPORT_POSTING` ticket transitions to `REJECTED` or `CANCELLED`, and refuse duplicate `run_number`, `ticket_number`, `idempotency_key`, or `(report_run_id, artifact_type)` insertions via `UNIQUE` constraints.
  6. **`AC-6` (`Kind: negative`)** — Refuse cross-context access to `execution` or `governance` repositories, entities, or domain internals via ArchUnit (`LayerRulesTest` and `BoundedContextIsolationRules`).
- **Open Questions**: `none`

---

### Gate Decision Required
Please confirm if you **approve** the `Intake` phase for `p1-d-execution-and-governance-persistence` and **authorize creating the feature worktree branch** (`feature/p1-d-execution-and-governance-persistence`) via `sh .agents-v0/scripts/feature-worktree.sh p1-d-execution-and-governance-persistence`.
The **Intake** phase (`/v0-intake`) for `p1-d-execution-and-governance-persistence` (**Story P1-D** in Milestone `P1 — Contracts & Data Models`) is complete and awaiting your approval.

### Requirements Artifacts
- **Requirements Spec**: [p1-d-execution-and-governance-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.md)
- **Phase Result**: [p1-d-execution-and-governance-persistence.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.phase-result.md)
- **State File**: [p1-d-execution-and-governance-persistence.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-d-execution-and-governance-persistence.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Summary of Scope & Acceptance Criteria (`Surfaces: backend`, `Material: no`, `6` ACs)
- **User Story**:
  > As a finance approver, I want Flyway physical persistence migrations for report runs, run artifacts, universal governance tickets, ticket comments, and ticket attachments with partial indexing on queued and running jobs, so that maker-checker workflows and runtime execution freeze checks operate with transactional integrity.
- **Acceptance Criteria**:
  1. **`AC-1` (`Kind: happy`)** — Migrate `report_runs` and `run_artifacts` tables (`V4__execution_and_governance_schema.sql`) with UUID primary keys, `UNIQUE` constraints (`run_number`, `idempotency_key`, `(report_run_id, artifact_type)`), foreign keys (`fk_runs_definition`, `fk_runs_recipe`, `fk_runs_triggered_by`, `fk_artifacts_run`), and optimistic concurrency `report_runs.version`.
  2. **`AC-2` (`Kind: happy`)** — Migrate partial index `idx_report_runs_active_by_def ON report_runs (report_definition_id, status) WHERE status IN ('JOB_QUEUED', 'RUNNING')` and verify `ExecutionFreezePort` (`hasInFlightRuns`) detects `JOB_QUEUED` / `RUNNING` runs while ignoring terminal runs (`SUCCESS`, `FAILED`, `CANCELLED`) under a `FOR UPDATE` row lock on `report_definitions`.
  3. **`AC-3` (`Kind: happy`)** — Migrate `governance_tickets`, `ticket_comments`, and `ticket_attachments` tables with all physical columns, `UNIQUE` constraints (`ticket_number`, `idempotency_key`), foreign keys (`fk_tickets_requester`, `fk_tickets_assignee`, `fk_tickets_owner`, `fk_tickets_decided_by`, `fk_tickets_definition`, `fk_tickets_run`, `fk_tickets_recipe_version`, `fk_tickets_reference_version`, `fk_comments_ticket`, `fk_comments_author`, `fk_attachments_ticket`, `fk_attachments_uploaded_by`), and optimistic concurrency `governance_tickets.version`.
  4. **`AC-4` (`Kind: negative`)** — Refuse invalid status/ticket-type values via `CHECK` constraints, and refuse `UPDATE` or `DELETE` on terminal `governance_tickets` (`APPROVED`, `REJECTED`, `CANCELLED` -> `"governance_tickets in terminal status"`) and append-only `run_artifacts`, `ticket_comments`, and `ticket_attachments` (`"is append-only"`).
  5. **`AC-5` (`Kind: edge`)** — Preserve `SUCCESS` `report_runs` and `run_artifacts` state when a linked `SAP_REPORT_POSTING` ticket transitions to `REJECTED` or `CANCELLED`, and refuse duplicate `run_number`, `ticket_number`, `idempotency_key`, or `(report_run_id, artifact_type)` insertions via `UNIQUE` constraints.
  6. **`AC-6` (`Kind: negative`)** — Refuse cross-context access to `execution` or `governance` repositories, entities, or domain internals via ArchUnit (`LayerRulesTest` and `BoundedContextIsolationRules`).
- **Open Questions**: `none`

---

### Gate Decision Required
Please confirm if you **approve** the `Intake` phase for `p1-d-execution-and-governance-persistence` and **authorize creating the feature worktree branch** (`feature/p1-d-execution-and-governance-persistence`) via `sh .agents-v0/scripts/feature-worktree.sh p1-d-execution-and-governance-persistence`.
