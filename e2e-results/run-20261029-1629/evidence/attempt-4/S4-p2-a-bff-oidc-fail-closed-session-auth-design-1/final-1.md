The **Design** phase for Story `P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`) is complete and now **awaiting your approval**.

### Design Artifacts Produced

1. **Feature OpenAPI 3.0.3 Contract Draft:** [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/openapi.yaml)
   - Self-contained contract for all 5 `/api/v1/auth/**` operations:
     - `initiateOidcLogin` (`GET /api/v1/auth/login` → `302`, `503`)
     - `handleOidcCallback` (`GET /api/v1/auth/callback` → `302`, `400`, `401`, `503`)
     - `getCurrentPrincipal` (`GET /api/v1/auth/me` → `200`, `401`, `503`)
     - `logoutSession` (`POST /api/v1/auth/logout` → `204`, `401`, `503`)
     - `mockLogin` (`POST /api/v1/auth/mock-login` → `200`, `400`, `403`, `503`)
   - Enforces `additionalProperties: false` on `MockLoginRequest`, defines `PrincipalSessionResponse` (`redirectView: DASHBOARD | ROLE_APPLY_ONBOARDING`), and standardizes RFC 7807 `ProblemDetail` (`application/problem+json`) with `X-Correlation-ID`.
2. **Feature Design Specification:** [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/design.md)
   - **Traceability:** Maps `AC-1` through `AC-7` and all NFRs (`p95 <= 150 ms` auth/session guard latency, `99.95%` availability, `500 ms`/`1000 ms` Redis timeouts, `2000 ms`/`5000 ms` OIDC timeouts, Tier 1/Tier 2 RPO/RTO, `Encode.forJava()` sanitization, and `L-002`/`L-003` lessons) to concrete components (`BffAuthController`, `BffAuthenticationService`, `FailClosedRedisSessionFilter`, `GoogleOidcIdentityProviderAdapter`, `RedisSessionStoreAdapter`, `AuditEventPort`).
   - **Data Model:** Documents PostgreSQL 15 usage (`users`, `user_role_assignments`, `roles`, `role_permissions`, `permissions`, `audit_log_entries` from `V2__iam_and_audit_schema.sql`) and Redis 7 key-spaces (`portal:oidc-state:<state>`, `portal:session:<sessionId>`, `portal:blacklist:<sessionId>`).
   - **Authorization & VAPT (`F4`, `F8`, `F9`, `F10`):** Maps all 5 `operationId`s with self-scoped session rules, PKCE + `RS256` JWKS verification (`alg: none` rejection), profile-gated mock login (`403 AUTH_FORBIDDEN` outside `local`/`test`), and tamper-evident security audit events via `AuditEventPort` (`L-003`).
   - **Failure Modes:** Covers `AC-3` (`Kind: edge`), `AC-5`, `AC-6`, and `AC-7` (`Kind: negative`), including slow/timeout/circuit-open fail-closed `HTTP 503` (`SESSION_STORE_UNAVAILABLE`) and multi-step write compensation.
3. **Architecture Decision Record (`Status: Proposed`):** [0007-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/adr/0007-bff-oidc-fail-closed-session-auth.md)
   - Compares 3 alternatives for server-side BFF OIDC PKCE + Redis session verification, explicit profile guard (`403` vs `@Profile`-omitted `404`), and cross-context `AuditEventPort` isolation.
4. **Sequence Diagram:** [iam-auth-sod.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/diagrams/sequences/iam-auth-sod.md)
5. **Design Review Report (`design-reviewer`):** [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/review.md)
   - **Verdict:** **PASS** (`0` Open Critical, `0` Open Suggestion, `0` Open Nice-to-have findings).
