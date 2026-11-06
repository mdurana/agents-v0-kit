---
description: Platform skeleton scaffolding for greenfield projects. Establish a working baseline, Dockerfile, compose, and verified test runner before /v0-intake.
---

# /v0-scaffold

You are entering **platform scaffolding** (`workflow-orchestration.mdc`). Use it for greenfield projects to establish a verified baseline on the integration branch before feature story intake.

## Prerequisite
Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/milestones/p0-platform-skeleton.md`. `guard-scaffold.sh check` verifies entry prerequisites, greenfield status, integration branch check, Sensei's external approval record for `plan`, and that `scaffold` is not already in `approvedPhases`. Brownfield projects stop and suggest `/v0-onboard`.

## Resume
The guard decides: `guard-scaffold.sh start` (step 2) checks for a clean working tree on the integration branch and sets state to `in_progress`. Continue from the platform files already on disk. Do not edit `docs/agents-v0/program.state.json`; only the guard scripts write it.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-gate-commit --> The gate commit is step 7: one commit and one `scaffold-v<n>` tag, made by the guard, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-scaffold.sh steps (scripts/generate-scaffold-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-scaffold.sh check`. It verifies entry prerequisites, greenfield status, on-branch integration check, Sensei's external plan approval record, and that scaffold is not already approved. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-scaffold.sh start`. It verifies a clean working tree on the integration branch and sets `docs/agents-v0/program.state.json` to `in_progress` on `docs/agents-v0/milestones/p0-platform-skeleton.md`.
3. Launch the `platform-engineer` subagent to configure application scaffold files under `app/`, `Dockerfile`, `docker-compose.yml`, and CI verify baseline. It runs no shell commands and leaves `Delivery approvals` tables empty.
4. On a blocker, run `sh .agents-v0/scripts/guard-scaffold.sh block "<plain reason>"` and stop.
5. When the platform skeleton and container configurations are complete, run `sh .agents-v0/scripts/guard-scaffold.sh ready`. It verifies the milestone P0 manifest, Dockerfile, docker-compose.yml, executes the pack's native backend verify command, writes `docs/agents-v0/milestones/scaffold.phase-result.md`, and sets state to `awaiting_approval`. When it prints `REFUSED`, fix what it names and run `ready` again.
6. Stop. Present the platform skeleton verification report to Sensei. Next: Sensei reviews the platform skeleton and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve scaffold. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal, run `sh .agents-v0/scripts/guard-scaffold.sh commit`. It verifies Sensei's approval record, updates `p0-platform-skeleton.md` status to released with the approved Delivery row, stages scaffold files, secret-scans, makes the single gate commit, and tags `scaffold-v<n>`. Then suggest: /v0-intake.
<!-- END generated -->

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11, `quality-and-testing.mdc`.
