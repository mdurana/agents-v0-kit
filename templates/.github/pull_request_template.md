## Summary

<!-- One-line description of the change. -->

**Feature-Artifact:** docs/requirements/&lt;feature&gt;.md
<!-- Required when this PR changes application code (ci/check-delivery-linkage.sh). -->

## Changed files

<!-- Bullet list of files and what changed. -->

## VAPT PR checklist

> Required for PRs touching auth, sessions, routes, controllers, uploads, or deployment security config.
> Flag any unchecked applicable item as **Critical** — must fix before merge.
>
> Record each finding as **Pass**, **Fail**, or **N/A** with a reason. N/A is valid only when this change does not affect that finding's surface; an applicable unchecked item is Critical and cannot be recorded as N/A.

**PR title / link:** _______________
**Reviewer:** _______________
**Date:** _______________

### F1 — Unauthorized Account Access (HIGH)
- [ ] Logout clears all client state
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
- [ ] Server-side: size limit, content sniff, structure parse
- [ ] Extension check supplemental
- [ ] `@PreAuthorize` on upload endpoints

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F4 — Improper Access Control (MEDIUM)
- [ ] `@PreAuthorize` on every new/changed admin or mutation endpoint
- [ ] Server-side route/module enforcement
- [ ] `permit-all` not enabled in lab/SIT/UAT/prod
- [ ] Test: restricted role → 403

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F5 — Exposed API Calls (LOW)
- [ ] New client-visible endpoints have auth + authz
- [ ] No sensitive data in URL query strings
- [ ] Rate limits on auth/admin paths

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F6 — Multiple Active Sessions (LOW)
- [ ] Session policy documented or prior tokens invalidated on login

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### F7 — Cookies Without HttpOnly (LOW)
- [ ] New cookies: `httpOnly`, `secure` (prod), `sameSite`
- [ ] No auth tokens via `document.cookie`

**Result:** Pass / Fail / N/A — reason and evidence: _______________

### Sign-off

| Role | Name | Date | Pass / Fail |
|------|------|------|------------|
| Author | | | |
| Reviewer | | | |

## Quality gate

- [ ] `mvn clean verify` / frontend tests green
- [ ] Coverage ≥ 80% backend / 70% frontend for changed code
- [ ] No new high/critical CVEs (document any exception)
- [ ] Docs synced (README, architecture, network, sequence diagrams)

**Result:** Pass / Fail / N/A — reason and evidence: _______________

> Attach or link the persisted evidence — Build: `docs/build/<feature>/build-report.md`; Verify: `docs/verify/<feature>/test-report.md`, `vapt-checklist.md`, `review-notes.md`.

## Delivery approvals

> Per `workflow-orchestration.mdc`: each phase approval must be recorded in the delivery artifact's `Delivery approvals` section using the canonical table (required by the CI approval check `ci/check-approvals.sh`; `ci/check-evidence.sh` verifies that the recorded evidence paths exist on disk):
>
> | Phase | Artifacts | Approver | Decision | Date |
> |-------|-----------|----------|----------|------|
>
> Put evidence paths in each phase row's Artifacts column — Build: `docs/build/<feature>/...`; Verify: `docs/verify/<feature>/...`. An approval must be a real user decision — never inferred. Record the Decision cell as an explicit positive token (canonically `Approved`); `ci/check-approvals.sh` accepts `approved` / `approve` / `yes` / `pass`.

- [ ] Approvals for all completed phases are recorded in the delivery artifact in the canonical table format, with evidence paths that exist on disk