6. **Phase Result & State:** [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md) and [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

Please review the design artifacts and confirm if you **approve** the `design` gate for `p2-a-bff-oidc-fail-closed-session-auth`.
The **Design** phase for Story `P2-A` (`p2-a-bff-oidc-fail-closed-session-auth`) is complete and now **awaiting your approval**.

### Design Artifacts Produced

1. **Feature OpenAPI 3.0.3 Contract Draft:** [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/openapi.yaml)
   - Self-contained contract for all 5 `/api/v1/auth/**` operations:
     - `initiateOidcLogin` (`GET /api/v1/auth/login` → `302`, `503`)
     - `handleOidcCallback` (`GET /api/v1/auth/callback` → `302`, `400`, `401`, `503`)
     - `getCurrentPrincipal` (`GET /api/v1/auth/me` → `200`, `401`, `503`)
     - `logoutSession` (`POST /api/v1/auth/logout` → `204`, `401`, `503`)
     - `mockLogin` (`POST /api/v1/auth/mock-login` → `200`, `400`, `403`, `503`)
   - Enforces `additionalProperties: false` on `MockLoginRequest`, defines `PrincipalSessionResponse` (`redirectView: DASHBOARD | ROLE_APPLY_ONBOARDING`), and standardizes RFC 7807 `ProblemDetail` (`application/problem+json`) with `X-Correlation-ID`.
2. **Feature Design Specification:** [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/design.md)
   - **Traceability:** Maps `AC-1` through `AC-7` and all NFRs (`p95 <= 150 ms` auth/session guard latency, `99.95%` availability, `500 ms`/`1000 ms` Redis timeouts, `2000 ms`/`5000 ms` OIDC timeouts, Tier 1/Tier 2 RPO/RTO, `Encode.forJava()` sanitization, and `L-002`/`L-003` lessons) to concrete components (`BffAuthController`, `BffAuthenticationService`, `FailClosedRedisSessionFilter`, `GoogleOidcIdentityProviderAdapter`, `RedisSessionStoreAdapter`, `AuditEventPort`).
   - **Data Model:** Documents PostgreSQL 15 usage (`users`, `user_role_assignments`, `roles`, `role_permissions`, `permissions`, `audit_log_entries` from `V2__iam_and_audit_schema.sql`) and Redis 7 key-spaces (`portal:oidc-state:<state>`, `portal:session:<sessionId>`, `portal:blacklist:<sessionId>`).
   - **Authorization & VAPT (`F4`, `F8`, `F9`, `F10`):** Maps all 5 `operationId`s with self-scoped session rules, PKCE + `RS256` JWKS verification (`alg: none` rejection), profile-gated mock login (`403 AUTH_FORBIDDEN` outside `local`/`test`), and tamper-evident security audit events via `AuditEventPort` (`L-003`).
   - **Failure Modes:** Covers `AC-3` (`Kind: edge`), `AC-5`, `AC-6`, and `AC-7` (`Kind: negative`), including slow/timeout/circuit-open fail-closed `HTTP 503` (`SESSION_STORE_UNAVAILABLE`) and multi-step write compensation.
3. **Architecture Decision Record (`Status: Proposed`):** [0007-bff-oidc-fail-closed-session-auth.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/adr/0007-bff-oidc-fail-closed-session-auth.md)
   - Compares 3 alternatives for server-side BFF OIDC PKCE + Redis session verification, explicit profile guard (`403` vs `@Profile`-omitted `404`), and cross-context `AuditEventPort` isolation.
4. **Sequence Diagram:** [iam-auth-sod.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/diagrams/sequences/iam-auth-sod.md)
5. **Design Review Report (`design-reviewer`):** [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/design/p2-a-bff-oidc-fail-closed-session-auth/review.md)
   - **Verdict:** **PASS** (`0` Open Critical, `0` Open Suggestion, `0` Open Nice-to-have findings).
6. **Phase Result & State:** [p2-a-bff-oidc-fail-closed-session-auth.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.phase-result.md) and [p2-a-bff-oidc-fail-closed-session-auth.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal/docs/agents-v0/requirements/p2-a-bff-oidc-fail-closed-session-auth.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

Please review the design artifacts and confirm if you **approve** the `design` gate for `p2-a-bff-oidc-fail-closed-session-auth`.
