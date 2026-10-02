---
description: Design phase. Produce the contract draft, event schemas, design.md (traceability, data, authorization, failure modes), an ADR, diagrams, and the UX spec; check, review, approve, and pin.
---

# /v0-design

You are entering the **Design** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching the architect, read `docs/agents-v0/requirements/<feature>.phase-result.md` when it exists. Confirm the Intake requirements artifact exists and its `Delivery approvals` section records an explicit Intake approval. If either is missing, and the artifact exists, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase design --status blocked --reason "<one line>"`, then stop and report the missing evidence; do not infer approval. On a brownfield repo the architect also reads the as-is documents: `docs/agents-v0/architecture.md`, `docs/agents-v0/design/system/context-map.md`, the `docs/agents-v0/onboarding/modules/` documents for the touched modules, and `docs/agents-v0/discovery/endpoints.txt` for existing operations the draft could clash with.

## Resume
When the artifact exists, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase design --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves. If this phase's approval row says `Re-opened` (`/v0-deliver`), the phase is open again: continue from the files, and set `Approved` only after the user approves the re-run.

## Collision
While another feature is in flight in this checkout, write only `docs/agents-v0/requirements/<feature>.md`, its state file, and `docs/agents-v0/design/<feature>/`. The feature contract draft is `docs/agents-v0/design/<feature>/openapi.yaml`. Do not edit the org catalog (`openapi/api-v1.yaml`, or the catalog path in the profile) during Design. Stop before editing any other shared file (`workflow-orchestration.mdc` Parallel features) when `git status` shows it is already modified or another feature's state is `in_progress`, `awaiting_approval`, or `blocked` on a phase that writes it. Record `--status blocked` with that reason.

## Instructions
1. Launch the `solution-architect` subagent with the Intake artifact.
2. **Helpers.** If `docs/agents-v0/design/<feature>/helper-brief.md` exists, launch the helper it names (`schema-author` for the contract draft, `docs-author` when the UX spec asks) from this session. Pass the result into the phase agent that wrote the brief. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents). Repeat until no brief remains. Do not present the gate while a brief is on disk.
3. For UI-affecting changes, launch the `ux-designer` subagent (skill: `ux-design`) after the feature draft `docs/agents-v0/design/<feature>/openapi.yaml` exists. Run the helper step again if that agent leaves a brief. Produce `docs/agents-v0/design/<feature>/ux-spec.md` and static HTML mockups under `docs/agents-v0/design/<feature>/mockups/`. The spec includes user flows, a per-screen state matrix (loading/error/empty/success) linked to those mockups, per-component default behavior (name, screen, mockup, OpenAPI operation or `—`, default behavior, override), WCAG 2.1 AA accessibility requirements, a responsive/device matrix, design-system conformance, and UX acceptance criteria. Mockups do not call the API, and every interactive element carries `data-component="<name>"`. A component that calls the API names an operation in `docs/agents-v0/design/<feature>/openapi.yaml`.
4. For **Major** tier changes, the architect must also follow `system-design` (context boundaries, failure modes, rollout).
5. The architect must follow the `contract-first-design` skill and produce:
   - The feature OpenAPI 3.0 draft at `docs/agents-v0/design/<feature>/openapi.yaml` for `/api/v1/...`. The org catalog stays unchanged until Build.
   - Event schemas under `docs/agents-v0/design/<feature>/events/` with `eventVersion`; additive evolution.
   - One error envelope per API surface (RFC 7807 **or** custom — not mixed).
   - Idempotency keys on non-idempotent creates.
   - `docs/agents-v0/design/<feature>/design.md` from `docs/agents-v0/design/_design.template.md`: traceability of every AC and NFR, data model, an authorization matrix with the resource rule per operation, failure modes, observability, and rollout.
   - An ADR for non-trivial decisions, with the real alternatives.
   - Mermaid diagrams following `architecture-and-diagrams.mdc` conventions.
6. **Mechanical checks.** Run, and fix until each passes: `sh .agents-v0/ci/check-openapi.sh lint docs/agents-v0/design/<feature>/openapi.yaml`; `sh .agents-v0/ci/check-openapi.sh compat docs/agents-v0/design/<feature>/openapi.yaml <catalog>` when the catalog exists; `sh .agents-v0/ci/check-design.sh <feature>`; for UI changes `sh .agents-v0/ci/check-ux-spec.sh <feature>`.
7. **Design review.** Launch the `design-reviewer` subagent. It writes `docs/agents-v0/design/<feature>/review.md` for the current design. Route each Critical finding back to the `solution-architect` (or `ux-designer`), then run the reviewer again: the review must name the design's current hash.
8. Check the **Design gate** (`workflow-orchestration.mdc`):
   - Feature draft `docs/agents-v0/design/<feature>/openapi.yaml` and event schemas under `docs/agents-v0/design/<feature>/events/` defined with `eventVersion`. The org catalog is not part of this gate.
   - The mechanical checks above pass, and `review.md` has no open Critical finding.
   - Error envelope chosen per surface.
   - ADR exists, with at least two alternatives.
   - Diagrams follow Mermaid conventions.
   - Security-review triggers identified; brief threat-model notes (assets, trust boundaries, top risks) for non-trivial security.
   - UX spec and HTML mockups exist for UI-affecting changes: flows, per-screen state matrix, a component-default row for every interactive control, a11y requirements, responsive/device matrix, design-system conformance, UX acceptance criteria. `ci/check-ux-spec.sh` passes, and API-backed components name an operation in the feature draft.
9. **Stop** and present the gate result to the user, including the feature draft path, `design.md`, the UX spec path, the mockup paths, and the review's open Suggestions. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result). After explicit approval, append the Design decision (Decision: `Approved`), approver, date, and contract/design/ADR/diagram/UX-spec/mockup paths to the Intake artifact's `Delivery approvals` section, then pin the approved design: `sh .agents-v0/ci/check-design.sh <feature> --pin "approved"`. The contract path in that row is `docs/agents-v0/design/<feature>/openapi.yaml`. Do not advance to Build without that approval.

## Amending an approved design
Build, Verify, or a review may find the approved design wrong. Do not edit the design in place and carry on. Set the phase `blocked` (reason "design amendment"), then follow `docs/agents-v0/design/_amendments.template.md`: change the files, run the checks and `design-reviewer` again, add a row to `docs/agents-v0/design/<feature>/amendments.md` with the first 12 characters of `sh .agents-v0/ci/check-design.sh <feature> --hash`, get the user's explicit approval on that row, and pin it (`--pin "amendment <n>"`). CI (`ci/check-design.sh --verify-lock`) rejects a design that changed without an Approved amendment row.

## Rules
`workflow-orchestration.mdc`, `api-and-events.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §2.
