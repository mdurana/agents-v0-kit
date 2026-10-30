The **Intake** phase (`/v0-intake`) for story **`P2-P` (`p2-p-frontend-shell-dashboard-and-notifications`)** is complete and ready for your review (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`).

### Artifacts Produced
- Requirements specification: [p2-p-frontend-shell-dashboard-and-notifications.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.md)
- Phase result: [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md)
- State file: [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), Story `P2-P`
- **Surface & Materiality**: `Surfaces: frontend`, `Material: no`, Tier: `standard`
- **User Story**:
  > As a finance preparer, I want the portal shell implemented with GCash design tokens, permission-filtered navigation menus, RFC 7807 problem detail modals displaying correlation IDs, an in-app notification bell drawer, and an empty-state Dashboard UI displaying my_open_runs, recent_runs, my_todo_count, awaiting_approval, and failed_scheduled_jobs widgets, so that I can navigate authorized workspaces and monitor operational status at a glance.
- **Acceptance Criteria (`AC-1`–`AC-8`)**:
  - **`AC-1` (`happy`)**: Initialize portal shell with GCash design tokens, authenticated principal profile from `GET /api/v1/auth/me` (in-memory only), OIDC/mock login (`GET /api/v1/auth/login`, `POST /api/v1/auth/mock-login`), `DASHBOARD` vs `ROLE_APPLY_ONBOARDING` routing, and `POST /api/v1/aut
<truncated 59 bytes>
ered workspace navigation menus against `PrincipalSessionResponse.permissions` and display the active `View-As` read-only overlay indicator (`readOnlyOverlay === true`).
  - **`AC-3` (`happy`)**: Render empty-state and live operational count Dashboard UI widgets (`my_open_runs`, `recent_runs`, `my_todo_count`, `awaiting_approval`, `failed_scheduled_jobs`) backed by `GET /api/v1/dashboard/widgets`.
  - **`AC-4` (`happy`)**: Open in-app Notification Bell drawer, filter unread alerts, and inspect notification details via `GET /api/v1/notifications` and `GET /api/v1/notifications/{id}`.
  - **`AC-5` (`happy`)**: Mark individual or all in-app notifications as read via `POST /api/v1/notifications/{id}/read` and `POST /api/v1/notifications/read-all`.
  - **`AC-6` (`edge`)**: Handle empty notification lists, keyboard `Escape` / focus trapping and restoration on modals and drawers, and `prefers-reduced-motion: reduce`.
  - **`AC-7` (`negative`)**: Proactively disable notification mutations under `View-As` mode and intercept RFC 7807 `application/problem+json` errors (`403 AUTH_FORBIDDEN`, `403 VIEW_AS_MUTATION_FORBIDDEN`, `404 RESOURCE_NOT_FOUND`, `400`/`422 VALIDATION_ERROR`, `503 SESSION_STORE_UNAVAILABLE`) to display the Problem Detail modal with copyable `correlationId`.
  - **`AC-8` (`negative`)**: Refuse unauthenticated access on `HTTP 401 AUTH_UNAUTHENTICATED`, block direct URL navigation to unauthorized workspaces (`403 Access Denied`), and sanitize untrusted text against XSS.
- **UX, Security & Compliance**: Includes WCAG 2.1 AA requirements, desktop operator viewport/browser matrix, GCash design token palette, UX acceptance criteria, security-review triggers (`auth`, `RBAC`, `any {id} path`), and BSP / DPA / GDPR / GXI compliance mappings (`Open questions: none`).

---

### Gate Approval Request
Please confirm if you **approve the Intake requirements** for `p2-p-frontend-shell-dashboard-and-notifications` and **authorize creating the feature worktree** (`feature/p2-p-frontend-shell-dashboard-and-notifications`).
The **Intake** phase (`/v0-intake`) for story **`P2-P` (`p2-p-frontend-shell-dashboard-and-notifications`)** is complete and ready for your review (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`).

### Artifacts Produced
- Requirements specification: [p2-p-frontend-shell-dashboard-and-notifications.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.md)
- Phase result: [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md)
- State file: [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json)

### Requirements Summary
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)), Story `P2-P`
- **Surface & Materiality**: `Surfaces: frontend`, `Material: no`, Tier: `standard`
- **User Story**:
  > As a finance preparer, I want the portal shell implemented with GCash design tokens, permission-filtered navigation menus, RFC 7807 problem detail modals displaying correlation IDs, an in-app notification bell drawer, and an empty-state Dashboard UI displaying my_open_runs, recent_runs, my_todo_count, awaiting_approval, and failed_scheduled_jobs widgets, so that I can navigate authorized workspaces and monitor operational status at a glance.
- **Acceptance Criteria (`AC-1`–`AC-8`)**:
  - **`AC-1` (`happy`)**: Initialize portal shell with GCash design tokens, authenticated principal profile from `GET /api/v1/auth/me` (in-memory only), OIDC/mock login (`GET /api/v1/auth/login`, `POST /api/v1/auth/mock-login`), `DASHBOARD` vs `ROLE_APPLY_ONBOARDING` routing, and `POST /api/v1/aut
<truncated 59 bytes>
ered workspace navigation menus against `PrincipalSessionResponse.permissions` and display the active `View-As` read-only overlay indicator (`readOnlyOverlay === true`).
  - **`AC-3` (`happy`)**: Render empty-state and live operational count Dashboard UI widgets (`my_open_runs`, `recent_runs`, `my_todo_count`, `awaiting_approval`, `failed_scheduled_jobs`) backed by `GET /api/v1/dashboard/widgets`.
  - **`AC-4` (`happy`)**: Open in-app Notification Bell drawer, filter unread alerts, and inspect notification details via `GET /api/v1/notifications` and `GET /api/v1/notifications/{id}`.
  - **`AC-5` (`happy`)**: Mark individual or all in-app notifications as read via `POST /api/v1/notifications/{id}/read` and `POST /api/v1/notifications/read-all`.
  - **`AC-6` (`edge`)**: Handle empty notification lists, keyboard `Escape` / focus trapping and restoration on modals and drawers, and `prefers-reduced-motion: reduce`.
  - **`AC-7` (`negative`)**: Proactively disable notification mutations under `View-As` mode and intercept RFC 7807 `application/problem+json` errors (`403 AUTH_FORBIDDEN`, `403 VIEW_AS_MUTATION_FORBIDDEN`, `404 RESOURCE_NOT_FOUND`, `400`/`422 VALIDATION_ERROR`, `503 SESSION_STORE_UNAVAILABLE`) to display the Problem Detail modal with copyable `correlationId`.
  - **`AC-8` (`negative`)**: Refuse unauthenticated access on `HTTP 401 AUTH_UNAUTHENTICATED`, block direct URL navigation to unauthorized workspaces (`403 Access Denied`), and sanitize untrusted text against XSS.
- **UX, Security & Compliance**: Includes WCAG 2.1 AA requirements, desktop operator viewport/browser matrix, GCash design token palette, UX acceptance criteria, security-review triggers (`auth`, `RBAC`, `any {id} path`), and BSP / DPA / GDPR / GXI compliance mappings (`Open questions: none`).

---

### Gate Approval Request
Please confirm if you **approve the Intake requirements** for `p2-p-frontend-shell-dashboard-and-notifications` and **authorize creating the feature worktree** (`feature/p2-p-frontend-shell-dashboard-and-notifications`).
