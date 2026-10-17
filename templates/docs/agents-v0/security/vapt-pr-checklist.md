# VAPT PR checklist

> Copy of `vapt-pr-review.mdc` for repo use. Fill per PR.

Always-on findings are F4, F8, F9, and F10. An applicable miss is **Critical**. HIGH and MEDIUM regression findings block merge when the diff touches that surface. LOW blocks only when the diff makes the issue exploitable.

**PR title / link:** _______________
**Reviewer:** _______________
**Date:** _______________

## F4 — Function-level access control (HIGH, always-on)
- [ ] The pack auth marker on every new or changed admin or mutation endpoint (`@PreAuthorize`, `[Authorize]`, a security `Depends()`, or Go auth middleware)
- [ ] Server-side route/module enforcement
- [ ] `permit-all` not enabled in lab/SIT/UAT/prod
- [ ] No authz bypass flags
- [ ] Policy or entitlement errors deny the request
- [ ] Test: restricted role → 403

## F8 — Object-level authorization (HIGH, always-on)
- [ ] Every `{id}` path authorizes that instance
- [ ] Same-role peer is the retest caller
- [ ] Write DTO rejects unknown properties
- [ ] Test: User A requests User B’s `{id}` → 403 or 404

## F9 — JWT validation (HIGH, always-on)
- [ ] Algorithm allowlist; `none` rejected; `iss`, `aud`, `exp`, `nbf` validated
- [ ] `kid` constrained to known keys; refresh reuse revokes the family
- [ ] Blacklist fails closed
- [ ] Test: disallowed `alg`, wrong audience, or expired token rejected

## F10 — Security audit events (MEDIUM, always-on)
- [ ] Auth, logout, denial, revocation, admin mutation, and upload outcome logged
- [ ] Correlation id, principal, action, result; no token or password
- [ ] Test: one denial and one admin or upload action

## F1 — Unauthorized Account Access (HIGH)
- [ ] Access token in memory; refresh token in an HttpOnly cookie
- [ ] Logout clears in-memory token, refresh cookie, and leftover client state
- [ ] Identity bound to validated JWT `sub`
- [ ] Server logout blacklists JWT + purges session + revokes IdP (SSO)
- [ ] JWT blacklist fails closed
- [ ] Test: User A logout → User B login → User B everywhere

## F2 — Sensitive Info in Frontend (MEDIUM)
- [ ] No backend URLs/RBAC roles/permission keys in client bundle
- [ ] No `PUBLIC_*`/`VITE_*` exposing internal config
- [ ] No demo/debug routes in prod path
- [ ] `X-Content-Type-Options: nosniff`
- [ ] Production sourcemaps disabled

## F3 — File Upload Validation (MEDIUM)
- [ ] Server-side: size limit, content sniff, structure parse, generated storage name
- [ ] Decompression limit; production virus scan
- [ ] Extension check supplemental
- [ ] The pack auth marker on upload endpoints (`@PreAuthorize`, `[Authorize]`, a security `Depends()`, or Go auth middleware)
- [ ] Client `accept` supplemental
- [ ] Test: renamed wrong-type file → 400

## F5 — Exposed API Calls (LOW)
- [ ] A visible URL is informational; missing authz is F4
- [ ] No sensitive data in URL query strings
- [ ] Rate limits on auth/admin paths

## F6 — Multiple Active Sessions (LOW)
- [ ] Session policy documented or prior tokens invalidated on login

## F7 — Cookies Without HttpOnly (LOW)
- [ ] New cookies: `httpOnly`, `secure` (prod), `sameSite`
- [ ] No auth tokens via `document.cookie`
- [ ] An auth cookie missing a flag blocks merge

## Sign-off

| Role | Name | Date | Pass / Fail |
|------|------|------|------------|
| Author | | | |
| Reviewer | | | |

An applicable miss on F4, F8, F9, or F10 is **Critical**.
