The **Intake** phase (`/v0-intake`) for story **P2-P** (`p2-p-frontend-shell-dashboard-and-notifications`) is complete and awaiting your approval.

### Artifacts Produced
- [p2-p-frontend-shell-dashboard-and-notifications.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.md)
- [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md)
- [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` / `P2-P` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md))
- **Surfaces & Materiality:** `Surfaces: frontend` (`app/frontend/` — React 19, TypeScript 5.9, Vite 7, Vitest), `Material: no`
- **User Story:**
  > As a finance preparer, I want the portal shell implemented with GCash design tokens, permission-filtered navigation menus, RFC 7807 problem detail modals displaying correlation IDs, an in-app notification bell drawer, and an empty-state Dashboard UI displaying my_open_runs, recent_runs, my_todo_count, awaiting_approval, and failed_scheduled_jobs widgets, so that I can navigate authorized workspaces and monitor operational status at a glance.
- **Acceptance Criteria (`AC-1` through `AC-7`, 5 happy + 2 negative):**
  - **AC-1 (`happy` — Session bootstrap, GCash shell tokens & permission-filtered navigation):** Calls `GET /api/v1/auth/me` with `credentials: "include"` and `X-Correlation-ID`, keeps session state strictly in React memory (never writing tokens/secrets/RBAC matrices to `localStora
<truncated 1145 bytes>
splays explicit empty states.
  - **AC-4 (`happy` — Mark single or all notifications as read):** Invokes `POST /api/v1/notifications/{id}/read` (`{"isRead": true}`) and `POST /api/v1/notifications/read-all` with `Idempotency-Key` headers, updating read state and the header unread badge count.
  - **AC-5 (`happy` — Logout & multi-user session isolation):** Invokes `POST /api/v1/auth/logout` (`HTTP 204`), clears in-memory state and web storage, and guarantees `User A` logout $\rightarrow$ `User B` login displays only `User B` data (`vapt-webapp.mdc` F1).
  - **AC-6 (`negative` — RFC 7807 Problem Detail modal, BOLA refusal & View-As mutation block):** Opens a focus-trapped `alertdialog` modal showing `title`, `status`, `detail`, `errorCode`, `instance`, `timestamp`, and copyable `correlationId` across `400`/`403`/`404`/`409`/`422`/`503` responses, treating `403`/`404` on `/api/v1/notifications/{id}` as access-denied/not-found without leaking data (`vapt-webapp.mdc` F8) and blocking notification mutations under `readOnlyOverlay = true` (`VIEW_AS_MUTATION_FORBIDDEN`).
  - **AC-7 (`negative` — Direct route authorization guards & HTTP 401 expiration):** Redirects unauthenticated visitors or expired `HTTP 401` sessions to sign-in (`GET /api/v1/auth/login` / `POST /api/v1/auth/mock-login`) and blocks direct navigation to unauthorized workspace routes with a deterministic `403 Access Denied` boundary (`vapt-webapp.mdc` F4).
- **UX, Security & Compliance:** WCAG 2.1 AA accessibility requirements, desktop/tablet responsive breakpoints (`1280x800`–`1920x1080` down to `768px`), GCash token specification, `UX-AC-1`..`UX-AC-4`, security triggers (`auth`, `RBAC`, `any {id} path`), and BSP Circular 982/1019, Philippines DPA (RA 10173)/GDPR, and Internal GXI baseline regulations recorded. Open questions: `none`.

Please review and confirm if you **approve** the `Intake` phase for `p2-p-frontend-shell-dashboard-and-notifications` and authorize creating the `feature/p2-p-frontend-shell-dashboard-and-notifications` worktree.
The **Intake** phase (`/v0-intake`) for story **P2-P** (`p2-p-frontend-shell-dashboard-and-notifications`) is complete and awaiting your approval.

### Artifacts Produced
- [p2-p-frontend-shell-dashboard-and-notifications.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.md)
- [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md)
- [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json) (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` / `P2-P` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md))
- **Surfaces & Materiality:** `Surfaces: frontend` (`app/frontend/` — React 19, TypeScript 5.9, Vite 7, Vitest), `Material: no`
- **User Story:**
  > As a finance preparer, I want the portal shell implemented with GCash design tokens, permission-filtered navigation menus, RFC 7807 problem detail modals displaying correlation IDs, an in-app notification bell drawer, and an empty-state Dashboard UI displaying my_open_runs, recent_runs, my_todo_count, awaiting_approval, and failed_scheduled_jobs widgets, so that I can navigate authorized workspaces and monitor operational status at a glance.
- **Acceptance Criteria (`AC-1` through `AC-7`, 5 happy + 2 negative):**
  - **AC-1 (`happy` — Session bootstrap, GCash shell tokens & permission-filtered navigation):** Calls `GET /api/v1/auth/me` with `credentials: "include"` and `X-Correlation-ID`, keeps session state strictly in React memory (never writing tokens/secrets/RBAC matrices to `localStora
<truncated 1145 bytes>
splays explicit empty states.
  - **AC-4 (`happy` — Mark single or all notifications as read):** Invokes `POST /api/v1/notifications/{id}/read` (`{"isRead": true}`) and `POST /api/v1/notifications/read-all` with `Idempotency-Key` headers, updating read state and the header unread badge count.
  - **AC-5 (`happy` — Logout & multi-user session isolation):** Invokes `POST /api/v1/auth/logout` (`HTTP 204`), clears in-memory state and web storage, and guarantees `User A` logout $\rightarrow$ `User B` login displays only `User B` data (`vapt-webapp.mdc` F1).
  - **AC-6 (`negative` — RFC 7807 Problem Detail modal, BOLA refusal & View-As mutation block):** Opens a focus-trapped `alertdialog` modal showing `title`, `status`, `detail`, `errorCode`, `instance`, `timestamp`, and copyable `correlationId` across `400`/`403`/`404`/`409`/`422`/`503` responses, treating `403`/`404` on `/api/v1/notifications/{id}` as access-denied/not-found without leaking data (`vapt-webapp.mdc` F8) and blocking notification mutations under `readOnlyOverlay = true` (`VIEW_AS_MUTATION_FORBIDDEN`).
  - **AC-7 (`negative` — Direct route authorization guards & HTTP 401 expiration):** Redirects unauthenticated visitors or expired `HTTP 401` sessions to sign-in (`GET /api/v1/auth/login` / `POST /api/v1/auth/mock-login`) and blocks direct navigation to unauthorized workspace routes with a deterministic `403 Access Denied` boundary (`vapt-webapp.mdc` F4).
- **UX, Security & Compliance:** WCAG 2.1 AA accessibility requirements, desktop/tablet responsive breakpoints (`1280x800`–`1920x1080` down to `768px`), GCash token specification, `UX-AC-1`..`UX-AC-4`, security triggers (`auth`, `RBAC`, `any {id} path`), and BSP Circular 982/1019, Philippines DPA (RA 10173)/GDPR, and Internal GXI baseline regulations recorded. Open questions: `none`.

Please review and confirm if you **approve** the `Intake` phase for `p2-p-frontend-shell-dashboard-and-notifications` and authorize creating the `feature/p2-p-frontend-shell-dashboard-and-notifications` worktree.
