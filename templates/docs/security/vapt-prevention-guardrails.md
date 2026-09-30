# VAPT prevention guardrails

> VAPT finding–mapped rules. Authoritative: `vapt-spring.mdc` (Spring Boot), `vapt-webapp.mdc` (web apps), `vapt-pr-review.mdc` (PR review).

## Retest matrix

| Finding | Surface | Pass criteria |
|---------|---------|---------------|
| F1 Unauthorized Account Access (HIGH) | Spring + Web | User B everywhere after User A logout + User B login |
| F2 Sensitive Info in Frontend (MEDIUM) | Web | No config leak endpoints; no RBAC/internal URLs in prod bundle |
| F3 File Upload Validation (MEDIUM) | Spring + Web | Renamed wrong-type file → 400 before processing |
| F4 Improper Access Control (MEDIUM) | Spring + Web | Restricted role → 403 on direct admin API/route |
| F5 Exposed API Calls (LOW) | Spring + Web | All endpoints auth + authz; rate limits on sensitive paths |
| F6 Multiple Active Sessions (LOW) | Spring + Web | Prior session dead on new login (if policy requires) |
| F7 Cookies Without HttpOnly (LOW) | Web | Session cookies HttpOnly + Secure |

## When to run

- Every PR touching auth, sessions, routes, controllers, uploads, or deployment security config.
- Before VAPT retest: inspect production bundle and Network tab; verify cookie flags; run the retest tests above.
