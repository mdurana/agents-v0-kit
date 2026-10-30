I have launched the `requirements-analyst` subagent to draft `docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md` for story `P2-A`. Waiting for completion.
The **Intake** phase for story **`P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`)** is complete and waiting for your approval (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`).

### Artifacts Produced
- Requirements specification: [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md)
- Phase result: [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md)
- Feature state: [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` (`P2-A`, [p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L13))
- **Surface / Materiality:** `Surfaces: bff`, `Material: no`, `Size: 7`
- **User Story:**
  > As a finance preparer, I want to authenticate via Google OIDC in production or local mock login in test environments with Redis-backed HttpOnly session cookies that fail closed with HTTP 503 when the session store is unavailable, so that my portal session is protected against token theft and cache outages.
- **Acceptance Criteria (`AC-1` through `AC-7`):**
  - **AC-1 (`Kind: happy`)** — Initiate Google OIDC login (`GET /api/v1/auth/login`) and exchange callback code (`GET /api/v1/auth/callback`) with strict JWT claim/signature validation (`iss`, `aud`, `exp`, `nbf`, `kid`, algorithm allowlist rejecting `alg: none`), PostgreSQL user upsert, active role/permission resolution, Redis session storage via [`SessionStorePort.storeSession`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/SessionStorePort.
<truncated 852 bytes>
L25) and [`SessionStorePort.loadSession`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/SessionStorePort.java#L12).
  - **AC-4 (`Kind: happy`)** — Terminate session, blacklist token in Redis, clear `HttpOnly` cookie (`Max-Age=0`), and emit `AUTH_LOGOUT` audit entry on `POST /api/v1/auth/logout` (`HTTP 204 No Content`).
  - **AC-5 (`Kind: negative`)** — Refuse unauthenticated, expired, revoked, or invalid OIDC/session requests with RFC 7807 `HTTP 401 Unauthorized` (`errorCode = "AUTH_UNAUTHENTICATED"`, `X-Correlation-ID`) and record `AUTH_LOGIN_FAILURE` audit entries on failed callbacks.
  - **AC-6 (`Kind: negative`)** — Refuse `POST /api/v1/auth/mock-login` outside `local`/`test` profiles with RFC 7807 `HTTP 403 Forbidden` (`errorCode = "AUTH_FORBIDDEN"`), and reject malformed or unknown-field payloads (`additionalProperties: false`) or invalid callback query params with RFC 7807 `HTTP 400 Bad Request` (`errorCode = "VALIDATION_ERROR"`).
  - **AC-7 (`Kind: negative`)** — Fail closed with RFC 7807 `HTTP 503 Service Unavailable` (`errorCode = "SESSION_STORE_UNAVAILABLE"`) when Redis `sessionStore` or the OIDC upstream is unavailable or times out.
- **Security Triggers & Regulations:** `auth`, `public route`, sensitive login/logout audit actions; BSP Circular 982 / 1019, Philippines Data Privacy Act of 2012 (RA 10173) & GDPR, Internal GXI Enterprise Governance & Security Baseline.
- **Open Questions:** `none`

---

### Gate Action Required
Please review [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md) and confirm:
1. **Approval of the Intake phase** for `p2-a-bff-oidc-fail-closed-session-auth` (including your approver name).
2. **Authorization to create the feature worktree branch** (`feature/p2-a-bff-oidc-fail-closed-session-auth` via `sh .agents-v0/scripts/feature-worktree.sh p2-a-bff-oidc-fail-closed-session-auth`).
The **Intake** phase for story **`P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`)** is complete and waiting for your approval (`activePhase: "intake"`, `activeStatus: "awaiting_approval"`).

### Artifacts Produced
- Requirements specification: [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md)
- Phase result: [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md)
- Feature state: [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json)

### Requirements Summary
- **Milestone / Story:** `P2 — MVP / Core Features` (`P2-A`, [p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md#L13))
- **Surface / Materiality:** `Surfaces: bff`, `Material: no`, `Size: 7`
- **User Story:**
  > As a finance preparer, I want to authenticate via Google OIDC in production or local mock login in test environments with Redis-backed HttpOnly session cookies that fail closed with HTTP 503 when the session store is unavailable, so that my portal session is protected against token theft and cache outages.
- **Acceptance Criteria (`AC-1` through `AC-7`):**
  - **AC-1 (`Kind: happy`)** — Initiate Google OIDC login (`GET /api/v1/auth/login`) and exchange callback code (`GET /api/v1/auth/callback`) with strict JWT claim/signature validation (`iss`, `aud`, `exp`, `nbf`, `kid`, algorithm allowlist rejecting `alg: none`), PostgreSQL user upsert, active role/permission resolution, Redis session storage via [`SessionStorePort.storeSession`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/SessionStorePort.
<truncated 852 bytes>
L25) and [`SessionStorePort.loadSession`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/app/backend/src/main/java/com/example/app/iam/port/SessionStorePort.java#L12).
  - **AC-4 (`Kind: happy`)** — Terminate session, blacklist token in Redis, clear `HttpOnly` cookie (`Max-Age=0`), and emit `AUTH_LOGOUT` audit entry on `POST /api/v1/auth/logout` (`HTTP 204 No Content`).
  - **AC-5 (`Kind: negative`)** — Refuse unauthenticated, expired, revoked, or invalid OIDC/session requests with RFC 7807 `HTTP 401 Unauthorized` (`errorCode = "AUTH_UNAUTHENTICATED"`, `X-Correlation-ID`) and record `AUTH_LOGIN_FAILURE` audit entries on failed callbacks.
  - **AC-6 (`Kind: negative`)** — Refuse `POST /api/v1/auth/mock-login` outside `local`/`test` profiles with RFC 7807 `HTTP 403 Forbidden` (`errorCode = "AUTH_FORBIDDEN"`), and reject malformed or unknown-field payloads (`additionalProperties: false`) or invalid callback query params with RFC 7807 `HTTP 400 Bad Request` (`errorCode = "VALIDATION_ERROR"`).
  - **AC-7 (`Kind: negative`)** — Fail closed with RFC 7807 `HTTP 503 Service Unavailable` (`errorCode = "SESSION_STORE_UNAVAILABLE"`) when Redis `sessionStore` or the OIDC upstream is unavailable or times out.
- **Security Triggers & Regulations:** `auth`, `public route`, sensitive login/logout audit actions; BSP Circular 982 / 1019, Philippines Data Privacy Act of 2012 (RA 10173) & GDPR, Internal GXI Enterprise Governance & Security Baseline.
- **Open Questions:** `none`

---

### Gate Action Required
Please review [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md) and confirm:
1. **Approval of the Intake phase** for `p2-a-bff-oidc-fail-closed-session-auth` (including your approver name).
2. **Authorization to create the feature worktree branch** (`feature/p2-a-bff-oidc-fail-closed-session-auth` via `sh .agents-v0/scripts/feature-worktree.sh p2-a-bff-oidc-fail-closed-session-auth`).
