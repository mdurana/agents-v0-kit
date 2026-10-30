Launching the `requirements-analyst` subagent (`spec-intake`) to draft `docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.md`. Waiting for completion.
The **Intake** phase (`/v0-intake`) for story **`P1-C`** (`p1-c-configuration-and-seeded-definitions-persistence`) is complete and awaiting your approval.

### Artifacts Produced
- **Requirements Artifact**: [p1-c-configuration-and-seeded-definitions-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.md)
- **Phase Result**: [p1-c-configuration-and-seeded-definitions-persistence.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.phase-result.md)
- **State File**: [p1-c-configuration-and-seeded-definitions-persistence.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P1 — Contracts & Data Models` ([p1-contracts-and-data-models.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p1-contracts-and-data-models.md)) · `P1-C`
- **Surface & Materiality**: `Surfaces: backend` · `Material: no`
- **User Story**:
  > As a finance preparer, I want Flyway physical persistence migrations for report definitions, immutable JSON recipe versions, Asia/Manila schedule configurations, and versioned reference lookup tables pre-seeded with the five MVP Funding Cost Summary commission report definitions and their 1st-of-month schedules, so that the Funding Cost pipeline is ready for day-one execution.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **`AC-1` (`happy`)**: Migrate `report_definitions` and `recipe_versions` tables with UUID PKs, unique constraints on `definition_code` and `(report_definition_id, version_number)`, JSONB schema/rule columns, `checksum_sha256`, foreign keys (`fk_recipes_definition`, `fk_report_definitions_active_recipe`, 
<truncated 488 bytes>
nstraints on `table_code`, `(reference_table_id, version_number)`, `(reference_table_version_id, row_index)`, and `(reference_table_version_id, row_key)`, JSONB columns, and foreign keys.
  - **`AC-4` (`happy`)**: Deterministically seed the five MVP Funding Cost Summary commission report definitions (*Cashout Offline*, *Cashout Online*, *Cashin Offline*, *Cashin Online*, and *Real Time*), their initial `ACTIVE` `v1` `recipe_versions` rows, and their 1st-of-month `Asia/Manila` `schedule_configs` rows.
  - **`AC-5` (`negative`)**: Refuse `UPDATE` of immutable payload columns or `DELETE` on published (`ACTIVE` or `SUPERSEDED`) `recipe_versions`, `reference_table_versions`, and `reference_table_rows` via database immutability triggers (`"is immutable once published"`), and refuse non-`Asia/Manila` schedule timezones via `chk_schedule_configs_timezone_manila`.
  - **`AC-6` (`edge`)**: Preserve `SUPERSEDED` versions intact during atomic active-version cutover (`active_recipe_version_id` and `active_version_id`) for 13-month historical auditability, and reject duplicate codes or version numbers via `UNIQUE` constraints.
  - **`AC-7` (`negative`)**: Refuse cross-context access to `com.example.app.configuration.repository..`, `..entity..`, or `..domain..` internals from `iam`, `execution`, `governance`, or `audit` via ArchUnit (`LayerRulesTest` / `BoundedContextIsolationRules`).
- **Open Questions**: `none`

---

### Approval Gate
Please review [p1-c-configuration-and-seeded-definitions-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.md) and confirm:
1. Do you **approve** the Intake requirements for `p1-c-configuration-and-seeded-definitions-persistence` (and provide your approver name)?
2. Do you **authorize creating the feature worktree/branch** (`feature/p1-c-configuration-and-seeded-definitions-persistence`) via `sh .agents-v0/scripts/feature-worktree.sh p1-c-configuration-and-seeded-definitions-persistence`?
The **Intake** phase (`/v0-intake`) for story **`P1-C`** (`p1-c-configuration-and-seeded-definitions-persistence`) is complete and awaiting your approval.

### Artifacts Produced
- **Requirements Artifact**: [p1-c-configuration-and-seeded-definitions-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.md)
- **Phase Result**: [p1-c-configuration-and-seeded-definitions-persistence.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.phase-result.md)
- **State File**: [p1-c-configuration-and-seeded-definitions-persistence.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story**: `P1 — Contracts & Data Models` ([p1-contracts-and-data-models.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p1-contracts-and-data-models.md)) · `P1-C`
- **Surface & Materiality**: `Surfaces: backend` · `Material: no`
- **User Story**:
  > As a finance preparer, I want Flyway physical persistence migrations for report definitions, immutable JSON recipe versions, Asia/Manila schedule configurations, and versioned reference lookup tables pre-seeded with the five MVP Funding Cost Summary commission report definitions and their 1st-of-month schedules, so that the Funding Cost pipeline is ready for day-one execution.
- **Acceptance Criteria (`AC-1` through `AC-7`)**:
  - **`AC-1` (`happy`)**: Migrate `report_definitions` and `recipe_versions` tables with UUID PKs, unique constraints on `definition_code` and `(report_definition_id, version_number)`, JSONB schema/rule columns, `checksum_sha256`, foreign keys (`fk_recipes_definition`, `fk_report_definitions_active_recipe`, 
<truncated 488 bytes>
nstraints on `table_code`, `(reference_table_id, version_number)`, `(reference_table_version_id, row_index)`, and `(reference_table_version_id, row_key)`, JSONB columns, and foreign keys.
  - **`AC-4` (`happy`)**: Deterministically seed the five MVP Funding Cost Summary commission report definitions (*Cashout Offline*, *Cashout Online*, *Cashin Offline*, *Cashin Online*, and *Real Time*), their initial `ACTIVE` `v1` `recipe_versions` rows, and their 1st-of-month `Asia/Manila` `schedule_configs` rows.
  - **`AC-5` (`negative`)**: Refuse `UPDATE` of immutable payload columns or `DELETE` on published (`ACTIVE` or `SUPERSEDED`) `recipe_versions`, `reference_table_versions`, and `reference_table_rows` via database immutability triggers (`"is immutable once published"`), and refuse non-`Asia/Manila` schedule timezones via `chk_schedule_configs_timezone_manila`.
  - **`AC-6` (`edge`)**: Preserve `SUPERSEDED` versions intact during atomic active-version cutover (`active_recipe_version_id` and `active_version_id`) for 13-month historical auditability, and reject duplicate codes or version numbers via `UNIQUE` constraints.
  - **`AC-7` (`negative`)**: Refuse cross-context access to `com.example.app.configuration.repository..`, `..entity..`, or `..domain..` internals from `iam`, `execution`, `governance`, or `audit` via ArchUnit (`LayerRulesTest` / `BoundedContextIsolationRules`).
- **Open Questions**: `none`

---

### Approval Gate
Please review [p1-c-configuration-and-seeded-definitions-persistence.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p1-c-configuration-and-seeded-definitions-persistence.md) and confirm:
1. Do you **approve** the Intake requirements for `p1-c-configuration-and-seeded-definitions-persistence` (and provide your approver name)?
2. Do you **authorize creating the feature worktree/branch** (`feature/p1-c-configuration-and-seeded-definitions-persistence`) via `sh .agents-v0/scripts/feature-worktree.sh p1-c-configuration-and-seeded-definitions-persistence`?
