---
description: Program architecture before any backlog. C4 through operations, then the ARC pack. Stories are written later by /v0-plan.
---

# /v0-architecture

You are entering **program architecture** (`workflow-orchestration.mdc`). This command runs after an approved roadmap and before `/v0-plan`. It does not write stories or a feature OpenAPI draft.

## Prerequisite
`docs/agents-v0/program.state.json` must record `roadmap` in `approvedPhases` (or an `Approved` `roadmap` row in `docs/agents-v0/roadmap/<program>.md`). On a brownfield repo, `onboard` must also be approved. P0-A alone and single named tickets skip this command.

## Resume
Continue from the architecture files already on disk. Do not recreate filled sections. Do not rewrite an `Accepted` ADR; supersede it with a new ADR when a decision changes.

## Collision
This command writes shared files (`docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`, `docs/agents-v0/adr/`). Stop before editing if `git status` shows uncommitted changes from a feature in flight.

## Instructions
1. Launch the `solution-architect` subagent (skill: `program-architecture`).
2. Author the architecture pack in order:
   - **C4 Context and Container** in `docs/agents-v0/architecture.md` (technology-agnostic C4 labels).
   - **Pattern ADR** under `docs/agents-v0/adr/` comparing at least two candidate architectures across cost, security, reliability, and operability, and recording `Pack: <id>` (`java`, `dotnet`, `node`, `python`, `go`, etc.). Ensure `.agents-v0/packs/<id>/` is complete (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, plus UI manifest when `ui` is set).
   - **Platform topology** in `docs/agents-v0/network.md` with zones, protocol-labelled edges, and security boundaries.
   - **Services & Data:** `docs/agents-v0/design/system/context-map.md` and per-context `components/<service>.md`, plus data flow, conceptual/logical/physical `erDiagram` models, state machine, failure domains, and MVP vs. future state in `architecture.md`.
   - **Operations & Governance:** `docs/agents-v0/design/system/nfr-slo.md`, `threat-model.md`, `ops-readiness.md`, and `arc-record.md` (with structural fitness functions).
3. Launch the `design-reviewer` subagent on the architecture pack to write `docs/agents-v0/design/system/architecture-review.md`. Route any `Critical` findings back to `solution-architect` to resolve, and re-run `design-reviewer` until zero `Open` Critical findings remain (max 3 review cycles before escalating to the user).
4. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase architecture --status awaiting_approval docs/agents-v0/architecture.md`.
5. **Stop** and present the architecture pack and `architecture-review.md` to the user. After explicit user approval:
   - Set the pattern ADR `Status` to `Accepted`.
   - Run `sh .agents-v0/scripts/activate-stack-pack.sh <pack>` with the ADR's `Pack:` id to bind the stack pack into `docs/agents-v0/project-profile.md` and `.cursor/`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --approve architecture docs/agents-v0/architecture.md`.

## Rules
`workflow-orchestration.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11.
