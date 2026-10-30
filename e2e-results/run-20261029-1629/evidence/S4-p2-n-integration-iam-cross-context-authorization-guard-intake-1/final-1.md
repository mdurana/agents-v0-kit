The **Intake** phase for **`p2-n-integration-iam-cross-context-authorization-guard`** (`Story: P2-N` — *Cross-Context Integration: IAM Cross-Context Authorization Guard*) is complete and awaiting your approval.

### Artifacts Produced
- **Requirements Specification:** [p2-n-integration-iam-cross-context-authorization-guard.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.md)
- **Phase Result:** [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md)
- **Feature State:** [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` / `P2-N` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L26))
- **Surfaces / Material:** `Surfaces: backend`, `Material: no`
- **User Story:**
  > As a platform administrator, I want execution, configuration, and governance endpoints to enforce fail-closed permission checks, same-role peer BOLA instance verification, and administrative View-As read-only mutation blocking via IamAuthorizationPort, so that unauthorized routes and mutating calls under a View-As overlay are deterministically denied across all contexts.
- **Acceptance Criteria (`AC-1` through `AC-6`):**
  - **AC-1 (`happy`):** Enforce fail-closed operation-to-permission route evaluation via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java) and [`FailC
<truncated 284 bytes>
ntext `GET` reads to the active `View-As` role permissions via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java) and restore full administrator permissions on `DELETE /api/v1/iam/view-as`.
  - **AC-3 (`happy`):** Authorize owner, assignee, and manager instance actions across `execution` (`POST /api/v1/runs/{id}/cancel`, `POST /api/v1/runs/{id}/endorse`) and `governance` (`POST /api/v1/tickets/{id}/cancel`, `PUT/POST /api/v1/tickets/{id}/owner`, `POST /api/v1/tickets/{id}/reassign`) `{id}` endpoints via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java).
  - **AC-4 (`edge`):** Immediately revoke cross-context route access on role/permission soft-delete or `user_role_assignments.expires_at` expiry (`HTTP 403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and fail closed with `HTTP 503 SESSION_STORE_UNAVAILABLE` on session/authorization store outages.
  - **AC-5 (`negative`):** Refuse same-role peer BOLA instance violations across `execution` and `governance` `{id}` endpoints with `HTTP 403 AUTH_FORBIDDEN` and `AUTHZ_DENIED` audit logging.
  - **AC-6 (`negative`):** Refuse unauthenticated callers (`HTTP 401 AUTH_UNAUTHENTICATED`), unmapped routes and missing route permissions (`HTTP 403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and all state-mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN` + `AUTHZ_DENIED` + `VIEW_AS_MUTATION_BLOCKED`) across `execution`, `configuration`, and `governance`.
- **Open Questions:** `none`

Please review and confirm:
1. Do you **approve** the **Intake** phase for `p2-n-integration-iam-cross-context-authorization-guard`?
2. Do you **authorize** creating the feature worktree branch `feature/p2-n-integration-iam-cross-context-authorization-guard` via `sh .agents-v0/scripts/feature-worktree.sh p2-n-integration-iam-cross-context-authorization-guard`?
The **Intake** phase for **`p2-n-integration-iam-cross-context-authorization-guard`** (`Story: P2-N` — *Cross-Context Integration: IAM Cross-Context Authorization Guard*) is complete and awaiting your approval.

### Artifacts Produced
- **Requirements Specification:** [p2-n-integration-iam-cross-context-authorization-guard.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.md)
- **Phase Result:** [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md)
- **Feature State:** [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` / `P2-N` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L26))
- **Surfaces / Material:** `Surfaces: backend`, `Material: no`
- **User Story:**
  > As a platform administrator, I want execution, configuration, and governance endpoints to enforce fail-closed permission checks, same-role peer BOLA instance verification, and administrative View-As read-only mutation blocking via IamAuthorizationPort, so that unauthorized routes and mutating calls under a View-As overlay are deterministically denied across all contexts.
- **Acceptance Criteria (`AC-1` through `AC-6`):**
  - **AC-1 (`happy`):** Enforce fail-closed operation-to-permission route evaluation via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java) and [`FailC
<truncated 284 bytes>
ntext `GET` reads to the active `View-As` role permissions via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java) and restore full administrator permissions on `DELETE /api/v1/iam/view-as`.
  - **AC-3 (`happy`):** Authorize owner, assignee, and manager instance actions across `execution` (`POST /api/v1/runs/{id}/cancel`, `POST /api/v1/runs/{id}/endorse`) and `governance` (`POST /api/v1/tickets/{id}/cancel`, `PUT/POST /api/v1/tickets/{id}/owner`, `POST /api/v1/tickets/{id}/reassign`) `{id}` endpoints via [`IamAuthorizationPort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/IamAuthorizationPort.java).
  - **AC-4 (`edge`):** Immediately revoke cross-context route access on role/permission soft-delete or `user_role_assignments.expires_at` expiry (`HTTP 403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and fail closed with `HTTP 503 SESSION_STORE_UNAVAILABLE` on session/authorization store outages.
  - **AC-5 (`negative`):** Refuse same-role peer BOLA instance violations across `execution` and `governance` `{id}` endpoints with `HTTP 403 AUTH_FORBIDDEN` and `AUTHZ_DENIED` audit logging.
  - **AC-6 (`negative`):** Refuse unauthenticated callers (`HTTP 401 AUTH_UNAUTHENTICATED`), unmapped routes and missing route permissions (`HTTP 403 AUTH_FORBIDDEN` + `AUTHZ_DENIED`), and all state-mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN` + `AUTHZ_DENIED` + `VIEW_AS_MUTATION_BLOCKED`) across `execution`, `configuration`, and `governance`.
- **Open Questions:** `none`

Please review and confirm:
1. Do you **approve** the **Intake** phase for `p2-n-integration-iam-cross-context-authorization-guard`?
2. Do you **authorize** creating the feature worktree branch `feature/p2-n-integration-iam-cross-context-authorization-guard` via `sh .agents-v0/scripts/feature-worktree.sh p2-n-integration-iam-cross-context-authorization-guard`?
