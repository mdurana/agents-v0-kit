---
name: spec-intake
description: Intake phase playbook. Turn a Jira/Confluence spec into acceptance criteria, NFRs, and a regulation list.
---

# spec-intake

Intake phase playbook for the `requirements-analyst` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the source: Jira issue, Confluence page, or user description.
2. Write `docs/agents-v0/requirements/<feature>.helper-brief.md` when the repo needs mapping (`helper: explore-researcher`, `workflow-orchestration.mdc` Helper agents). Do not launch the helper. Continue after the main session returns its result.
3. Draft `docs/agents-v0/requirements/<feature>.md`:
   - **User story** — one sentence: `As a [role], I want [goal], so that [benefit].` Copy it from the milestone row when the story belongs to a program. If the sentence still contains `<...>` placeholders, or omits `so that`, stop and ask the user to supply the missing role, goal, or benefit. Do not invent them.
   - **Acceptance criteria** — split the goal and each constraint into testable rows with stable IDs (`AC-1`, `AC-2`, …). One behavior per row.
   - **Out of scope** — exclusions from the source, as their own list. Do not turn an exclusion into an acceptance criterion unless it is itself testable.
   - **NFRs** — performance, availability, observability targets.
   - **UX requirements** (UI-affecting changes) — WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria.
   - **Regulations** — GDPR, BSP, internal GXI as applicable.
   - **Security-review triggers** — auth changes, new upload endpoints, RBAC changes, new public routes.
   - **Open questions** — for the user.
   - **Milestone/Story links** — `Milestone: <Pn-name>` and `Story: <story-id>` under the title when the story belongs to a milestone program (`docs/agents-v0/milestones/<milestone>.md`).
   - **Delivery approvals** — record only actual user decisions, in this canonical table format (required by the CI checks `ci/check-approvals.sh` and `ci/check-evidence.sh`):

     | Phase | Artifacts | Approver | Decision | Date |
     |-------|-----------|----------|----------|------|
     | Intake | docs/agents-v0/requirements/&lt;feature&gt;.md | &lt;name&gt; | Approved | &lt;date&gt; |

     Append one row per approved phase; record evidence paths in each phase row's Artifacts column — Build: `docs/agents-v0/build/<feature>/...`; Verify: `docs/agents-v0/verify/<feature>/...`.
4. If greenfield UI, ask "Svelte or React?" once and record the answer.
5. Apply the **story-size budget** before the gate (`workflow-orchestration.mdc`):
   - Record `Surfaces:` as `backend`, `bff`, or `frontend`. When `docs/agents-v0/project-profile.md` lists `Service roots`, also record `Service root: <root>` for a backend or BFF story. A story that needs two service roots is two stories.
   - Count `AC-*` rows. The cap is eight (`AC-1` through `AC-8`).
   - More than one surface, more than one bounded context, or more than eight criteria: do not present the Intake gate. Write `## Proposed split` with extra milestone rows (story sentence, surface, dependency) and stop until the user approves the split. After approval, this artifact keeps the first slice; each other row is its own feature.
   - Record `Vertical slice: yes` only when the user asks for one journey across surfaces. That story may list more than one surface and still has at most eight criteria.
6. Resolve open questions with the user.
7. Present the Intake gate result and wait for approval before Design.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report.
- [ ] `project-delivery-core.mdc`: stack identified; async/messaging/cache justified or omitted.
- [ ] `frontend-web.mdc`: Svelte/React decision recorded for greenfield UI.
- [ ] UX requirements recorded for UI-affecting changes (WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria).
- [ ] `security-baseline.mdc` §11: applicable regulations and security-review triggers identified.
- [ ] User story is one sentence: `As a [role], I want [goal], so that [benefit].`
- [ ] Acceptance criteria are one behavior per `AC-*` row, split from that story and its constraints; out of scope is a separate list.
- [ ] Story size: one surface unless `Vertical slice: yes`; at most `AC-8`. Oversized stories stop on `## Proposed split`.
- [ ] `workflow-orchestration.mdc`: Intake gate criteria met; stopped for approval; approvals table format used.
