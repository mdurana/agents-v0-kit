---
description: Design phase. Produce the contract draft, event schemas, design.md (traceability, data, authorization, failure modes), ADR, diagrams, and UX spec; review with design-reviewer and gate on user approval.
---

# /v0-design

You are entering the **Design** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
1. If `<feature>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not set `in_progress` until it resolves. If `docs/agents-v0/requirements/<feature>.md` does not exist, stop and ask for the slug. Do not mark Design blocked on a missing file. Read `docs/agents-v0/requirements/<feature>.state.json` and `docs/agents-v0/requirements/<feature>.phase-result.md` when present. If `release` is in `approvedPhases`, stop. Do not reopen the story. A docs-only edit or a 1-for-1 patch bump starts at `/v0-triage`. Any other fix starts at `/v0-maintain`. A new feature starts at `/v0-intake` with a new slug. Run `git worktree list` and look for branch `feature/<feature>`. If that worktree exists and this checkout is not it, stop. Open that folder and run `/v0-status <feature>` there. If no worktree has branch `feature/<feature>` (Intake step 7 did not run), stop: do not set `in_progress` and do not work on the integration branch. Tell the user that `/v0-intake <feature>` must finish its gate commit and worktree step (Sensei approves via `sh .agents-v0/scripts/guard-common.sh approve intake <feature>`, authorises the branch in its own turn, and then `sh .agents-v0/scripts/guard-intake.sh commit <feature>` runs) and that this phase continues in the printed folder.
2. Greenfield platform skeleton (`P0-A`) runs `/v0-scaffold` on the integration branch, not `/v0-design`.
3. Verify that `intake` is in `approvedPhases` in `docs/agents-v0/requirements/<feature>.state.json`, Sensei's external intake approval record (`sh .agents-v0/scripts/guard-common.sh approve intake <feature>`) is verified, and `Delivery approvals` has an `Approved` `Intake` row committed on `feature/<feature>`. If missing, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status blocked --reason "Intake not approved" docs/agents-v0/requirements/<feature>.md` and stop.
4. If `design` is already in `approvedPhases` and this run is not `--reopen design`, stop. Do not set `in_progress`. The next command is `/v0-build`. Otherwise run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status in_progress docs/agents-v0/requirements/<feature>.md` and continue from existing files under `docs/agents-v0/design/<feature>/`.
<!-- MEM-05: phase agents read the accepted cross-story lessons before they start, and leave lesson candidates in the phase-result at the gate (workflow-orchestration.mdc Lessons Memory). -->
5. Read the lessons memory (`docs/agents-v0/lessons.md`, `workflow-orchestration.mdc` Lessons Memory) and pass entries whose `Scope` matches to `solution-architect`, `ux-designer`, and `design-reviewer`.

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
   - When the requirements artifact is `tier: major` and no `Approved` `architecture` row exists, follow `system-design` before feature contracts. Do not run `/v0-architecture`.
3. **UX design (`ux-designer`, skill: `ux-design`):** For UI-affecting stories, produce `docs/agents-v0/design/<feature>/ux-spec.md` (user flows, per-screen loading/error/empty/success state matrix, component table with `data-component` and either an OpenAPI `operationId` or `METHOD /api/v1/...` from the feature draft, WCAG 2.1 AA rules) and static HTML mockups under `docs/agents-v0/design/<feature>/mockups/`.
4. **Helpers:** If `docs/agents-v0/design/<feature>/helper-brief.md` exists, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/<feature>.md`, launch the named helper from this session, pass the result back, and delete the brief.
5. **No-contract shortcut (`Contract: None`):** When `design.md` records `N/A: no /api/v1 operation` and `N/A: no event contract`, there is no `ux-spec.md`, no new public route other than `/health`, `/ready`, or `/live`, and `Material: no`, skip `design-reviewer` and proceed directly to `/v0-build`. Skip steps 6–8. Do not run `--approve design`. `/v0-build` accepts that `design.md`, and `--approve build` backfills `design`.
6. **Design review (`design-reviewer`):** For all other stories, launch `design-reviewer` to inspect `design.md`, `openapi.yaml`, `asyncapi.yaml`, `events/` (when present), `ux-spec.md`, `mockups/`, and the cited ADR, writing `docs/agents-v0/design/<feature>/review.md`. If `review.md` reports any open `Critical` finding, route back to `solution-architect` or `ux-designer` to resolve it and re-run `design-reviewer` (max 3 cycles, prompt-only, before escalating to the user).
7. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`phase: design`, `status: awaiting_approval`, and `## Lessons` → `### design` with at most 3 candidates or `- none`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status awaiting_approval docs/agents-v0/requirements/<feature>.md`.
8. **Stop** and present the design artifacts and `review.md` summary to the user. After explicit user approval:
   - Set the cited ADR's `Status` to `Accepted` (when an ADR was written).
   - Update `<feature>.phase-result.md` to `status: approved`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/<feature>.md`. It refuses when `docs/agents-v0/design/<feature>/design.md` is missing or empty: you write the design evidence yourself; nothing fills it in for you (kitfix-20261031-skeleton).
   - <!-- kitfix-20261031-traceability --> The approval runs `check-traceability.sh design`: every `AC-<n>` of the requirements must be in `design.md` Traceability (T1), the AC count must match the milestone `Size` (T2, blames Intake unless `## Proposed split` or a `Plan deviation:` line is recorded), and `design.md` must not name unknown AC ids (T3). Each `TRACE WARN` line names the check and the earliest bad phase; report every one to the user in the approval reply. With `trace_mode=fail` in `.agents-v0/policy.conf` (set by the team or the e2e harness, never by the agent; the hooks protect the file) a failing check refuses the approval: fix the artifact of the phase it blames.
   - <!-- kitfix-20261031-gate-commit --> **Commit the gate on `feature/<feature>`**: run the command the script prints (`git add -A && git commit -m "<story>: design approved"`), one commit, never `--amend`. `/v0-build` does not start (`--active-phase build --status in_progress` refuses) while the tree holds uncommitted Design work.

## Amending an Approved Design
If Build or Verify discovers that an approved contract or design must change:
1. Run `sh .agents-v0/scripts/sync-feature-state.sh --reopen design docs/agents-v0/requirements/<feature>.md`, then update the design files under `docs/agents-v0/design/<feature>/` (and supersede any `Accepted` ADR with a new ADR if the architectural decision changed).
2. Re-run `design-reviewer` so `review.md` has zero open `Critical` findings.
3. Ask the user to approve the design amendment. After that approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve design docs/agents-v0/requirements/<feature>.md` before resuming `/v0-build`.

## Rules
`workflow-orchestration.mdc`, `api-and-events.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §2.
