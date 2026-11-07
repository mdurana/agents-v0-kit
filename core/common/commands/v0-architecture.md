---
description: Program architecture before any backlog. C4 through operations, then the ARC pack. Stories are written later by /v0-plan.
---

# /v0-architecture

You are entering **program architecture** (`workflow-orchestration.mdc`). This command runs after an approved roadmap and before `/v0-plan`. It does not write stories or a feature OpenAPI draft.

## Prerequisite
`guard-architecture.sh check` verifies entry prerequisites, onboard approval on brownfield codebases, the user's external approval record for `roadmap`, and that `architecture` is not already in `approvedPhases`. A Major story with no roadmap stops and suggests `/v0-design` (`system-design`). A single named ticket stops and suggests `/v0-intake`. P0-A stops and suggests `/v0-build`. A docs-only edit or a 1-for-1 patch bump stops and suggests `/v0-triage`. Any other fix stops and suggests `/v0-maintain`.

## Resume
The guard decides: `guard-architecture.sh start` (step 2) checks for a clean feature tree and sets state to `in_progress`. Continue from the architecture files already on disk. Do not recreate filled sections. Do not rewrite an `Accepted` ADR; supersede it with a new ADR when a decision changes. Do not edit `docs/agents-v0/program.state.json`; only the guard scripts write it.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-gate-commit --> The gate commit is step 8: one commit and one `architecture-v<n>` tag, made by the guard, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-architecture.sh steps (scripts/generate-architecture-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-architecture.sh check`. It verifies entry prerequisites, onboard approval on brownfield codebases, the user's external roadmap approval record, and that architecture is not already approved. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-architecture.sh start`. It verifies a clean feature tree and sets `docs/agents-v0/program.state.json` to `in_progress` on `docs/agents-v0/architecture.md`.
3. Launch the `solution-architect` subagent (skill: `program-architecture`) to author the architecture pack in order: C4 Context and Container in `docs/agents-v0/architecture.md`, Pattern ADR with `Pack: <id>` under `docs/agents-v0/adr/` (preserving any existing brownfield `Pack` cell in `docs/agents-v0/project-profile.md`), platform topology in `docs/agents-v0/network.md`, `docs/agents-v0/design/system/context-map.md` and per-context `components/<service>.md`, data flow / `erDiagram` / state machine / failure domains / MVP vs. future state in `architecture.md`, and `nfr-slo.md`, `threat-model.md`, `ops-readiness.md`, and `arc-record.md`. It runs no shell commands and leaves the `Delivery approvals` table empty.
4. Launch the `design-reviewer` subagent on the architecture pack to write `docs/agents-v0/design/system/architecture-review.md`. Route any `Open` findings back to `solution-architect` to fix or disposition (`Resolved`, `Deferred`, or `Accepted`), and re-run `design-reviewer` until zero `Open` findings remain in `architecture-review.md` (max 3 review cycles before escalating to the user). Both subagents run no shell commands.
5. On a blocker, run `sh .agents-v0/scripts/guard-architecture.sh block "<plain reason>"` and stop.
6. When the pack and review are complete, run `sh .agents-v0/scripts/guard-architecture.sh ready`. It verifies mandatory sections in `architecture.md` and `network.md`, pattern ADR with `Pack: <id>`, required `design/system/` files without placeholders, and `architecture-review.md` with `agent: design-reviewer` and zero `Open` findings, writes `docs/agents-v0/architecture.phase-result.md`, and sets state to `awaiting_approval`. When it prints `REFUSED`, fix what it names and run `ready` again.
7. Stop. Present the architecture pack, `architecture-review.md`, and `architecture.phase-result.md` to the user. Next: The user reviews the architecture pack and runs, in their own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve architecture. Never run approve yourself; the agent cannot approve this gate.
8. After the user runs approve in their own terminal, run `sh .agents-v0/scripts/guard-architecture.sh commit`. It verifies the user's approval record, promotes the pattern ADR `Status` to `Accepted`, updates `(Proposed)` ADR labels, appends the verified `architecture` row to `Delivery approvals`, binds the stack pack into `docs/agents-v0/project-profile.md` and `.cursor/`, stages architecture files, secret-scans, makes the single gate commit, and tags `architecture-v<n>`. Then suggest: /v0-plan.
<!-- END generated -->

## Rules
`workflow-orchestration.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11.
