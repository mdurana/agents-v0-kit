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
1. Launch the `solution-architect` subagent. It follows `program-architecture`.
2. Write the pack in this order. A narrower request may stop after the named step. C4 stays technology-agnostic. The pattern ADR chooses the technology, with at least two options.
   - C4 Context and Container in `docs/agents-v0/architecture.md`.
   - Pattern ADR under `docs/agents-v0/adr/`.
   - Platform topology in `docs/agents-v0/network.md`.
   - Services: `docs/agents-v0/design/system/context-map.md`, data, integration, sequence diagrams.
   - Contracts: catalog shape. No feature `openapi.yaml`.
   - Operations: `docs/agents-v0/design/system/nfr-slo.md` and `docs/agents-v0/design/system/threat-model.md`. SLO numbers live only in `nfr-slo.md`.
   - ARC: `docs/agents-v0/design/system/arc-record.md`. Name the discovery file and the pattern ADR. Do not copy them. Point fitness functions at `nfr-slo.md`.
3. Check the **Architecture gate**: every step above has a filled section, C4 names no product technology, the ADR has two real options and a Status of Proposed or Accepted, and the ARC record has a recommendation plus a Fitness functions section. `sh .agents-v0/ci/check-adr.sh` passes. An Accepted ADR is superseded, not rewritten, when the decision changes.
4. **Stop** and present the pack. After one explicit approval, set the pattern ADR's Status to `Accepted` when it is still `Proposed`, then record the `architecture` row on `docs/agents-v0/architecture.md`. Its Artifacts cell lists every file in the pack, including `docs/agents-v0/design/system/arc-record.md`. Do not add an `arc` row. Do not start `/v0-plan` without the `architecture` row.

## Rules
`workflow-orchestration.mdc`, `architecture-and-diagrams.mdc`, `project-delivery-core.mdc`, `security-baseline.mdc` §11.
