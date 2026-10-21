---
description: Intake phase. Turn a Jira/Confluence/user spec into the requirements artifact with Gherkin acceptance criteria, NFRs, regulations, and structured state.
---

# /v0-intake

You are entering the **Intake** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
- Brownfield: if `docs/agents-v0/onboarding/report.md` exists, `docs/agents-v0/onboarding/state.json` must record `lastApprovedPhase: "onboard"`.
- Milestone story: `plan` must be in `approvedPhases` in `docs/agents-v0/program.state.json`, or the manifest `docs/agents-v0/milestones/<milestone>.md` must have an `Approved` `plan` row. A single ticket with no milestone has no plan to check. Dependency `verify` approvals are required before `/v0-build`, not before Intake.
- P0-A skeleton: skip `/v0-intake` and proceed directly to `/v0-build`.
- If `docs/agents-v0/requirements/<feature>.md` is absent, create it with a title line for `<feature>`. Then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase intake --status in_progress docs/agents-v0/requirements/<feature>.md` and continue from existing files on disk.

## Instructions
1. Classify **change tier** (`workflow-orchestration.mdc`): **Trivial** → route to `/v0-triage`; **Emergency** → route to `/v0-maintain`; **Major** / **Standard** → continue here.
2. Launch the `requirements-analyst` subagent (skill: `spec-intake`) with the source specification.
3. **Helpers:** If `docs/agents-v0/requirements/<feature>.helper-brief.md` exists, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/<feature>.md` to verify no duplicate brief loop, launch `explore-researcher`, pass the findings back to `requirements-analyst`, and delete the brief.
4. Produce `docs/agents-v0/requirements/<feature>.md` following `spec-intake`:
   - User story formatted as `As a [role], I want [goal], so that [benefit].` (no unresolved `<...>` placeholders).
   - Gherkin acceptance criteria (`### AC-1 — <name>`, `Kind: happy | negative | edge`, `Given` / `When` / `Then` with observable outcomes), capped at `AC-1` through `AC-8` on a single primary surface (`Surfaces: backend | bff | frontend`, or `Vertical slice: yes` when requested). If the story is oversized, write `## Proposed split`. If it is oversized or the user story is still incomplete, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase intake --status blocked --reason "Proposed split or incomplete user story pending user confirmation" docs/agents-v0/requirements/<feature>.md` and stop.
   - At least one `Kind: negative` or `Kind: edge` scenario (or `Negatives: N/A: <reason>` when no security trigger applies; security triggers like auth, RBAC, uploads, public routes, or any `{id}` path must include a refusing `Kind: negative`).
   - Preconditions, Desk check, NFRs, regulations, security-review triggers, `Material: yes | no`, and `Open questions: none` (resolve any open questions with the user first).
   - For UI-affecting stories, include UX requirements (WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria).
5. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`phase: intake`, `status: awaiting_approval`, `user_story`, `ac_count`, `negative_count`, `regulations`, `open_questions`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase intake --status awaiting_approval docs/agents-v0/requirements/<feature>.md`.
6. **Stop** and present the requirements summary to the user. After explicit user approval, append the `Intake` row (Decision `Approved`) to `## Delivery approvals` in `docs/agents-v0/requirements/<feature>.md`, update `<feature>.phase-result.md` to `status: approved`, then run `sh .agents-v0/scripts/sync-feature-state.sh --approve intake docs/agents-v0/requirements/<feature>.md`. Do not advance to `/v0-design` without that approval.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`, `frontend-web.mdc`, `security-baseline.mdc` §11.
