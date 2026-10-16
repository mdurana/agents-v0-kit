---
name: pr-review
description: Verify phase playbook. Apply the code-review checklist; label findings Critical/Suggestion/Nice to have.
---

# pr-review

Verify phase playbook for the `code-reviewer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the changed files (diff or branch changes).
2. Apply the `code-review.mdc` checklist:
   - Correctness: happy path, edge cases, failure modes.
   - Security: parameterized SQL and sort/filter allowlists; XSS-safe rendering; log injection mitigated the way the pack `backend.mdc` says; no secrets; safe path handling; CSRF/CORS/BOLA; JWT claim checks; audit events when the diff touches those actions.
   - API/events: boundary validation; DTOs not entities; idempotent event handling; HTTP semantics.
   - Observability: useful logs at state transitions; trace context propagated; no PII/secrets.
   - Complexity/coverage: methods ≤ 30 lines; cognitive complexity ≤ 15.
   - Error handling: no empty catches; exception paths tested.
   - UX/a11y: state matrix, component defaults, and layout versus the approved mockups; keyboard/focus flow; contrast; access control enforced server-side, not UI hide-only. API calls match the OpenAPI operation named on the component row.
   - Docs/diagrams: updated if behavior or topology changed.
3. Label each finding: **Critical** (merge blocker), **Suggestion** (should fix), **Nice to have** (optional).
4. Cite file:line and the rule clause for each finding.
5. Persist review notes to `docs/agents-v0/verify/<feature>/review-notes.md` (finding, label, file:line, rule clause); report to the orchestrator; on Critical, route back to the responsible agent.

## Rule-compliance checklist
- [ ] `code-review.mdc`: full checklist applied.
- [ ] `backend.mdc` / `frontend-web.mdc`: style, layering, size limits.
- [ ] `quality-and-testing.mdc`: methods ≤ 30 lines; cognitive complexity ≤ 15; coverage targets.
- [ ] `api-and-events.mdc`: DTOs not entities; idempotency; HTTP semantics.
- [ ] `architecture-and-diagrams.mdc`: docs/diagrams updated.
- [ ] UX/a11y: UX spec conformance and accessibility reviewed for UI changes.
- [ ] `workflow-orchestration.mdc`: Verify gate (review) — no Critical findings; notes persisted to `docs/agents-v0/verify/<feature>/review-notes.md`.
