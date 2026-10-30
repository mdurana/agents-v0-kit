---
description: Program architecture before any backlog. C4 through operations, then the ARC pack. Stories are written later by /v0-plan.
---

# /v0-architecture

You are entering **program architecture** (`workflow-orchestration.mdc`). This command runs after an approved roadmap and before `/v0-plan`. It does not write stories or a feature OpenAPI draft.

## Prerequisite
If `roadmap` is not in `approvedPhases` in `docs/agents-v0/program.state.json` and `docs/agents-v0/roadmap/<program>.md` has no `Approved` `roadmap` row, stop and suggest `/v0-roadmap`. Do not set `in_progress`. If `docs/agents-v0/onboarding/state.json` exists and `onboard` is not approved, stop and suggest `/v0-onboard`. A Major story with no roadmap stops and suggests `/v0-design` (`system-design`). A single named ticket stops and suggests `/v0-intake`. P0-A stops and suggests `/v0-build`. A docs-only edit or a 1-for-1 patch bump stops and suggests `/v0-triage`. Any other fix stops and suggests `/v0-maintain`. If `architecture` is already in `approvedPhases`, stop and suggest `/v0-plan`. Do not set `in_progress`.

## Resume
Only after the prerequisite passes, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase architecture --status in_progress docs/agents-v0/architecture.md`. Continue from the architecture files already on disk. Do not recreate filled sections. Do not rewrite an `Accepted` ADR; supersede it with a new ADR when a decision changes.

## Collision
This command writes shared files (`docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`, `docs/agents-v0/adr/`). Stop before editing if `git status` shows uncommitted changes from a feature in flight.

## Instructions
1. Launch the `solution-architect` subagent (skill: `program-architecture`).
2. Author the architecture pack in order:
   - **C4 Context and Container** in `docs/agents-v0/architecture.md` (technology-agnostic C4 labels).
   - **Pattern ADR** under `docs/agents-v0/adr/` comparing at least two candidate architectures across cost, security, reliability, and operability, and recording `Pack: <id>` (`java`, `dotnet`, `node`, `python`, `go`, etc.). On a brownfield repo where `/v0-onboard` already set the `Pack` cell in `docs/agents-v0/project-profile.md`, keep that pack id and do not replace it. Ensure `.agents-v0/packs/<id>/` is complete (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, plus UI manifest when `ui` is set).
   - **Platform topology** in `docs/agents-v0/network.md` with zones, protocol-labelled edges, and security boundaries.
   - **Services & Data:** `docs/agents-v0/design/system/context-map.md` and per-context `components/<service>.md`, plus data flow, conceptual/logical/physical `erDiagram` models, state machine, failure domains, and MVP vs. future state in `architecture.md`.
   - **Operations & Governance:** `docs/agents-v0/design/system/nfr-slo.md`, `threat-model.md`, `ops-readiness.md`, and `arc-record.md` (with structural fitness functions).
3. Launch the `design-reviewer` subagent on the architecture pack to write `docs/agents-v0/design/system/architecture-review.md`. Route any `Open` findings back to `solution-architect` to fix or disposition (`Resolved`, `Deferred`, or `Accepted`), and re-run `design-reviewer` until zero `Open` findings remain in `architecture-review.md` (max 3 review cycles, prompt-only, before escalating to the user).
4. Write `docs/agents-v0/architecture.phase-result.md` and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase architecture --status awaiting_approval docs/agents-v0/architecture.md`.
5. **Stop** and present the architecture pack and `architecture-review.md` to the user. After explicit user approval:
   - Set the pattern ADR `Status` to `Accepted`, record `Deciders` with the approver(s), update any `(Proposed)` ADR label in component plans, and update any narrative sentence in `architecture-review.md` that still calls the ADR `Proposed` to `Accepted`.
   - Append the `architecture` row on `docs/agents-v0/architecture.md` naming every pack path (including `arc-record.md` and `architecture-review.md`), then run `sh .agents-v0/scripts/sync-feature-state.sh --approve architecture docs/agents-v0/architecture.md`.
   - Run `sh .agents-v0/scripts/activate-stack-pack.sh <pack>` with the ADR's `Pack:` id to bind the stack pack into `docs/agents-v0/project-profile.md` and `.cursor/`. Exit 2 means `project-profile.md` already names another pack: stop and do not replace it, and do not start `/v0-plan` until the profile `Pack` cell matches the ADR.
   - <!-- kitfix-20261031-gate-commit --> After `activate-stack-pack.sh`, commit this gate on the integration branch, one commit, and tag it: `git add -A && git commit -m "program: architecture approved" && git tag -a architecture-v1 -m "architecture approved"` (the script prints it). Never `--amend`; a revision after a reopen is a new commit and the next tag (`architecture-v2`). The next phase refuses to start while this gate is uncommitted. Never commit secrets (`.env`, keys): `check-gate-commit.sh` names them.

## Rules
`workflow-orchestration.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11.
