## Summary

<!-- One-line description of the change. -->

**Feature-Artifact:** docs/agents-v0/requirements/<feature>.md
<!-- Required when this MR changes application code. A bug fix, CVE patch, dependency bump, or hotfix replaces the line above with: **Maintain-Note:** docs/agents-v0/maintain/<id>/note.md -->
<!-- Do not give both. A fix does not borrow a feature artifact's approvals. -->

## Changed files

<!-- Bullet list of files and what changed. -->

## VAPT MR checklist

> Required for MRs touching auth, sessions, routes, controllers, uploads, or deployment security config.
> Always-on findings are F4, F8, F9, and F10. An applicable miss is **Critical**.
> Regression findings keep their severity. HIGH and MEDIUM block merge when the diff touches that surface. LOW blocks only when the diff makes the issue exploitable.
>
> Record each finding as **Pass**, **Fail**, or **N/A** with a reason. N/A is valid only when this change does not affect that finding's surface.

**MR title / link:** _______________
**Reviewer:** _______________
**Date:** _______________

### F4 — Function-level access control (HIGH, always-on)
- [ ] The pack auth marker on every new or changed admin or mutation endpoint (`@PreAuthorize`, `[Authorize]`, a security `Depends()`, or Go auth middleware)
- [ ] Server-side route/module enforcement
- [ ] `permit-all` not enabled in lab/SIT/UAT/prod
- [ ] Policy or entitlement errors deny the request
- [ ] Test: restricted role → 403

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F8 — Object-level authorization (HIGH, always-on)
- [ ] Every `{id}` path authorizes that instance for a same-role peer
- [ ] Test: User A requests User B’s `{id}` → 403 or 404

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F9 — JWT validation (HIGH, always-on)
- [ ] Algorithm allowlist; `iss`, `aud`, `exp`, `nbf` validated; blacklist fails closed
- [ ] Test: disallowed `alg`, wrong audience, or expired token rejected

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F10 — Security audit events (MEDIUM, always-on)
- [ ] Auth, denial, and admin or upload actions logged without a token or password

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F1 — Unauthorized Account Access (HIGH)
- [ ] Access token in memory; refresh token in an HttpOnly cookie
- [ ] Logout clears in-memory token, refresh cookie, and leftover client state
- [ ] Identity bound to validated JWT `sub`
- [ ] Server logout blacklists JWT + purges session + revokes IdP (SSO)
- [ ] JWT blacklist fails closed
- [ ] Test: User A logout → User B login → User B everywhere

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F2 — Sensitive Info in Frontend (MEDIUM)
- [ ] No backend URLs/RBAC roles/permission keys in client bundle
- [ ] No `PUBLIC_*`/`VITE_*` exposing internal config
- [ ] `X-Content-Type-Options: nosniff`
- [ ] Production sourcemaps disabled

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F3 — File Upload Validation (MEDIUM)
- [ ] Server-side: size limit, content sniff, structure parse, generated storage name
- [ ] Decompression limit; production virus scan
- [ ] Extension check supplemental
- [ ] The pack auth marker on upload endpoints (`@PreAuthorize`, `[Authorize]`, a security `Depends()`, or Go auth middleware)

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F5 — Exposed API Calls (LOW)
- [ ] A visible URL is informational; missing authz is F4
- [ ] No sensitive data in URL query strings
- [ ] Rate limits on auth/admin paths

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F6 — Multiple Active Sessions (LOW)
- [ ] Session policy documented or prior tokens invalidated on login

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F7 — Cookies Without HttpOnly (LOW)
- [ ] New cookies: `httpOnly`, `secure` (prod), `sameSite`
- [ ] No auth tokens via `document.cookie`
- [ ] An auth or refresh cookie missing a flag blocks merge

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### Sign-off

| Role | Name | Date | Pass / Fail |
|------|------|------|------------|
| Author | | | |
| Reviewer | | | |

## Quality gate

- [ ] Profile Backend verify command green (Pack `java`: `./mvnw -B clean verify -Pci-security`) / frontend verify command green
- [ ] Changed-line coverage ≥ 80% (report check: ≥ 80% backend / 70% frontend)
- [ ] No new high/critical CVEs (document any exception)
- [ ] Docs synced (README, architecture, network, sequence diagrams)

**Result:** Pass / Fail / N/A — reason and evidence: _______________

> Attach or link the persisted evidence — Build: `docs/agents-v0/build/<feature>/build-report.md`; Verify: `docs/agents-v0/verify/<feature>/test-report.md`, `vapt-checklist.md`, `review-notes.md`.

## Delivery approvals

> Per `workflow-orchestration.mdc`: each phase approval is recorded in `docs/agents-v0/requirements/<feature>.state.json` (`sync-feature-state.sh --approve <phase>`) and optionally in the delivery artifact's `Delivery approvals` section:
>
> | Phase | Artifacts | Approver | Decision | Date |
> |-------|-----------|----------|----------|------|
>
> Put evidence paths in each phase row's Artifacts column — Build: `docs/agents-v0/build/<feature>/...`; Verify: `docs/agents-v0/verify/<feature>/...`. An approval must be a real user decision — never inferred.

- [ ] Approvals for all completed phases are recorded in the delivery artifact in the canonical table format, with evidence paths that exist on disk
