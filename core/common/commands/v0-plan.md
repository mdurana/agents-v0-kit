---
description: Program planning. Decompose an approved roadmap and architecture pack into milestone manifests and ordered stories before /v0-intake.
---

# /v0-plan

You are entering **program planning** (`workflow-orchestration.mdc` Program planning). Use it when the goal is larger than one story: a new platform, a multi-service change, or any Major-tier program. A single named ticket goes straight to `/v0-intake`. The seeded P0-A story goes to `/v0-build`.

## Prerequisite
Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/repo-map.md` when they exist. A brownfield repo needs an `Approved` `onboard` row in `docs/agents-v0/onboarding/report.md` (run `/v0-onboard` first). Read the context map from the approved architecture pack. The onboard map is the input only when this command was skipped (P0-A or a single ticket). If the profile's Layout is still a placeholder on a greenfield repo, record the profile with the user before planning.

A plan whose only story is the seeded P0-A row does not require a roadmap or an architecture pack. Any other program needs an `Approved` `roadmap` row on `docs/agents-v0/roadmap/<program>.md`, an `Approved` `architecture` row on `docs/agents-v0/architecture.md`, and a `Pack` cell whose `.agents-v0/packs/<id>/pack.json` is complete. When the roadmap row is missing, stop and ask for `/v0-roadmap <discovery-path>`. When the architecture row is missing, stop and ask for `/v0-architecture`. When `Pack` is empty, still a placeholder, or has no complete manifest, stop and ask for `/v0-architecture` to bind it. Do not interview. Do not rewrite the architecture pack. Read the discovery file only at the `Discovery:` path recorded on that roadmap.

## Resume
Continue from the milestone manifests already on disk. Do not recreate story rows. The context map is an input from `/v0-architecture`. A program has no per-feature state file (`workflow-orchestration.mdc` Program planning).

## Collision
Planning writes milestone manifests and `docs/agents-v0/milestones/plan.md`. It does not write `docs/agents-v0/design/system/` or ADRs. Stop before editing a manifest that `git status` already shows modified by a feature in flight, and ask which checkout owns it.

## Instructions
1. Launch the `program-planner` subagent with the approved roadmap. A P0-A-only plan may start from the seeded milestone instead.
2. **Helpers.** If a `docs/agents-v0/design/system/<program>.helper-brief.md` exists, launch the helper it names (`explore-researcher` unless the brief says otherwise) from this session. Pass the result into a second launch of `program-planner`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
3. The planner follows `program-planning` (milestone manifests, stories, dependency order). Every story goal comes from the approved roadmap and fits a context already on the context map. Do not add a theme the roadmap does not name. Do not add a context the architecture pack does not name.
4. Check the **Plan gate** (`workflow-orchestration.mdc`):
   - The context map from `/v0-architecture` already names every bounded context in scope. Plan reads it and does not write it.
   - Each milestone manifest in scope exists under `docs/agents-v0/milestones/` with concrete stories: a full `As a [role], I want [goal], so that [benefit].` sentence, a feature artifact path, a dependency column that names story IDs, and Surface and Size filled. Each manifest records `Roadmap:` and `Architecture: docs/agents-v0/architecture.md`, except a P0-A-only plan.
   - Dependencies form an acyclic order (`ci/check-milestone.sh` enforces it once stories are approved).
   - Every story fits the story-size budget: one surface, at most eight acceptance criteria, including the negative or edge Intake will add. Seeded P0-A stays at four.
   - Every pair of bounded contexts that talk to each other has an integration story that depends on both sides.
   - Hardening stories (P4) exist for every filled NFR/SLO row.
5. **Stop** and present `docs/agents-v0/milestones/plan.md` (the milestone table and the story flowchart). The context map is the approved input, not a plan deliverable. After explicit approval, append a `plan` row (Decision: `Approved`, approver, date, `docs/agents-v0/milestones/plan.md`, the manifest, and the roadmap path) to the `Delivery approvals` table of each manifest in scope. Do not start `/v0-intake` for any story without that approval.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11.
