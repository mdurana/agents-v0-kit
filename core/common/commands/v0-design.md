---
description: Design phase. Produce the contract draft, event schemas, design.md (traceability, data, authorization, failure modes), ADR, diagrams, and UX spec; review with design-reviewer and gate on user approval.
---

# /v0-design

You are entering the **Design** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
1. Read `docs/agents-v0/requirements/<feature>.state.json` and `docs/agents-v0/requirements/<feature>.phase-result.md` when present.
2. When the story is `Story: P0-A` (`Milestone: P0`), skip `/v0-design` and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status in_progress docs/agents-v0/requirements/<feature>.md`.
3. Otherwise verify that `intake` is in `approvedPhases` in `docs/agents-v0/requirements/<feature>.state.json` (or `Delivery approvals` has an `Approved` `intake` row). If missing, mark `--active-phase design --status blocked --reason "Intake not approved"` and stop.
4. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status in_progress docs/agents-v0/requirements/<feature>.md` and continue from existing files under `docs/agents-v0/design/<feature>/`.

## Collision
Write only under `docs/agents-v0/design/<feature>/`, `docs/agents-v0/adr/`, and the feature's state/result files. Do not modify the repo-wide OpenAPI catalog (`openapi/api-v1.yaml` or `openapi/<service>-v1.yaml`) during Design; Build merges the approved draft into the catalog.

## Instructions
1. **Contract draft (`schema-author`):** When the story adds or modifies an HTTP `/api/v1` operation or event contract (`asyncapi.yaml` / `events/`), launch `schema-author` to write `docs/agents-v0/design/<feature>/openapi.yaml` and/or `docs/agents-v0/design/<feature>/events/`.
2. **Design architecture (`solution-architect`, skill: `contract-first-design`):**
   - Write `docs/agents-v0/design/<feature>/design.md` from `docs/agents-v0/design/_design.template.md`: trace every `AC-*` and NFR, define the data model, provide an authorization matrix per operation, list failure modes covering every `Kind: negative` and `Kind: edge` AC, and document observability and rollout.
   - When the story has no HTTP API change, record `N/A: no /api/v1 operation` in `design.md`. When it has no events, record `N/A: no event contract`.
   - Write an ADR under `docs/agents-v0/adr/<NN>-<slug>.md` comparing at least two alternatives (`Status: Proposed`), or record `ADR: N/A: no product decision` when no contract/architecture decision is needed.
   - When `Material: yes` on the requirements artifact, write or update `docs/agents-v0/design/system/arc-record.md`.
   - When security-review triggers apply, include threat-model notes naming applicable VAPT findings (`F4`, `F8`, `F9`, `F10`).
3. **UX design (`ux-designer`, skill: `ux-design`):** For UI-affecting stories, produce `docs/agents-v0/design/<feature>/ux-spec.md` (user flows, per-screen loading/error/empty/success state matrix, component table with `data-component` and OpenAPI `operationId`, WCAG 2.1 AA rules) and static HTML mockups under `docs/agents-v0/design/<feature>/mockups/`.
4. **No-contract shortcut (`Contract: None`):** When `design.md` records `N/A: no /api/v1 operation` and `N/A: no event contract`, there is no `ux-spec.md`, no new public route other than `/health`, `/ready`, or `/live`, and `Material: no`, skip `design-reviewer`, run `sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/<feature>.md`, and proceed directly to `/v0-build`.
5. **Design review (`design-reviewer`):** For all other stories, launch `design-reviewer` to inspect `design.md`, `openapi.yaml`, `asyncapi.yaml`, `ux-spec.md`, `mockups/`, and the cited ADR, writing `docs/agents-v0/design/<feature>/review.md`. If `review.md` reports any open `Critical` finding, route back to `solution-architect` or `ux-designer` to resolve it and re-run `design-reviewer` (max 3 cycles).
6. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`phase: design`, `status: awaiting_approval`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status awaiting_approval docs/agents-v0/requirements/<feature>.md`.
7. **Stop** and present the design artifacts and `review.md` summary to the user. After explicit user approval:
   - Set the cited ADR's `Status` to `Accepted` (when an ADR was written).
   - Update `<feature>.phase-result.md` to `status: approved`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/<feature>.md`.

## Amending an Approved Design
If Build or Verify discovers that an approved contract or design must change:
1. Update the design files under `docs/agents-v0/design/<feature>/` (and supersede any `Accepted` ADR with a new ADR if the architectural decision changed).
2. Re-run `design-reviewer` so `review.md` has zero open `Critical` findings.
3. Ask the user to approve the design amendment before resuming `/v0-build`.

## Rules
`workflow-orchestration.mdc`, `api-and-events.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §2.
