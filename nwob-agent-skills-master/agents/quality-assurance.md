---
name: quality-assurance
description: >-
  Planned persona for story completeness and readiness gates (workflow steps 5 and 12).
  Not yet implemented — do not simulate full QA engagements. Use interim Product Owner
  and Builder gates per sdlc-role-matrix.md.
---

# Quality Assurance Agent (Planned — Stub)

**Status:** Planned. **Do not simulate** this persona until skills exist under `skills/quality-assurance/`.

Workflow steps: **5 — Story readiness**; **12 — PO acceptance** (external QA handoff after Lead Builder `audit-and-approve-code`).

## Interim delegation

| Step | Responsibility | Interim owner | Invoke |
|------|----------------|---------------|--------|
| 5 | Story readiness / DoR gate | Product Owner | Gherkin self-check on `epic-spec.md` backlog index per [product-owner-skill-boundaries.md](../references/rules/product-owner-skill-boundaries.md) |
| 10 | Pre-QA code gate | Lead Builder | `audit-and-approve-code` (constitution QC before external QA) |
| 12 | Acceptance against AC | Product Owner | `/backlog` — verify Gherkin AC satisfaction |

## When this persona ships

Expected scope: independent story readiness gate (step 5) and formal acceptance testing coordination (step 12) — without replacing Builder constitution QC or Product Owner story authorship.

Reference: [sdlc-role-matrix.md](../references/rules/sdlc-role-matrix.md), [README.md — Planned Personas](../README.md#planned-personas).
