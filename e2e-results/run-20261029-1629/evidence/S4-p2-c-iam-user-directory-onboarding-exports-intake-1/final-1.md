I have launched the `requirements-analyst` subagent (`3412588f-60a5-4e7a-8c77-03c45f173443`) to draft the Intake requirements artifact [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md) for Story `P2-C`. Waiting for the subagent to complete and report back.
### Intake Gate — Story `P2-C` (`p2-c-iam-user-directory-onboarding-exports`)

The Intake requirements artifact and state have been prepared and set to `awaiting_approval`:

- **Requirements Artifact:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md)
- **Phase Result:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md)
- **State File:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)
- **Milestone / Story:** `P2 — MVP / Core Features` ([`p2-mvp-core-features.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md), Story `P2-C`, `Surfaces: backend`, `Material: no`, `Size: 8`)

#### User Story
> As a platform administrator, I want user filtering, role assignments with optional expiry, self-lock protection, Google Workspace or mock directory lookups, zero-role Role Apply onboarding submission, and user/role CSV access review exports, so that workforce access lifecycle and compliance reviews are centrally governed.

#### Acceptance Criteria Summary (`AC-1` – `AC-8`)
| ID | Kind | Summary |
|----|------|---------|
| **AC-1** | `happy` | `GET /api/v1/iam/users` offset pagination (`page`, `limit` up to `100`) and case-insensitive substring search across `workspace_email`, `display_name`, and `department`. |
| **AC-2** | `happy` | `GET /api/v1/iam/users/{id}` and `PATCH /api/v1/iam/users/{id}` (`If-Match`, `UserStatusUpdateRequest`) updating active status/department
<truncated 1039 bytes>
s/users` and `GET /api/v1/iam/exports/roles` streaming UTF-8 CSV reports (`text/csv`) with spreadsheet formula-injection neutralization (`'`), auditing `IAM_USERS_EXPORTED_CSV` / `IAM_ROLES_EXPORTED_CSV`, and excluding expired `user_role_assignments` (`expires_at <= now()`) from effective session permissions while preserving historical rows. |
| **AC-7** | `negative` | Refusal of administrator self-deactivation and self-admin-role removal/expiry (`HTTP 409 SELF_LOCKOUT_PREVENTED`, audited as `IAM_SELF_LOCKOUT_REFUSED` with `noRollbackFor` per `L-004`), unauthorized callers (`HTTP 403 AUTH_FORBIDDEN`), and mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`). |
| **AC-8** | `negative` | Refusal of SoD conflicts (`HTTP 403 SOD_CONFLICT_DETECTED`, audited as `SOD_CONFLICT_REFUSED`), unknown user `{id}` (`HTTP 404 RESOURCE_NOT_FOUND`), stale `If-Match` (`HTTP 412 CONCURRENCY_CONFLICT`), version mismatch / duplicate pending ticket / idempotency conflict (`HTTP 409`), invalid/inactive `roleId`s / past `expiresAt` / short `query` / missing headers / undeclared JSON fields (`HTTP 400` / `HTTP 422 VALIDATION_ERROR`), and corporate directory outage (`HTTP 503 DIRECTORY_UNAVAILABLE`). |

- **Regulations:** BSP Circular 982 / 1019, Philippines Data Privacy Act of 2012 (RA 10173) & GDPR, Internal GXI Enterprise Governance & Security Baseline (`security-baseline.mdc` §1, §2, §3, §5, §7, §8, §11, §12; VAPT F4, F8, F9, F10).
- **Security-Review Triggers:** `RBAC`, `auth`, `any {id} path`, and sensitive actions (user status toggle, role assignment/revocation, self-service role application submission, and access review CSV export).
- **Open Questions:** `none`

---

**Decision requested:**
Please confirm if you **approve the Intake gate** for `p2-c-iam-user-directory-onboarding-exports` (and provide the approver name if different from `mdurana`) and **authorize creating the feature worktree branch** (`sh .agents-v0/scripts/feature-worktree.sh p2-c-iam-user-directory-onboarding-exports`).
### Intake Gate — Story `P2-C` (`p2-c-iam-user-directory-onboarding-exports`)

The Intake requirements artifact and state have been prepared and set to `awaiting_approval`:

- **Requirements Artifact:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.md)
- **Phase Result:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md)
- **State File:** [`docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)
- **Milestone / Story:** `P2 — MVP / Core Features` ([`p2-mvp-core-features.md`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md), Story `P2-C`, `Surfaces: backend`, `Material: no`, `Size: 8`)

#### User Story
> As a platform administrator, I want user filtering, role assignments with optional expiry, self-lock protection, Google Workspace or mock directory lookups, zero-role Role Apply onboarding submission, and user/role CSV access review exports, so that workforce access lifecycle and compliance reviews are centrally governed.

#### Acceptance Criteria Summary (`AC-1` – `AC-8`)
| ID | Kind | Summary |
|----|------|---------|
| **AC-1** | `happy` | `GET /api/v1/iam/users` offset pagination (`page`, `limit` up to `100`) and case-insensitive substring search across `workspace_email`, `display_name`, and `department`. |
| **AC-2** | `happy` | `GET /api/v1/iam/users/{id}` and `PATCH /api/v1/iam/users/{id}` (`If-Match`, `UserStatusUpdateRequest`) updating active status/department
<truncated 1039 bytes>
s/users` and `GET /api/v1/iam/exports/roles` streaming UTF-8 CSV reports (`text/csv`) with spreadsheet formula-injection neutralization (`'`), auditing `IAM_USERS_EXPORTED_CSV` / `IAM_ROLES_EXPORTED_CSV`, and excluding expired `user_role_assignments` (`expires_at <= now()`) from effective session permissions while preserving historical rows. |
| **AC-7** | `negative` | Refusal of administrator self-deactivation and self-admin-role removal/expiry (`HTTP 409 SELF_LOCKOUT_PREVENTED`, audited as `IAM_SELF_LOCKOUT_REFUSED` with `noRollbackFor` per `L-004`), unauthorized callers (`HTTP 403 AUTH_FORBIDDEN`), and mutating calls under an active `View-As` overlay (`HTTP 403 VIEW_AS_MUTATION_FORBIDDEN`). |
| **AC-8** | `negative` | Refusal of SoD conflicts (`HTTP 403 SOD_CONFLICT_DETECTED`, audited as `SOD_CONFLICT_REFUSED`), unknown user `{id}` (`HTTP 404 RESOURCE_NOT_FOUND`), stale `If-Match` (`HTTP 412 CONCURRENCY_CONFLICT`), version mismatch / duplicate pending ticket / idempotency conflict (`HTTP 409`), invalid/inactive `roleId`s / past `expiresAt` / short `query` / missing headers / undeclared JSON fields (`HTTP 400` / `HTTP 422 VALIDATION_ERROR`), and corporate directory outage (`HTTP 503 DIRECTORY_UNAVAILABLE`). |

- **Regulations:** BSP Circular 982 / 1019, Philippines Data Privacy Act of 2012 (RA 10173) & GDPR, Internal GXI Enterprise Governance & Security Baseline (`security-baseline.mdc` §1, §2, §3, §5, §7, §8, §11, §12; VAPT F4, F8, F9, F10).
- **Security-Review Triggers:** `RBAC`, `auth`, `any {id} path`, and sensitive actions (user status toggle, role assignment/revocation, self-service role application submission, and access review CSV export).
- **Open Questions:** `none`

---

**Decision requested:**
Please confirm if you **approve the Intake gate** for `p2-c-iam-user-directory-onboarding-exports` (and provide the approver name if different from `mdurana`) and **authorize creating the feature worktree branch** (`sh .agents-v0/scripts/feature-worktree.sh p2-c-iam-user-directory-onboarding-exports`).
