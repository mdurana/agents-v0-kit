# VAPT PR checklist

> Copy of `vapt-pr-review.mdc` for repo use. Fill per PR.

**PR title / link:** _______________
**Reviewer:** _______________
**Date:** _______________

## F1 — Unauthorized Account Access (HIGH)
- [ ] Logout clears all client state
- [ ] Identity bound to validated JWT `sub`
- [ ] Server logout blacklists JWT + purges session + revokes IdP (SSO)
- [ ] JWT blacklist fails closed
- [ ] No new user cache without logout invalidation
- [ ] Test: User A logout → User B login → User B everywhere

## F2 — Sensitive Info in Frontend (MEDIUM)
- [ ] No backend URLs/RBAC roles/permission keys in client bundle
- [ ] No `PUBLIC_*`/`VITE_*` exposing internal config
- [ ] No demo/debug routes in prod path
- [ ] `X-Content-Type-Options: nosniff`
- [ ] Production sourcemaps disabled

## F3 — File Upload Validation (MEDIUM)
- [ ] Server-side: size limit, content sniff, structure parse
- [ ] Extension check supplemental
- [ ] `@PreAuthorize` on upload endpoints
- [ ] Client `accept` supplemental
- [ ] Test: renamed wrong-type file → 400

## F4 — Improper Access Control (MEDIUM)
- [ ] `@PreAuthorize` on every new/changed admin or mutation endpoint
- [ ] Server-side route/module enforcement
- [ ] `permit-all` not enabled in lab/SIT/UAT/prod
- [ ] No authz bypass flags
- [ ] Test: restricted role → 403

## F5 — Exposed API Calls (LOW)
- [ ] New client-visible endpoints have auth + authz
- [ ] No sensitive data in URL query strings
- [ ] Rate limits on auth/admin paths

## F6 — Multiple Active Sessions (LOW)
- [ ] Session policy documented or prior tokens invalidated on login

## F7 — Cookies Without HttpOnly (LOW)
- [ ] New cookies: `httpOnly`, `secure` (prod), `sameSite`
- [ ] No auth tokens via `document.cookie`

## Sign-off

| Role | Name | Date | Pass / Fail |
|------|------|------|------------|
| Author | | | |
| Reviewer | | | |

Flag any unchecked applicable item as **Critical** — must fix before merge.
