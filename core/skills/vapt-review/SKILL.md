---
name: vapt-review
description: Verify phase playbook. Run the VAPT F1–F7 checklist; mark any applicable unchecked item as Critical.
---

# vapt-review

Verify phase playbook for the `security-reviewer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the changed files (diff or branch changes). Do not treat `after-edit.sh` VAPT-WARN lines as pass/fail evidence — they are edit-time heuristics only.
2. Select the surface:
   - Spring Boot API → `vapt-spring.mdc` (F1, F3, F4, F5, F6).
   - Web app (SvelteKit/React) → `vapt-webapp.mdc` (F1, F2, F3, F4, F5, F6, F7).
   - PR-level → `vapt-pr-review.mdc`.
3. For each finding, record: finding ID, pass/fail, evidence (file:line), retest step.
4. Mark N/A only for an unaffected surface and record the reason. Mark **any applicable unchecked item as Critical** — merge blocker; N/A is not a security exception.
5. Persist the checklist results to `docs/verify/<feature>/vapt-checklist.md` (finding ID, pass/fail/N/A + reason, evidence file:line, retest step); report findings to the orchestrator; on Critical, route back to the responsible Build/Maintain agent.

## Rule-compliance checklist
- [ ] `vapt-spring.mdc`: F1 (logout/blacklist fail-closed), F3 (upload validation), F4 (`@PreAuthorize`/`permit-all`), F5 (auth+authz/rate limits), F6 (session policy).
- [ ] `vapt-webapp.mdc`: F1 (logout/client state), F2 (no config leak/sourcemap), F3 (upload UI supplemental), F4 (server-side route enforcement), F5 (visible endpoints protected), F6 (session policy), F7 (cookie flags).
- [ ] `vapt-pr-review.mdc`: full PR checklist with sign-off.
- [ ] `security-baseline.mdc`: authn/authz, secrets, cookies, uploads, headers, API hardening, production hygiene, compliance.
- [ ] `api-and-events.mdc` §"Security at the boundary": parameterized queries; no secrets in logs/responses.
- [ ] `workflow-orchestration.mdc`: Verify gate (security) — no Critical findings; checklist persisted to `docs/verify/<feature>/vapt-checklist.md`.
