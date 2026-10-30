Subagent `requirements-analyst` has been launched to draft the requirements artifact for `p2-b-iam-rbac-sod-and-view-as`. Waiting for its completion notification.
### Intake Gate — Story `P2-B` (`p2-b-iam-rbac-sod-and-view-as`)

The **Intake** phase for story `P2-B` (**IAM RBAC, SoD & View-As Permission Overlay**) is complete and ready for your review and approval.

#### Artifacts
- Requirements artifact: [p2-b-iam-rbac-sod-and-view-as.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.md)
- Phase result: [p2-b-iam-rbac-sod-and-view-as.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.phase-result.md)
- State file: [p2-b-iam-rbac-sod-and-view-as.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

#### Summary
- **Milestone / Story:** `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `P2-B` · `Surfaces: backend` · `Material: no`
- **User Story:**
  > As a platform administrator, I want explicit operation-to-permission RBAC mapping that denies all unregistered endpoints, full role and permission CRUD with soft-delete revival, production Segregation of Duties conflict evaluation, and a read-only View-As permission overlay with clearance, so that every API route enforces least privilege and strict maker-checker separation.
- **Acceptance Criteria (`AC-1`–`AC-8`):**
  - `AC-1` (`happy`): Enforce explicit operation-to-permission RBAC route mapping for registered endpoints via `FailClosedRoutePermissionGuard` and `IamAuthorizationPort`.
  - `AC-2` (`happy`): Create, list, inspect, and update RBAC roles (`POST/GET/PUT /api/v1/iam/roles/**`) and `role_permissions` bindings with `Idempotency-Key`, `If-Match` / `ETag` optimistic concurrency, and `audit_log_entries` recording.
  - `AC-3` (`happy`): Register, list, inspect, and update RBAC route permissions (`POST/GET/PUT /api/v1/iam/permissions/**`) with `Idempotency-Key`, `If-Match`, and `audit_log_entries` recording.
  - `AC-4` (`edge`): Soft-delete (`DELETE /api/v1/iam/roles/{id}`, `DELETE /api/v1/iam/permissions/{id}`) and revive (`POST /api/v1/iam/roles/{id}/revive`, `POST /api/v1/iam/permissions/{id}/revive`) RBAC roles and permissions while preserving foreign-key references in `role_permissions` and `user_role_assignments`.
  - `AC-5` (`happy`): Manage Segregation of Duties conflict rules (`GET/PUT /api/v1/iam/sod-rules`) and evaluate production (`100%` rules enforced) vs non-production (`enforce_in_non_prod = true`) SoD matrices via `SodConflictEvaluator` (`IamSodEvaluationPort`).
  - `AC-6` (`happy`): Activate (`POST /api/v1/iam/view-as`) and clear (`DELETE /api/v1/iam/view-as`) administrative read-only `View-As` permission overlay in Redis `SessionClaims` (`effectiveViewAsRole`, `readOnlyOverlay`).
  - `AC-7` (`negative`): Refuse unmapped endpoints and unauthorized callers with `HTTP 403 AUTH_FORBIDDEN`, and refuse mutating requests under an active `View-As` overlay with `HTTP 403 VIEW_AS_MUTATION_FORBIDDEN` (while permitting `DELETE /api/v1/iam/view-as` and `POST /api/v1/auth/logout`).
  - `AC-8` (`negative`): Refuse SoD conflicts (`HTTP 403 SOD_CONFLICT_DETECTED`), unknown `{id}` paths (`HTTP 404 RESOURCE_NOT_FOUND`), stale `If-Match` headers (`HTTP 412 CONCURRENCY_CONFLICT`), duplicate/version/system-role conflicts (`HTTP 409 CONCURRENCY_CONFLICT`), and malformed/undeclared-property requests (`HTTP 400` / `HTTP 422 VALIDATION_ERROR`).
- **Security-Review Triggers & Regulations:** `RBAC`, `auth`, `any {id} path`, and sensitive actions documented; BSP Circular 982 / 1019, Philippines Data Privacy Act (RA 10173) / GDPR, and Internal GXI Security Baseline applied.
- **Open Questions:** `none`

---

**Decision requested:** Please confirm whether you **approve Intake** for `p2-b-iam-rbac-sod-and-view-as` and authorize creating the feature worktree (`feature/p2-b-iam-rbac-sod-and-view-as`).
### Intake Gate — Story `P2-B` (`p2-b-iam-rbac-sod-and-view-as`)

The **Intake** phase for story `P2-B` (**IAM RBAC, SoD & View-As Permission Overlay**) is complete and ready for your review and approval.

#### Artifacts
- Requirements artifact: [p2-b-iam-rbac-sod-and-view-as.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.md)
- Phase result: [p2-b-iam-rbac-sod-and-view-as.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.phase-result.md)
- State file: [p2-b-iam-rbac-sod-and-view-as.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-b-iam-rbac-sod-and-view-as.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

#### Summary
- **Milestone / Story:** `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `P2-B` · `Surfaces: backend` · `Material: no`
- **User Story:**
  > As a platform administrator, I want explicit operation-to-permission RBAC mapping that denies all unregistered endpoints, full role and permission CRUD with soft-delete revival, production Segregation of Duties conflict evaluation, and a read-only View-As permission overlay with clearance, so that every API route enforces least privilege and strict maker-checker separation.
- **Acceptance Criteria (`AC-1`–`AC-8`):**
  - `AC-1` (`happy`): Enforce explicit operation-to-permission RBAC route mapping for registered endpoints via `FailClosedRoutePermissionGuard` and `IamAuthorizationPort`.
  - `AC-2` (`happy`): Create, list, inspect, and update RBAC roles (`POST/GET/PUT /api/v1/iam/roles/**`) and `role_permissions` bindings with `Idempotency-Key`, `If-Match` / `ETag` optimistic concurrency, and `audit_log_entries` recording.
  - `AC-3` (`happy`): Register, list, inspect, and update RBAC route permissions (`POST/GET/PUT /api/v1/iam/permissions/**`) with `Idempotency-Key`, `If-Match`, and `audit_log_entries` recording.
  - `AC-4` (`edge`): Soft-delete (`DELETE /api/v1/iam/roles/{id}`, `DELETE /api/v1/iam/permissions/{id}`) and revive (`POST /api/v1/iam/roles/{id}/revive`, `POST /api/v1/iam/permissions/{id}/revive`) RBAC roles and permissions while preserving foreign-key references in `role_permissions` and `user_role_assignments`.
  - `AC-5` (`happy`): Manage Segregation of Duties conflict rules (`GET/PUT /api/v1/iam/sod-rules`) and evaluate production (`100%` rules enforced) vs non-production (`enforce_in_non_prod = true`) SoD matrices via `SodConflictEvaluator` (`IamSodEvaluationPort`).
  - `AC-6` (`happy`): Activate (`POST /api/v1/iam/view-as`) and clear (`DELETE /api/v1/iam/view-as`) administrative read-only `View-As` permission overlay in Redis `SessionClaims` (`effectiveViewAsRole`, `readOnlyOverlay`).
  - `AC-7` (`negative`): Refuse unmapped endpoints and unauthorized callers with `HTTP 403 AUTH_FORBIDDEN`, and refuse mutating requests under an active `View-As` overlay with `HTTP 403 VIEW_AS_MUTATION_FORBIDDEN` (while permitting `DELETE /api/v1/iam/view-as` and `POST /api/v1/auth/logout`).
  - `AC-8` (`negative`): Refuse SoD conflicts (`HTTP 403 SOD_CONFLICT_DETECTED`), unknown `{id}` paths (`HTTP 404 RESOURCE_NOT_FOUND`), stale `If-Match` headers (`HTTP 412 CONCURRENCY_CONFLICT`), duplicate/version/system-role conflicts (`HTTP 409 CONCURRENCY_CONFLICT`), and malformed/undeclared-property requests (`HTTP 400` / `HTTP 422 VALIDATION_ERROR`).
- **Security-Review Triggers & Regulations:** `RBAC`, `auth`, `any {id} path`, and sensitive actions documented; BSP Circular 982 / 1019, Philippines Data Privacy Act (RA 10173) / GDPR, and Internal GXI Security Baseline applied.
- **Open Questions:** `none`

---

**Decision requested:** Please confirm whether you **approve Intake** for `p2-b-iam-rbac-sod-and-view-as` and authorize creating the feature worktree (`feature/p2-b-iam-rbac-sod-and-view-as`).
