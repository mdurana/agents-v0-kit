---
name: vapt-review
description: Verify phase playbook. Run always-on VAPT findings F4, F8, F9, and F10, plus regression findings for the surface the diff touches.
---

# vapt-review

Verify phase playbook for the `security-reviewer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the changed files (diff or branch changes). Do not treat `after-edit.sh` VAPT-WARN lines as pass/fail evidence — they are edit-time heuristics only.
2. Select the surface:
   - API or BFF → `vapt.mdc` (always-on F4, F8, F9, F10; regression F1, F3, F5, F6).
   - Web app (React / existing SvelteKit) → `vapt-webapp.mdc` (always-on F4, F8; regression F1, F2, F3, F5, F6, F7). Mark F9 and F10 N/A only when no API or BFF in the diff validates tokens or writes audit events, and record that reason.
   - PR-level → `vapt-pr-review.mdc`.
3. For each finding, record: finding ID, pass/fail, evidence (file:line), retest step.
4. Mark N/A only for an unaffected surface and record the reason. An applicable miss on F4, F8, F9, or F10 is **Critical**. An applicable HIGH or MEDIUM regression finding (F1, F2, F3) blocks merge. A LOW regression finding (F5, F6, F7) blocks merge only when the diff makes it exploitable. N/A is not a security exception for an applicable item.
5. Persist the checklist results to `docs/agents-v0/verify/<feature>/vapt-checklist.md` (finding ID, pass/fail/N/A + reason, evidence file:line, retest step); report findings to the orchestrator; on Critical, route back to the responsible Build/Maintain agent.

## Rule-compliance checklist
- [ ] Always-on: F4 (function-level 403), F8 (same-role peer `{id}` → 403 or 404), F9 (JWT `alg`/`iss`/`aud`/`exp`, fail-closed blacklist), F10 (audit events without a token).
- [ ] `vapt.mdc` regression: F1 (logout/blacklist fail-closed), F3 (upload validation), F5 (query string and rate limits; missing authz recorded as F4), F6 (session policy).
- [ ] `vapt-webapp.mdc` regression: F1 (memory access token, HttpOnly refresh, logout), F2 (no config leak/sourcemap), F3 (upload UI supplemental), F5 (visible URL is informational), F6 (session policy), F7 (cookie flags; missing auth-cookie flag blocks).
- [ ] `vapt-pr-review.mdc`: full PR checklist with sign-off.
- [ ] `security-baseline.mdc`: authn/authz, JWT, session storage, secrets, cookies, uploads, headers, API hardening, audit events, production hygiene, compliance.
- [ ] `api-and-events.mdc` §"Security at the boundary": parameterized queries; sort/filter allowlist; URL allowlist; no secrets in logs/responses.
- [ ] `workflow-orchestration.mdc`: Verify gate (security) — no Critical findings; checklist persisted to `docs/agents-v0/verify/<feature>/vapt-checklist.md`.
