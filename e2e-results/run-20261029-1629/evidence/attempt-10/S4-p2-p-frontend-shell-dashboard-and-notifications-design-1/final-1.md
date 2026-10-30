The **Design** phase (`/v0-design`) for Story **P2-P** (`p2-p-frontend-shell-dashboard-and-notifications` — *Frontend Shell, Dashboard & In-App Notifications*) is complete and ready for your review at the **Design Gate**.

### Produced Design Artifacts

1. **Feature OpenAPI 3.0.3 Contract Draft:** [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/openapi.yaml)
   - Self-contained contract draft covering all 10 operations consumed by the portal shell, Dashboard, and Notification Bell drawer: `initiateOidcLogin` (`GET /api/v1/auth/login`), `handleOidcCallback` (`GET /api/v1/auth/callback`), `getCurrentPrincipal` (`GET /api/v1/auth/me`), `logoutSession` (`POST /api/v1/auth/logout`), `mockLogin` (`POST /api/v1/auth/mock-login`), `getDashboardWidgets` (`GET /api/v1/dashboard/widgets`), `listNotifications` (`GET /api/v1/notifications`), `getNotificationById` (`GET /api/v1/notifications/{id}`), `markNotificationRead` (`POST /api/v1/notifications/{id}/read`), and `markAllNotificationsRead` (`POST /api/v1/notifications/read-all`).
   - Enforces `additionalProperties: false` on write request schemas (`MockLoginRequest`, `NotificationReadRequest`), `Idempotency-Key` headers on `POST` mutations, `X-Correlation-ID` response headers, and RFC 7807 `ProblemDetail` (`application/problem+json`).

2. **Architecture & Traceability Specification:** [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/design.md), [ADR 0021](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/adr/0021-frontend-shell-dashboard-and-notifications.md) (`Status: Proposed`), & [frontend-shell.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/
<truncated 4445 bytes>
ns/mockups/notifications-loading.html)
     - [notifications-empty.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-empty.html)
     - [notifications-populated.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-populated.html)
     - [notifications-error.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-error.html)

4. **Design Review Report & State:** [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/review.md), [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md), and [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json)
   - `design-reviewer` verdict: **PASS** (`0` open `Critical` findings).
   - State synced to `activePhase: "design"`, `activeStatus: "awaiting_approval"`.

---

### Approval Gate

Please review the design artifacts and reply to **approve** the Design phase for `p2-p-frontend-shell-dashboard-and-notifications` (or share any requested adjustments) before we mark ADR 0021 `Accepted`, record the Design approval, and proceed to `/v0-build p2-p-frontend-shell-dashboard-and-notifications`.
The **Design** phase (`/v0-design`) for Story **P2-P** (`p2-p-frontend-shell-dashboard-and-notifications` — *Frontend Shell, Dashboard & In-App Notifications*) is complete and ready for your review at the **Design Gate**.

### Produced Design Artifacts

1. **Feature OpenAPI 3.0.3 Contract Draft:** [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/openapi.yaml)
   - Self-contained contract draft covering all 10 operations consumed by the portal shell, Dashboard, and Notification Bell drawer: `initiateOidcLogin` (`GET /api/v1/auth/login`), `handleOidcCallback` (`GET /api/v1/auth/callback`), `getCurrentPrincipal` (`GET /api/v1/auth/me`), `logoutSession` (`POST /api/v1/auth/logout`), `mockLogin` (`POST /api/v1/auth/mock-login`), `getDashboardWidgets` (`GET /api/v1/dashboard/widgets`), `listNotifications` (`GET /api/v1/notifications`), `getNotificationById` (`GET /api/v1/notifications/{id}`), `markNotificationRead` (`POST /api/v1/notifications/{id}/read`), and `markAllNotificationsRead` (`POST /api/v1/notifications/read-all`).
   - Enforces `additionalProperties: false` on write request schemas (`MockLoginRequest`, `NotificationReadRequest`), `Idempotency-Key` headers on `POST` mutations, `X-Correlation-ID` response headers, and RFC 7807 `ProblemDetail` (`application/problem+json`).

2. **Architecture & Traceability Specification:** [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/design.md), [ADR 0021](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/adr/0021-frontend-shell-dashboard-and-notifications.md) (`Status: Proposed`), & [frontend-shell.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/
<truncated 4445 bytes>
ns/mockups/notifications-loading.html)
     - [notifications-empty.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-empty.html)
     - [notifications-populated.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-populated.html)
     - [notifications-error.html](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/mockups/notifications-error.html)

4. **Design Review Report & State:** [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/design/p2-p-frontend-shell-dashboard-and-notifications/review.md), [p2-p-frontend-shell-dashboard-and-notifications.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.phase-result.md), and [p2-p-frontend-shell-dashboard-and-notifications.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-p-frontend-shell-dashboard-and-notifications/docs/agents-v0/requirements/p2-p-frontend-shell-dashboard-and-notifications.state.json)
   - `design-reviewer` verdict: **PASS** (`0` open `Critical` findings).
   - State synced to `activePhase: "design"`, `activeStatus: "awaiting_approval"`.

---

### Approval Gate

Please review the design artifacts and reply to **approve** the Design phase for `p2-p-frontend-shell-dashboard-and-notifications` (or share any requested adjustments) before we mark ADR 0021 `Accepted`, record the Design approval, and proceed to `/v0-build p2-p-frontend-shell-dashboard-and-notifications`.
