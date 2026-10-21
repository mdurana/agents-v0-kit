---
description: Program planning. Decompose an approved roadmap and architecture pack into milestone manifests and ordered stories before /v0-intake.
---

# /v0-plan

You are entering **program planning** (`workflow-orchestration.mdc`). Use it when the goal is larger than one story. A single named ticket goes straight to `/v0-intake`; the seeded P0-A story goes to `/v0-build`.

## Prerequisite
Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/repo-map.md`. Except for a P0-A-only plan, `docs/agents-v0/program.state.json` must record both `roadmap` and `architecture` in `approvedPhases` (or `Approved` rows in `roadmap/<program>.md` and `architecture.md`), and the profile `Pack` cell must be bound to a complete pack.

## Resume
Continue from the milestone manifests already on disk: preserve approved or seeded `P0-A` rows, replace template stubs, and author concrete stories adhering to the story-size budget and roadmap horizons.

## Instructions
1. Launch the `program-planner` subagent (skill: `program-planning`) with the approved roadmap and `docs/agents-v0/design/system/context-map.md`.
2. **Helpers:** If `docs/agents-v0/design/system/<program>.helper-brief.md` exists, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/architecture.md` to check for duplicate helper briefs, launch `explore-researcher`, pass the findings back to `program-planner`, and delete the brief.
3. Verify the **Plan gate** criteria from `program-planning`:
   - Every story maps to a bounded context in `context-map.md` and a goal from the approved roadmap.
   - Each milestone manifest under `docs/agents-v0/milestones/` has concrete `As a [role], I want [goal], so that [benefit].` stories, feature artifact paths, acyclic story-ID dependencies, `Surface` (`backend`, `bff`, `frontend`, or `vertical slice`), and `Size` (`1`–`8`).
   - Cross-context calls have an integration story depending on both sides; P4 covers NFR/SLO targets and P5 covers `ops-readiness.md`.
4. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase plan --status awaiting_approval docs/agents-v0/milestones/plan.md`.
5. **Stop** and present `docs/agents-v0/milestones/plan.md` (milestone table and story dependency flowchart) to the user. After explicit user approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve plan docs/agents-v0/milestones/plan.md`.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11.
