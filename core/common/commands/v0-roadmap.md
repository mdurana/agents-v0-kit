---
description: Sequence an approved discovery document into a now / next / later roadmap. The discovery file may live anywhere in the repository.
---

# /v0-roadmap

You are sequencing a program (`workflow-orchestration.mdc`). The human-in-the-loop discovery already happened outside the kit; its output is the only product input.

## Prerequisite
The user passes one repo-relative path to the discovery file, for example `/v0-roadmap docs/product/claims-discovery.md`. A run with no path stops and asks for one. Do not set `in_progress`. If `docs/agents-v0/onboarding/state.json` exists and `onboard` is not approved, stop and suggest `/v0-onboard`. A single named ticket stops and suggests `/v0-intake`. P0-A stops and suggests `/v0-build`. A docs-only edit or a 1-for-1 patch bump stops and suggests `/v0-triage`. Any other fix stops and suggests `/v0-maintain`. If `docs/agents-v0/program.state.json` already has `roadmap` in `approvedPhases`, stop and suggest `/v0-architecture`. Do not set `in_progress`.

## Resume
Validate the discovery file (step 2) before copying a roadmap or setting `in_progress`. When it passes, copy `docs/agents-v0/roadmap/_template.md` to `docs/agents-v0/roadmap/<program>.md` if that file is absent, then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status in_progress docs/agents-v0/roadmap/<program>.md`. Continue from `docs/agents-v0/roadmap/<program>.md` when it already records `Discovery:` as the path the user gave. Do not recreate it unless `--refresh` is passed or the discovery document changed. If step 2 fails and the roadmap file already exists, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status blocked --reason "<missing section or placeholder>" docs/agents-v0/roadmap/<program>.md` and stop.

## Instructions
1. Launch the `program-planner` subagent with the discovery path (skill: `program-roadmap`).
2. Verify the discovery document contains non-empty sections for: `Problem`, `Success metric`, `Options`, `Chosen option`, `In scope`, and `Out of scope` without unresolved placeholders (`<...>`, `[...]`, `TBD`, `TODO`, `FIXME`, `XX`/`XXX`, `__`, `???`). If any section is missing or incomplete, stop and ask the user to complete it in the discovery file. When the roadmap file already exists, record `--status blocked` as in Resume.
3. Write `docs/agents-v0/roadmap/<program>.md` from `docs/agents-v0/roadmap/_template.md`:
   - Record `Discovery: <path>` and its sha256 hash.
   - Assign every `In scope` item under the chosen option to exactly one horizon (`Now`, `Next`, or `Later`) without inventing themes or splitting a single leaf item across horizons.
   - Copy `Out of scope` items and any `Stack preference:` line verbatim.
4. Write `docs/agents-v0/roadmap/<program>.phase-result.md` and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase roadmap --status awaiting_approval docs/agents-v0/roadmap/<program>.md`.
5. **Stop** and present the roadmap sequence to the user. After explicit user approval, append the `roadmap` row to `Delivery approvals` (this file and the discovery path, Decision `Approved`), then run `sh .agents-v0/scripts/sync-feature-state.sh --approve roadmap docs/agents-v0/roadmap/<program>.md`. The next command is `/v0-architecture`. Do not start `/v0-architecture` or `/v0-plan` without that approval.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `architecture-and-diagrams.mdc`.
