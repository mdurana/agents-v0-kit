---
description: Program planning. Decompose an approved roadmap and architecture pack into milestone manifests and ordered stories before /v0-intake.
---

# /v0-plan

You are entering **program planning** (`workflow-orchestration.mdc`). Use it when the goal is larger than one story.

## Prerequisite
<!-- MEM-05: Plan reads the accepted cross-story lessons so milestone sizing and ordering learn from earlier stories. Plan is a program phase and writes no lesson candidates. -->
Read `docs/agents-v0/project-profile.md`, `docs/agents-v0/repo-map.md`, and the lessons memory (`docs/agents-v0/lessons.md`, `workflow-orchestration.mdc` Lessons Memory). `guard-plan.sh check` verifies entry prerequisites, onboard approval on brownfield codebases, Sensei's external approval record for `architecture`, and that `plan` is not already in `approvedPhases`. A single named ticket stops and suggests `/v0-intake`. The seeded P0-A story stops and suggests `/v0-build`. A docs-only edit or a 1-for-1 patch bump stops and suggests `/v0-triage`. Any other fix stops and suggests `/v0-maintain`. The profile `Pack` cell must be bound to a complete pack before a non-P0-A plan starts.

## Resume
The guard decides: `guard-plan.sh start` (step 2) checks for a clean feature tree and sets state to `in_progress`. Continue from the milestone manifests already on disk: preserve approved or seeded `P0-A` rows, replace template stubs, and author concrete stories adhering to the story-size budget and roadmap horizons. Do not edit `docs/agents-v0/program.state.json`; only the guard scripts write it.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-gate-commit --> The gate commit is step 7: one commit and one `plan-v<n>` tag, made by the guard, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-plan.sh steps (scripts/generate-plan-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-plan.sh check`. It verifies entry prerequisites, onboard approval on brownfield codebases, Sensei's external architecture approval record, and that plan is not already approved. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-plan.sh start`. It verifies a clean feature tree and sets `docs/agents-v0/program.state.json` to `in_progress` on `docs/agents-v0/milestones/plan.md`.
3. Launch the `program-planner` subagent (skill: `program-planning`) to author milestone manifests under `docs/agents-v0/milestones/` and `docs/agents-v0/milestones/plan.md` (milestone summary table and `flowchart TD` story dependency graph). It runs no shell commands and leaves `Delivery approvals` tables empty.
4. On a blocker, run `sh .agents-v0/scripts/guard-plan.sh block "<plain reason>"` and stop.
5. When milestone manifests and plan.md are complete, run `sh .agents-v0/scripts/guard-plan.sh ready`. It verifies that every manifest has concrete `As a [role], I want [goal], so that [benefit].` stories without placeholders, valid `Surface`, valid `Size` (`1`–`8`, seeded P0-A = `4`), concrete story-ID dependencies without cycles, and integration stories for cross-context calls, writes `docs/agents-v0/milestones/plan.phase-result.md`, and sets state to `awaiting_approval`. When it prints `REFUSED`, fix what it names and run `ready` again.
6. Stop. Present the milestone manifests and `docs/agents-v0/milestones/plan.md` to Sensei. Next: Sensei reviews the plan manifests and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve plan. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal, run `sh .agents-v0/scripts/guard-plan.sh commit`. It verifies Sensei's approval record, appends the verified `plan` row to `Delivery approvals` in `plan.md` and every in-scope milestone manifest, stages plan files, secret-scans, makes the single gate commit, and tags `plan-v<n>`. Then suggest: /v0-intake, or /v0-build when the first story is P0-A.
<!-- END generated -->

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11.
