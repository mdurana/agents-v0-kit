---
description: Program architecture before any backlog. C4 through operations, then the ARC pack. Stories are written later by /v0-plan.
---

# /v0-architecture

You are entering **program architecture** (`workflow-orchestration.mdc` Architecture). This command runs after an approved roadmap and before `/v0-plan`. It does not write stories or a feature OpenAPI draft.

## Prerequisite
An `Approved` `roadmap` row on `docs/agents-v0/roadmap/<program>.md`. When that row is missing, stop and ask for `/v0-roadmap <discovery-path>`. Read the discovery file only at the `Discovery:` path on that roadmap. On a brownfield repo, `docs/agents-v0/onboarding/report.md` must have an `Approved` `onboard` row. As-is text already in `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md` stays. Add the target sections beside it.

P0-A alone and a single named ticket skip this command. Maintain and Trivial never open it.

## Resume
Continue from the architecture files already on disk. Do not recreate a section that is already filled. Do not rewrite an Accepted ADR; supersede it (`sh .agents-v0/ci/check-adr.sh`). A program has no per-feature state file.

## Collision
This command writes shared files: `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`, and `docs/agents-v0/adr/`. Stop before editing one that `git status` already shows modified by a feature in flight.

## Instructions
1. Launch the `solution-architect` subagent. It follows `program-architecture`. Phase agents do not launch other agents, so this command launches the reviewer in step 3.
2. Write the pack in this order. A narrower request may stop after the named step. C4 stays technology-agnostic. The pattern ADR chooses the technology, with at least two options.
   - C4 Context and Container in `docs/agents-v0/architecture.md`.
   - Pattern ADR under `docs/agents-v0/adr/`, with a filled `Patterns considered` table and a `Pack:` line. The id is the stack the user named. A discovery `Stack preference:` is an input, not the binding. Write a complete pack under `.agents-v0/packs/<id>/` (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`) and a UI manifest for the `ui` id. An incomplete pack stops before `/v0-plan`. Bind it in step 5, after the `architecture` row is approved.
   - Platform topology in `docs/agents-v0/network.md`, including a `Target topology` diagram.
   - Services: `docs/agents-v0/design/system/context-map.md` (also the service map), then in `architecture.md` the data flow, the conceptual, logical, and physical data models, the state machine, failure domains and degradation, and MVP and future state. Sequence diagrams. A component plan per context under `docs/agents-v0/design/system/components/`, or `N/A: <reason>`.
   - Contracts: catalog shape and the deprecation rule. No feature `openapi.yaml`.
   - Operations: `docs/agents-v0/design/system/nfr-slo.md`, `docs/agents-v0/design/system/threat-model.md`, and `docs/agents-v0/design/system/ops-readiness.md`. SLO numbers live only in `nfr-slo.md`.
   - ARC: `docs/agents-v0/design/system/arc-record.md`. Name the discovery file and the pattern ADR. Do not copy them. Point SLO targets at `nfr-slo.md` and fill the structural fitness function table.
3. Run `sh .agents-v0/ci/check-architecture-pack.sh`, then launch the `design-reviewer` subagent on the pack. It writes `docs/agents-v0/design/system/architecture-review.md`. Route each Critical finding back to the `solution-architect`, then run the reviewer again.
4. Check the **Architecture gate**: every step above has a filled section or `N/A: <reason>`, C4 names no product technology, the Data flow diagram uses the C4 Container nodes, the ADR has two real options and a Status of Proposed or Accepted, and the ARC record has a recommendation plus a structural fitness function row. `sh .agents-v0/ci/check-architecture-pack.sh` and `sh .agents-v0/ci/check-adr.sh` pass, and `architecture-review.md` has no open Critical. An Accepted ADR is superseded, not rewritten, when the decision changes.
5. **Stop** and present the pack. After one explicit approval, set the pattern ADR's Status to `Accepted` when it is still `Proposed`, then record the `architecture` row on `docs/agents-v0/architecture.md`. Its Artifacts cell lists every file in the pack, including `docs/agents-v0/design/system/arc-record.md` and `docs/agents-v0/design/system/architecture-review.md`. Do not add an `arc` row. Then run `sh .agents-v0/scripts/activate-stack-pack.sh <pack>` with the ADR's `Pack:` value. Exit 2 means the profile already names another pack: stop. Do not start `/v0-plan` without the `architecture` row and a profile `Pack` cell that matches the ADR. CI runs `.agents-v0/ci/check-architecture-pack.sh --approved` through `.agents-v0/ci/check-milestone.sh`.

## Rules
`workflow-orchestration.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11.
