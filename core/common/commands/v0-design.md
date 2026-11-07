---
description: Design phase. Produce the contract draft, event schemas, design.md (traceability, data, authorization, failure modes), ADR, diagrams, and UX spec; review with design-reviewer and gate on user approval.
---

# /v0-design

You are entering the **Design** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
- If `<feature>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not start Design until the lowercase `<feature>` slug is resolved and `docs/agents-v0/requirements/<feature>.md` exists.
- Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/lessons.md` (`workflow-orchestration.mdc` Lessons Memory) and pass entries whose `Scope` matches to `solution-architect`, `ux-designer`, and `design-reviewer`.
- `guard-design.sh check <feature> [--reopen]` verifies the `<feature>` slug, rejects `p0-a*` (greenfield platform skeleton runs `/v0-scaffold`), verifies the current checkout is the `feature/<feature>` worktree, checks the user's external `intake` approval record and committed gate, and ensures `<feature>` is not already released or approved (or checks `reopenCount < 3` when `--reopen` is passed).
- `guard-design.sh start <feature> [--reopen]` verifies a clean working tree on `feature/<feature>`, seeds `docs/agents-v0/design/<feature>/design.md` from `docs/agents-v0/design/_design.template.md` if absent, and sets `docs/agents-v0/requirements/<feature>.state.json` to `in_progress`. Do not edit `docs/agents-v0/requirements/<feature>.state.json` directly; only the guard scripts write it.

## Collision
Write only under `docs/agents-v0/design/<feature>/`, `docs/agents-v0/adr/`, `docs/agents-v0/diagrams/`, and `docs/agents-v0/design/system/arc-record.md`. Do not modify the repo-wide OpenAPI catalog (`openapi/api-v1.yaml` or `openapi/<service>-v1.yaml`) during Design; Build merges the approved draft into the catalog.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-skeleton --> <!-- kitfix-20261031-traceability --> <!-- kitfix-20261031-gate-commit --> The gate commit is step 7: after explicit user approval in his external terminal, `guard-design.sh commit <feature>` promotes the cited ADR to `Status: Accepted`, appends the verified `Design` row, runs traceability checks (`T1`–`T3`, reporting any `TRACE WARN` line), stages only the story's design paths, scans for secrets, and makes one commit `"<story>: design approved"` on `feature/<feature>`, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-design.sh steps (scripts/generate-design-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-design.sh check <feature> [--reopen]`. It validates the `<feature>` slug, blocks `p0-a*` (redirecting to `/v0-scaffold`), verifies the current checkout is the `feature/<feature>` worktree (If no worktree has branch `feature/<feature>`, it refuses and stops), checks the user's external `intake` approval and committed gate, and ensures the story is not already released or approved (or checks `reopenCount < 3` when `--reopen` is passed). When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-design.sh start <feature> [--reopen]`. It verifies a clean working tree on `feature/<feature>`, seeds `docs/agents-v0/design/<feature>/design.md` from `docs/agents-v0/design/_design.template.md` if absent, and sets `docs/agents-v0/requirements/<feature>.state.json` to `in_progress`.
3. Read `docs/agents-v0/lessons.md` and launch the shell-less Design subagents in sequence (none may edit the repo-wide `openapi/` catalog or run shell commands):
   - **Contract draft (`schema-author`):** When the story adds or modifies an HTTP `/api/v1` operation or event contract, write `docs/agents-v0/design/<feature>/openapi.yaml` and/or `docs/agents-v0/design/<feature>/events/`.
   - **Architecture & ADR (`solution-architect`, skill: `contract-first-design`):** Write `docs/agents-v0/design/<feature>/design.md` (tracing every `AC-n` and NFR, data model, BOLA authorization matrix per `operationId`, failure modes naming every `Kind: negative` and `Kind: edge` AC, observability, and rollout), an ADR under `docs/agents-v0/adr/<NN>-<slug>.md` (`Status: Proposed`, comparing at least two alternatives, or `ADR: N/A: no product decision` when `Contract: None`), and `docs/agents-v0/design/system/arc-record.md` when `Material: yes`.
   - **UX spec & mockups (`ux-designer`, skill: `ux-design`):** For UI-affecting stories, write `docs/agents-v0/design/<feature>/ux-spec.md` (flows, loading/error/empty/success state matrix, component defaults, WCAG 2.1 AA rules) and static HTML mockups under `docs/agents-v0/design/<feature>/mockups/` with matching `data-component` attributes.
   - **Design review (`design-reviewer`):** Unless the story qualifies for the `Contract: None` shortcut (no `/api/v1` operation, no event contract, no `ux-spec.md`, no non-health public route, and `Material: no`), launch `design-reviewer` to write `docs/agents-v0/design/<feature>/review.md` and resolve any open `Critical` findings (max 3 cycles).
4. If `docs/agents-v0/design/<feature>/helper-brief.md` exists or open `Critical` findings remain after 3 review cycles, run `sh .agents-v0/scripts/guard-design.sh block <feature> "<plain reason>"` (which deduplicates helper briefs and records `blocked`). If a helper brief was written, launch the named helper, pass findings back, remove the brief, and resume; otherwise stop and escalate to the user.
5. When the design artifacts are complete, run `sh .agents-v0/scripts/guard-design.sh ready <feature>`. It verifies that the repo-wide `openapi/` catalog is untouched, checks `design.md` sections, AC traceability (`T1`–`T3`), `Kind: negative`/`edge` failure modes, OpenAPI 3.0 validity (`/api/v1/`, `additionalProperties: false`, `Idempotency-Key`, BOLA rules), UX mockup `data-component` parity, ADR options, and zero open `Critical` findings in `review.md`. When the story qualifies for the `Contract: None` shortcut, `ready` records `status: contract_none`; run `sh .agents-v0/scripts/guard-design.sh commit <feature>` and proceed directly to `/v0-build <feature>`. Otherwise `ready` writes `docs/agents-v0/requirements/<feature>.phase-result.md` and sets state to `awaiting_approval`. When it prints `REFUSED`, fix what it names and run `ready` again.
6. Stop. Present the design artifacts and `review.md` summary to the user and wait for explicit approval. Next: The user reviews docs/agents-v0/design/<feature>/ and runs, in their own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve design <feature>. Never run approve yourself; the agent cannot approve this gate.
7. After the user runs approve in their own terminal, run `sh .agents-v0/scripts/guard-design.sh commit <feature>`. It verifies the user's external approval record, promotes the cited ADR to `Status: Accepted`, appends the verified `Design` row to `Delivery approvals`, runs traceability checks, stages only the story's design and state paths, scans staged content for secrets, and commits `"<story>: design approved"` on `feature/<feature>`. Then suggest: /v0-build <feature>.
<!-- END generated -->

## Amending an Approved Design
If Build or Verify discovers that an approved contract or design must change:
1. Run `sh .agents-v0/scripts/guard-design.sh check <feature> --reopen` and `sh .agents-v0/scripts/guard-design.sh start <feature> --reopen`, then update the design files under `docs/agents-v0/design/<feature>/` (and supersede any `Accepted` ADR with a new ADR if the architectural decision changed).
2. Re-run `design-reviewer` so `review.md` has zero open `Critical` findings, then run `sh .agents-v0/scripts/guard-design.sh ready <feature>`.
3. Ask the user for explicit approval in their own terminal (`sh .agents-v0/scripts/guard-common.sh approve design <feature>`), then run `sh .agents-v0/scripts/guard-design.sh commit <feature>` before resuming `/v0-build`.

## Rules
`workflow-orchestration.mdc`, `api-and-events.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §2.
