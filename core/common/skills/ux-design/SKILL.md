---
name: ux-design
description: Design phase playbook. Produce HTML mockups and the UX spec — flows, screen states, per-component default behavior, accessibility, and UX acceptance criteria.
---

# ux-design

Design phase playbook for the `ux-designer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Intake artifact (`docs/agents-v0/requirements/<feature>.md`): acceptance criteria, UX requirements (WCAG 2.1 AA target, device/browser matrix, design-system reference), and the UI stack named by the pack's `ui` id. Read the feature draft `docs/agents-v0/design/<feature>/openapi.yaml` when the UI calls an API.
2. Inventory the screens affected by the acceptance criteria; map each criterion to a screen. For a single primary screen, copy `docs/agents-v0/snippets/ux-spec-one-screen.md` to `docs/agents-v0/design/<feature>/ux-spec.md` and fill placeholders (still add mockups). Multi-screen stories use `docs/agents-v0/design/ux-spec.md` as the shape.
3. For each screen write the **state matrix** — loading, error, empty, success (`frontend-web.mdc` UX clause) — with the trigger for each state and the mockup file for that state.
4. Write **static HTML mockups** under `docs/agents-v0/design/<feature>/mockups/`. One file per screen state (for example `list-empty.html`, `create-error.html`). HTML and CSS only. Every interactive element (link, button, input, select, textarea, summary, or an element with role button, link, tab, menuitem, checkbox, or switch) carries `data-component="<Component name>"`, the same name as its row in the component table. No fetch, no API client, no secrets. Show layout, hierarchy, labels, and every interactive control.
5. Draw **user flows** as Mermaid flowcharts (`architecture-and-diagrams.mdc` conventions); one flow per primary task.
6. Write **component defaults** in the UX spec. One row per interactive component:
   - **Component** and **Screen**. A shared component (the same Delete control on two screens) is defined once; other rows reference that name.
   - **Mockup** path for the state that shows it.
   - **Operation** — the operation in `docs/agents-v0/design/<feature>/openapi.yaml` when the component calls the API, either its `operationId` or `METHOD /api/v1/...` (`POST /api/v1/contacts`). Use `—` when it does not. If the operation is not in that draft, stop. Do not invent an endpoint.
   - **Default behavior** — what happens if the user does not override it, including the result states: success, validation error, 401, and 5xx, each pointing at a mockup when the user can see that result.
   - **Override** — blank until the user changes it. A change updates this cell and the mockup in the same step.
7. Specify **accessibility** per screen: keyboard path, focus order, modal focus trap/restore, ARIA needs, color contrast, `prefers-reduced-motion`, touch targets (WCAG 2.1 AA).
8. Define **responsive breakpoints** and the device/browser matrix from Intake. Mockups cover the breakpoints named in Intake (at least the desktop and narrow widths already required).
9. Record **design-system conformance**: tokens/components reused; any deviation gets an ADR reference.
10. Write **UX acceptance criteria**: testable, one per row, mapped screen → mockup → criterion (the Verify audit maps each to a test of the built UI).
11. Record N/A determinations (no-UI surface) with the reason. A no-UI story has no mockups and no component table; say so.
12. Verify every mockup control has a component row, every row links to a mockup that exists and contains that `data-component` attribute, API-backed rows name a draft operation, and no mockup calls the API. Read each row against its mockup to confirm they describe the same behavior.
13. Persist the spec to `docs/agents-v0/design/<feature>/ux-spec.md` and the mockups beside it. Stop for the Design gate. Present the spec and the mockup paths. Do not start Build.

## Rule-compliance checklist
- [ ] HTML mockups exist for each screen state; they are static (no API calls).
- [ ] Component defaults: name, screen, mockup, operation or `—`, default behavior, override. Shared components defined once.
- [ ] Every visible control has a row; every row's mockup exists; mockup and row agree.
- [ ] API-backed components name an operation in `docs/agents-v0/design/<feature>/openapi.yaml`. No new endpoint in the UX spec.
- [ ] UX spec complete: flows, per-screen state matrix, WCAG 2.1 AA accessibility, responsive/device matrix, design-system conformance; N/A determinations reasoned.
- [ ] UX acceptance criteria name the screen and the mockup.
- [ ] `frontend-web.mdc`: state matrix; accessibility; the bound pack's `ui` id (the React example is `frontend-web.mdc`).
- [ ] `architecture-and-diagrams.mdc`: Mermaid conventions for flows.
- [ ] `quality-and-testing.mdc`: UX acceptance criteria are testable on the built UI.
- [ ] `workflow-orchestration.mdc`: Design gate criteria met; stopped for approval.
