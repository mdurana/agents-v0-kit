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
   - **User story** — one sentence on its own line: `As a [role], I want [goal], so that [benefit].` Copy it from the milestone row when the story belongs to a program. If the sentence still contains `<...>` placeholders, or omits `so that`, stop and ask the user to supply the missing role, goal, or benefit. Do not invent them.
   - **Acceptance criteria** — split the goal and each constraint into testable rows with stable IDs (`AC-1`, `AC-2`, …, no gaps). One Gherkin scenario per id, under a `### AC-n — <scenario name>` heading. Each scenario has `Kind: happy`, `Kind: negative`, or `Kind: edge`, then `Given`, `When`, and `Then` on their own lines. Extra `And` lines belong to that same scenario. The `Then` names an observable result: an HTTP status, a stored state, a quoted message, or a screen state. Do not write "works as expected", "handles errors gracefully", or "successfully processes". At least one scenario is `Kind: negative` or `Kind: edge`. A security-review trigger (auth, upload, RBAC, public route) needs a `Kind: negative` whose `Then` is an authorization or validation refusal (for example HTTP 401, 403, 400, or 422). When no trigger applies and the story has no failure behavior, record `Negatives: N/A: <reason>` instead of a negative scenario. P0-A does not use this shape; `/v0-build` copies AC-1 through AC-4 from the milestone.
   - **Preconditions** — the state that exists before any scenario. `N/A: <reason>` when there is none.
   - **Desk check** — one sentence a person can run before QA. Name the fixture, screen, page, or HTTP call.
   - **Material** — `Material: yes` when the story adds a service, a datastore, a security boundary, or a breaking API. Otherwise `Material: no`.
   - **Out of scope** — exclusions from the source, as their own list. An exclusion is not a negative scenario. Do not turn an exclusion into an acceptance criterion unless it is itself testable.
   - **NFRs** — performance, availability, observability targets.
   - **UX requirements** (UI-affecting changes) — WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria.
   - **Regulations** — GDPR, BSP, internal GXI as applicable.
   - **Security-review triggers** — `none`, or a bullet for each trigger that applies: auth, upload, RBAC, public route. Do not restate the catalog when none apply.
   - **Open questions** — resolve them with the user. Before the gate the section is the single word `none`.
   - **Milestone file** — when `Milestone:` is set, also record `Milestone file: docs/agents-v0/milestones/<milestone>.md` and `Story: <story-id>`. The manifest must name that story id.
   - **Milestone/Story links** — `Milestone: <Pn-name>` and `Story: <story-id>` under the title when the story belongs to a milestone program (`docs/agents-v0/milestones/<milestone>.md`).
   - **Delivery approvals** — record only actual user decisions, in this canonical table format (required by the CI checks `.agents-v0/ci/check-approvals.sh` and `.agents-v0/ci/check-evidence.sh`):

     | Phase | Artifacts | Approver | Decision | Date |
     |-------|-----------|----------|----------|------|
     | Intake | docs/agents-v0/requirements/&lt;feature&gt;.md | &lt;name&gt; | Approved | &lt;date&gt; |

     Append one row per approved phase; record evidence paths in each phase row's Artifacts column — Build: `docs/agents-v0/build/<feature>/...`; Verify: `docs/agents-v0/verify/<feature>/...`.
4. The UI is the bound pack's `ui` id. The React example is React 19, TypeScript 5.9, and Vite 7.
5. Apply the **story-size budget** before the gate (`workflow-orchestration.mdc`):
   - Record `Surfaces:` as `backend`, `bff`, or `frontend`. When `docs/agents-v0/project-profile.md` lists `Service roots`, also record `Service root: <root>` for a backend or BFF story. A story that needs two service roots is two stories.
   - Count `AC-*` rows. The cap is eight (`AC-1` through `AC-8`).
   - More than one surface, more than one bounded context, or more than eight criteria: do not present the Intake gate. The required negative counts toward the eight. Write `## Proposed split` with a **table** of extra milestone rows (story sentence, surface, dependency) and stop until the user approves the split (`check-intake.sh` fails while that section is open or the table is missing). After approval, this artifact keeps the first slice and drops `## Proposed split`; each other row is its own feature.
   - Record `Vertical slice: yes` only when the user asks for one journey across surfaces. That story may list more than one surface and still has at most eight criteria. Do not write `## Proposed split` for the seeded P0-A row. This skill does not write that story; `/v0-build` copies it.
6. Resolve open questions with the user. Write `none` under Open questions.
7. Run `sh .agents-v0/ci/check-intake.sh docs/agents-v0/requirements/<feature>.md` and fix until it exits 0. Do not present the gate while it fails. P0-A does not run this skill or this check. `/v0-build` copies that milestone story and AC-1 through AC-4.
8. Present the Intake gate result and wait for approval before Design.

Scenario shape:

```markdown
### AC-1 — place the order
Kind: happy
Given a signed-in customer and fixture CUST-1
When the customer places an order for SKU-1
Then HTTP 201 and the order row is stored with status PENDING

### AC-2 — reject an unknown customer
Kind: negative
Given no customer for fixture CUST-404
When the customer places an order
Then HTTP 404 and no order row is written
```

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report.
- [ ] `project-delivery-core.mdc`: stack identified; async/messaging/cache justified or omitted.
- [ ] The UI matches the bound pack's `ui` id. The React example is React 19, TypeScript 5.9, Vite 7.
- [ ] UX requirements recorded for UI-affecting changes (WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria).
- [ ] `security-baseline.mdc` §11: applicable regulations and security-review triggers identified. A sensitive action is named so Design can require step-up.
- [ ] User story is one sentence: `As a [role], I want [goal], so that [benefit].`
- [ ] Acceptance criteria are one Gherkin scenario per `AC-*` heading, split from that story and its constraints; out of scope is a separate list.
- [ ] Each scenario has `Kind: happy`, `negative`, or `edge`. The `Then` names an observable result. Preconditions and a desk check are recorded.
- [ ] One scenario is `Kind: negative` or `Kind: edge`, or `Negatives: N/A: <reason>` when no security-review trigger applies.
- [ ] A security-review trigger has a `Kind: negative` whose `Then` is a refusal. `Negatives: N/A` is absent in that case.
- [ ] `Material:` is `yes` or `no`.
- [ ] `sh .agents-v0/ci/check-intake.sh` exits 0.
- [ ] Story size: one surface unless `Vertical slice: yes`; at most `AC-8`. Oversized stories stop on `## Proposed split`.
- [ ] `workflow-orchestration.mdc`: Intake gate criteria met; stopped for approval; approvals table format used.
