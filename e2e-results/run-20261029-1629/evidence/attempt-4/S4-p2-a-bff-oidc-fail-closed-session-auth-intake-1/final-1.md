I have initialized the Intake phase (`in_progress`) for `p2-a-bff-oidc-fail-closed-session-auth` and launched the `requirements-analyst` subagent to produce the requirements artifact `docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md`. Waiting for the subagent to complete.
The **Intake** phase (`/v0-intake`) for story **`P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`)** is complete and ready for your review (`status: awaiting_approval`).

### Artifacts Produced
- **Requirements Specification**: [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md)
- **Phase Result**: [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md)
- **State File**: [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json)

### Summary of Requirements
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `P2-A` · `Surfaces: bff` · `Material: no` · `Size: 7`
- **User Story**:
  > As a finance preparer, I want to authenticate via Google OIDC in production or local mock login in test environments with Redis-backed HttpOnly session cookies that fail closed with HTTP 503 when the session store is unavailable, so that my portal session is protected against token theft and cache outages.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **`AC-1` (`happy`)**: `GET /api/v1/auth/login` initiates Google OIDC Authorization Code + PKCE flow (`HTTP 302`), and `GET /api/v1/auth/callback` validates `state`, exchanges `code`, verifies JWT claims (`RS256` allowlist, `iss`, `aud`, `exp`, `nbf`, trusted JWKS `kid`), updates `users.last_login_at`, stores `portal:session:<sessionId>` in Redis, issues an `HttpOnly; Secure; SameSite=Lax` cookie, records an authentication success audit entry, and redirects (`HTTP 302`) to the portal shell.
  - **`AC-2` (`happy`)**: `POST /api/v1/auth/mock-login` (in `local`/`test` profiles) and `GET /api/v1/auth/me` return `HTTP 200` `PrincipalSessionResponse` with active `roles`, `permissions`, `readOnlyOverlay: false`, and `redirectView: "DASHBOARD"`.
  - **`AC-3` (`edge`)**: Authenticated principals with zero active roles (or expired/revoked assignments) receive `redirectView: "ROLE_APPLY_ONBOARDING"` with `roles: []` and `permissions: []`.
  - **`AC-4` (`happy`)**: `POST /api/v1/auth/logout` deletes `portal:session:<sessionId>`, writes `portal:blacklist:<sessionId>` in Redis, clears the cookie (`Max-Age=0`), logs a logout audit event, returns `HTTP 204`, and causes replayed requests to fail with `HTTP 401` (`AUTH_UNAUTHENTICATED`).
  - **`AC-5` (`negative`)**: Missing/mismatched `code` or `state` returns `HTTP 400` (`VALIDATION_ERROR`); forged/expired/`alg: none`/untrusted-`kid` OIDC tokens, deactivated users (`is_active = false`), or missing/expired sessions return `HTTP 401` (`AUTH_UNAUTHENTICATED`) with failure audit logging.
  - **`AC-6` (`negative`)**: `POST /api/v1/auth/mock-login` outside `local`/`test` profiles returns `HTTP 403` (`AUTH_FORBIDDEN`), and unknown JSON fields (`additionalProperties: false`) return `HTTP 400` (`VALIDATION_ERROR`).
  - **`AC-7` (`negative`)**: Any Redis session/revocation outage or OIDC upstream outage fails closed with `HTTP 503` (`SESSION_STORE_UNAVAILABLE`).
- **Open Questions**: `none`

---

### Gate Decision Required
Please confirm if you **approve** the Intake artifact for `p2-a-bff-oidc-fail-closed-session-auth` and authorize creating the feature worktree (`feature/p2-a-bff-oidc-fail-closed-session-auth`).
The **Intake** phase (`/v0-intake`) for story **`P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`)** is complete and ready for your review (`status: awaiting_approval`).

### Artifacts Produced
- **Requirements Specification**: [p2-a-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.md)
- **Phase Result**: [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md)
- **State File**: [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json)

### Summary of Requirements
- **Milestone / Story**: `P2 — MVP / Core Features` ([p2-mvp-core-features.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/milestones/p2-mvp-core-features.md)) · `P2-A` · `Surfaces: bff` · `Material: no` · `Size: 7`
- **User Story**:
  > As a finance preparer, I want to authenticate via Google OIDC in production or local mock login in test environments with Redis-backed HttpOnly session cookies that fail closed with HTTP 503 when the session store is unavailable, so that my portal session is protected against token theft and cache outages.
- **Acceptance Criteria (`AC-1`–`AC-7`)**:
  - **`AC-1` (`happy`)**: `GET /api/v1/auth/login` initiates Google OIDC Authorization Code + PKCE flow (`HTTP 302`), and `GET /api/v1/auth/callback` validates `state`, exchanges `code`, verifies JWT claims (`RS256` allowlist, `iss`, `aud`, `exp`, `nbf`, trusted JWKS `kid`), updates `users.last_login_at`, stores `portal:session:<sessionId>` in Redis, issues an `HttpOnly; Secure; SameSite=Lax` cookie, records an authentication success audit entry, and redirects (`HTTP 302`) to the portal shell.
  - **`AC-2` (`happy`)**: `POST /api/v1/auth/mock-login` (in `local`/`test` profiles) and `GET /api/v1/auth/me` return `HTTP 200` `PrincipalSessionResponse` with active `roles`, `permissions`, `readOnlyOverlay: false`, and `redirectView: "DASHBOARD"`.
  - **`AC-3` (`edge`)**: Authenticated principals with zero active roles (or expired/revoked assignments) receive `redirectView: "ROLE_APPLY_ONBOARDING"` with `roles: []` and `permissions: []`.
  - **`AC-4` (`happy`)**: `POST /api/v1/auth/logout` deletes `portal:session:<sessionId>`, writes `portal:blacklist:<sessionId>` in Redis, clears the cookie (`Max-Age=0`), logs a logout audit event, returns `HTTP 204`, and causes replayed requests to fail with `HTTP 401` (`AUTH_UNAUTHENTICATED`).
  - **`AC-5` (`negative`)**: Missing/mismatched `code` or `state` returns `HTTP 400` (`VALIDATION_ERROR`); forged/expired/`alg: none`/untrusted-`kid` OIDC tokens, deactivated users (`is_active = false`), or missing/expired sessions return `HTTP 401` (`AUTH_UNAUTHENTICATED`) with failure audit logging.
  - **`AC-6` (`negative`)**: `POST /api/v1/auth/mock-login` outside `local`/`test` profiles returns `HTTP 403` (`AUTH_FORBIDDEN`), and unknown JSON fields (`additionalProperties: false`) return `HTTP 400` (`VALIDATION_ERROR`).
  - **`AC-7` (`negative`)**: Any Redis session/revocation outage or OIDC upstream outage fails closed with `HTTP 503` (`SESSION_STORE_UNAVAILABLE`).
- **Open Questions**: `none`

---

### Gate Decision Required
Please confirm if you **approve** the Intake artifact for `p2-a-bff-oidc-fail-closed-session-auth` and authorize creating the feature worktree (`feature/p2-a-bff-oidc-fail-closed-session-auth`).
