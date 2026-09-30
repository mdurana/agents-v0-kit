---
description: Design phase. Produce OpenAPI/event contracts, an ADR, and Mermaid diagrams.
---

# /design

You are entering the **Design** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching the architect, confirm the Intake requirements artifact exists and its `Delivery approvals` section records an explicit Intake approval. If either is missing, and the artifact exists, run `sh scripts/sync-feature-state.sh <artifact> --active-phase design --status blocked --reason "<one line>"`, then stop and report the missing evidence; do not infer approval.

## Resume
When the artifact exists, run `sh scripts/sync-feature-state.sh <artifact> --active-phase design --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
While another feature is in flight in this checkout, write only `docs/requirements/<feature>.md`, its state file, and `docs/design/<feature>/`. Stop before editing a shared file (`workflow-orchestration.mdc` Parallel features), including `openapi/api-v1.yaml`, when `git status` shows it is already modified or another feature's state is `in_progress`, `awaiting_approval`, or `blocked` on a phase that writes it. Record `--status blocked` with that reason.

## Instructions
1. Launch the `solution-architect` subagent with the Intake artifact.
2. For UI-affecting changes, launch the `ux-designer` subagent (skill: `ux-design`) to produce `docs/design/<feature>/ux-spec.md` and static HTML mockups under `docs/design/<feature>/mockups/`. The spec includes user flows, a per-screen state matrix (loading/error/empty/success) linked to those mockups, per-component default behavior (name, screen, mockup, OpenAPI operation or `—`, default behavior, override), WCAG 2.1 AA accessibility requirements, a responsive/device matrix, design-system conformance, and UX acceptance criteria. Mockups do not call the API. A component that calls the API names an operation in the approved OpenAPI contract.
3. For **Major** tier changes, the architect must also follow `system-design` (context boundaries, failure modes, rollout).
4. The architect must follow the `contract-first-design` skill and produce:
    - OpenAPI 3.0 contracts for `/api/v1/...`, stored in the repository's established contract location.
   - Event schemas with `eventVersion`; additive evolution.
   - One error envelope per API surface (RFC 7807 **or** custom — not mixed).
   - Idempotency keys on non-idempotent creates.
   - An ADR for non-trivial decisions.
   - Mermaid diagrams following `architecture-and-diagrams.mdc` conventions.
5. Check the **Design gate** (`workflow-orchestration.mdc`):
   - Contracts and event schemas defined with `eventVersion`.
   - Error envelope chosen per surface.
   - ADR exists.
   - Diagrams follow Mermaid conventions.
   - Security-review triggers identified.
   - UX spec and HTML mockups exist for UI-affecting changes: flows, per-screen state matrix, a component-default row for every interactive control, a11y requirements, responsive/device matrix, design-system conformance, UX acceptance criteria. Every mockup control has a row, every row's mockup exists, and the mockup and the row agree. API-backed components name an approved OpenAPI operation.
6. **Stop** and present the gate result to the user, including the UX spec path and the mockup paths. After explicit approval, append the Design decision (Decision: `Approved`), approver, date, and contract/ADR/diagram/UX-spec/mockup paths to the Intake artifact's `Delivery approvals` section. Do not advance to Build without that approval.

## Rules
`workflow-orchestration.mdc`, `api-and-events.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §2.
