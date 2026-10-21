---
description: Write a markdown deck from an approved Intake artifact, or from approved program or delivery records. The user supplies the audience and the decision the meeting must take. Documentation only.
---

# /v0-deck

Documentation command (`workflow-orchestration.mdc` Lifecycle). Not a delivery phase. `/v0-deliver` does not run it. A missing deck does not block Build or Release. `/v0-status` does not report it.

## Prerequisite
The user names the kind and the decision the meeting must answer, in the user's words. Audience is `Technical`, `Non-technical`, or `Mixed`.

- `/v0-deck intake <feature> <audience> <decision>`
- `/v0-deck product <audience> <decision>`
- `/v0-deck delivery <audience> <decision>`

A run missing the audience (`Technical`, `Non-technical`, or `Mixed`) or the decision stops and asks for those arguments. Do not write the deck. Do not interview for a problem statement. Do not invent a mission statement.

## Instructions
1. Follow `leadership-deck`.
2. **Intake** source is `docs/agents-v0/requirements/<feature>.md` with `intake` in `docs/agents-v0/requirements/<feature>.state.json` (`approvedPhases`) or an `Approved` `intake` row. Refuse when neither is present. When the file sets `Milestone file:`, that manifest must contain the `Story:` id and have `plan` approved in `docs/agents-v0/program.state.json` or an `Approved` `plan` row. Refuse when that line is set and either is missing.
3. **Product** sources, each of which must be approved in `docs/agents-v0/program.state.json` (`approvedPhases`) / `<feature>.state.json` or carry an `Approved` row except the discovery file and an ARC record covered by the architecture approval: the roadmap (`roadmap`), `docs/agents-v0/design/system/context-map.md` (admitted when `plan` or `architecture` is approved in `program.state.json` or cited on an `Approved` `plan` row), `docs/agents-v0/design/system/arc-record.md` when that file exists (`architecture` in `program.state.json`, an `Approved` `arc` row, or an `Approved` `architecture` row in `docs/agents-v0/architecture.md` that names the file), and every `docs/agents-v0/requirements/*.md` that has `intake` approved in `<feature>.state.json` or an `Approved` `intake` row. The discovery file is read only at the `Discovery:` path recorded on the approved roadmap. It has no approval row. Skip a requirements file with no Intake approval.
4. **Delivery** sources are the product sources plus the milestone manifests and the release evidence for stories with `release` in `<feature>.state.json` (`approvedPhases`) or named on `Approved` `release` rows. That evidence is `artifacts.verify`, `artifacts.buildReport`, and `docs/agents-v0/requirements/<feature>.phase-result.md`. There is no `artifacts.release` key. Skip a story whose release is not approved.
5. Write the deck and its params file. Intake writes `docs/agents-v0/presentations/<feature>-intake.md` and `docs/agents-v0/presentations/<feature>-intake.params.md`. Product and delivery write `docs/agents-v0/presentations/<roadmap-stem>.md` or `<roadmap-stem>-delivery.md`, and the matching params file. The deck states no number that is not already in those sources. For `Non-technical`, copy scenario names only. For `Technical` and `Mixed`, also copy `Kind:` and the `Then` line. The params file records the audience, the decision, each source path, and the date from that source's `.state.json` (`phaseDates.<phase>`, or `updatedAt` date) or `Approved` row (the discovery path is stamped with the roadmap approval date; a requirements path is stamped with its Intake approval date; the ARC path is stamped with the `arc` or `architecture` approval date).
6. Stop. Do not add an `Approved` row. Do not edit the discovery file, the roadmap, requirements, design, or any approvals table.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`.
