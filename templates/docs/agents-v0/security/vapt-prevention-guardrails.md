# VAPT prevention guardrails

> VAPT finding–mapped rules. Authoritative: `vapt.mdc` (Spring Boot), `vapt-webapp.mdc` (web apps), `vapt-pr-review.mdc` (PR review). Controls: `security-baseline.mdc`.

Always-on findings are F4, F8, F9, and F10. An applicable miss is Critical. F1–F3 and F5–F7 are regression checks. HIGH and MEDIUM block merge when the diff touches that surface. LOW blocks only when the diff makes the issue exploitable.

## Retest matrix

| Finding | Surface | Pass criteria |
|---------|---------|---------------|
| F4 Function-level access control (HIGH, always-on) | Spring + Web | Restricted role → 403 on direct admin API/route |
| F8 Object-level authorization (HIGH, always-on) | Spring + Web | Same-role peer → 403 or 404 on another `{id}` |
| F9 JWT validation (HIGH, always-on) | Spring (API or BFF) | Disallowed `alg`, wrong `aud`/`iss`, or expired token rejected; blacklist fails closed |
| F10 Security audit events (MEDIUM, always-on) | Spring (API or BFF) | Auth, denial, and admin/upload events logged without a token |
| F1 Unauthorized Account Access (HIGH) | Spring + Web | User B everywhere after User A logout + User B login; access token not in web storage |
| F2 Sensitive Info in Frontend (MEDIUM) | Web | No config leak endpoints; no RBAC/internal URLs in prod bundle |
| F3 File Upload Validation (MEDIUM) | Spring + Web | Renamed wrong-type file → 400 before processing |
| F5 Exposed API Calls (LOW) | Spring + Web | Sensitive params not in the query string; rate limits on sensitive paths. Missing authz is F4 |
| F6 Multiple Active Sessions (LOW) | Spring + Web | Prior session dead on new login (if policy requires) |
| F7 Cookies Without HttpOnly (LOW) | Web | Session cookies HttpOnly + Secure. A missing flag on an auth cookie blocks merge |

## When to run

- Every Verify of application code reviews F4, F8, F9, and F10.
- Every PR touching auth, sessions, routes, controllers, uploads, or deployment security config also reviews the regression findings the diff can affect.
- Before a VAPT retest: inspect the production bundle and Network tab; verify cookie flags; run the retest tests above.
