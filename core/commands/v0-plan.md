---
description: Program planning. Decompose a large goal into a context map, milestone manifests, and ordered stories before /v0-intake.
---

# /v0-plan

You are entering **program planning** (`workflow-orchestration.mdc` Program planning). Use it when the goal is larger than one story: a new platform, a multi-service change, or any Major-tier program. A single story goes straight to `/v0-intake`.

## Prerequisite
Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/repo-map.md` when they exist. A brownfield repo needs an `Approved` `onboard` row in `docs/agents-v0/onboarding/report.md` (run `/v0-onboard` first); its as-is `docs/agents-v0/design/system/context-map.md` is the starting point. If the profile's Layout is still a placeholder on a greenfield repo, record the profile with the user before planning.

## Resume
Continue from the context map and the milestone manifests already on disk; do not recreate them. A program has no per-feature state file (`workflow-orchestration.mdc` Program planning).

## Collision
Planning writes shared files (the milestone manifests, `docs/agents-v0/design/system/`, ADRs). Stop before editing one that `git status` already shows modified by a feature in flight, and ask which checkout owns it.

## Instructions
1. Launch the `program-planner` subagent with the goal (Jira epic, Confluence page, or user description).
2. **Helpers.** If a `docs/agents-v0/design/system/<program>.helper-brief.md` exists, launch the helper it names (`explore-researcher` unless the brief says otherwise) from this session. Pass the result into a second launch of `program-planner`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
3. The planner follows `system-design` (context map, NFR/SLO budget, threat-model notes, ADR) and then `program-planning` (milestone manifests, stories, dependency order).
4. Check the **Plan gate** (`workflow-orchestration.mdc`):
   - `docs/agents-v0/design/system/context-map.md` names every bounded context in scope, its service root (when the profile lists `Service roots`), and how it integrates with the others.
   - Each milestone manifest in scope exists under `docs/agents-v0/milestones/` with concrete stories: a full `As a [role], I want [goal], so that [benefit].` sentence, a feature artifact path, and a dependency column that names story IDs.
   - Dependencies form an acyclic order (`ci/check-milestone.sh` enforces it once stories are approved).
   - Every story fits the story-size budget: one surface, at most eight acceptance criteria.
   - Every pair of bounded contexts that talk to each other has an integration story that depends on both sides.
   - Hardening stories (P4) exist for every filled NFR/SLO row.
5. **Stop** and present the plan to the user: context map, manifests, and the story graph. After explicit approval, append a `plan` row (Decision: `Approved`, approver, date, the context-map and manifest paths) to the `Delivery approvals` table of each manifest in scope. Do not start `/v0-intake` for any story without that approval.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11.
