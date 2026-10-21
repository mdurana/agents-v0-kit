---
description: Sequence an approved discovery document into a now / next / later roadmap. The discovery file may live anywhere in the repository.
---

# /v0-roadmap

You are sequencing a program (`workflow-orchestration.mdc`). The human-in-the-loop discovery already happened outside the kit; its output is the only product input.

## Prerequisite
The user passes one repo-relative path to the discovery file, for example `/v0-roadmap docs/product/claims-discovery.md`. A run with no path stops and asks for one. On a brownfield repo, `docs/agents-v0/onboarding/state.json` must show `lastApprovedPhase: "onboard"`. Maintain, Trivial, and single named tickets skip this command.

## Resume
Copy `docs/agents-v0/roadmap/_template.md` to `docs/agents-v0/roadmap/<program>.md` when it is absent, then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status in_progress docs/agents-v0/roadmap/<program>.md`. Continue from `docs/agents-v0/roadmap/<program>.md` when it already records `Discovery:` as the path the user gave. Do not recreate it unless `--refresh` is passed or the discovery document changed.

## Instructions
1. Launch the `program-planner` subagent with the discovery path (skill: `program-roadmap`).
2. Verify the discovery document contains non-empty sections for: `Problem`, `Success metric`, `Options`, `Chosen option`, `In scope`, and `Out of scope` without unresolved placeholders (`TBD`, `TODO`, `<...>`). If any section is missing or incomplete, stop and ask the user to complete it in the discovery file.
3. Write `docs/agents-v0/roadmap/<program>.md` from `docs/agents-v0/roadmap/_template.md`:
   - Record `Discovery: <path>` and its sha256 hash.
   - Assign every `In scope` item under the chosen option to exactly one horizon (`Now`, `Next`, or `Later`) without inventing themes or splitting a single leaf item across horizons.
   - Copy `Out of scope` items and any `Stack preference:` line verbatim.
4. Write `docs/agents-v0/roadmap/<program>.phase-result.md` and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status awaiting_approval docs/agents-v0/roadmap/<program>.md`.
5. **Stop** and present the roadmap sequence to the user. After explicit user approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve roadmap docs/agents-v0/roadmap/<program>.md`. Do not start `/v0-architecture` or `/v0-plan` without that approval.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `architecture-and-diagrams.mdc`.
