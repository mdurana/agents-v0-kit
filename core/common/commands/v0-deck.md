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

A run missing the kind (`intake`, `product`, or `delivery`), the audience (`Technical`, `Non-technical`, or `Mixed`), or the decision stops and asks for those arguments. An `intake` deck also stops when the feature slug is missing. Do not write the deck. Do not interview for a problem statement. Do not invent a mission statement.

## Instructions
Subagents: `docs-author` (`shell: false`) — Skill: `leadership-deck`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-deck.sh steps (scripts/generate-deck-steps.sh); do not edit -->
1. **Pre-flight check & source-approval validation** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh check <kind> [<feature>] <audience> <decision>
   ```
   Wait for exit `0` (`OK check: ...` + JSON manifest of `kind`, `audience`, `decision`, `deckPath`, `paramsPath`, and `sources`). When `<kind>`, `<feature>` (for `intake`), `<audience>` (`Technical`, `Non-technical`, or `Mixed`), or `<decision>` is missing or any required source is not yet approved in `.state.json` (or legacy `Approved` row), stop and report the refusal verbatim.
2. **Draft deck and `.params.md`** — launch the shell-less **`docs-author`** subagent (`core/common/agents/docs-author.md`, `shell: false`) with skill `leadership-deck` (`core/common/skills/leadership-deck/SKILL.md`) and the JSON manifest from Step 1. `docs-author` writes only `docs/agents-v0/presentations/<stem>.md` and `docs/agents-v0/presentations/<stem>.params.md`, copying figures, dates, and scenario text strictly from the admitted sources. Do not edit any source or `.state.json` files.
3. **Verify deck, provenance params, & read-only source tree** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh verify <kind> [<feature>]
   ```
   Wait for exit `0` (`OK verify: ...`). Confirms `<stem>.md` and `<stem>.params.md` exist, `Kind:`, `Audience:`, `Decision:`, and `## Sources` in `<stem>.params.md` cite only approved sources, and `git status --porcelain -uall` shows zero modifications outside `docs/agents-v0/presentations/`.
4. **Safe-staged commit** — run:
   ```sh
   sh .agents-v0/scripts/guard-deck.sh commit <kind> [<feature>]
   ```
   Stages only `docs/agents-v0/presentations/<stem>.md` and `docs/agents-v0/presentations/<stem>.params.md`, scans staged content for secrets, and commits `v0(deck): write <stem> briefing`.
<!-- END generated -->

### Source & Provenance Rules
- **Intake** source is `docs/agents-v0/requirements/<feature>.md` with `intake` in `docs/agents-v0/requirements/<feature>.state.json` (`approvedPhases`) or an `Approved` `intake` row. Refuse when neither is present. When the file sets `Milestone file:`, that manifest must contain the `Story:` id and have `plan` approved in `docs/agents-v0/program.state.json` or an `Approved` `plan` row. Refuse when that line is set and either is missing.
- **Product** sources, each of which must be approved in `docs/agents-v0/program.state.json` (`approvedPhases`) / `<feature>.state.json` or carry an `Approved` row except the discovery file and an ARC record covered by the architecture approval: the roadmap (`roadmap`), `docs/agents-v0/design/system/context-map.md` (admitted when `plan` or `architecture` is approved in `program.state.json` or cited on an `Approved` `plan` row), `docs/agents-v0/design/system/arc-record.md` when that file exists (`architecture` in `program.state.json`, an `Approved` `arc` row, or an `Approved` `architecture` row in `docs/agents-v0/architecture.md` that names the file), and every `docs/agents-v0/requirements/*.md` that has `intake` approved in `<feature>.state.json` or an `Approved` `intake` row. The discovery file is read only at the `Discovery:` path recorded on the approved roadmap. It has no approval row. Skip a requirements file with no Intake approval.
- **Delivery** sources are the product sources plus the milestone manifests and the release evidence for stories with `release` in `<feature>.state.json` (`approvedPhases`) or named on `Approved` `release` rows. That evidence is `artifacts.verify`, `artifacts.buildReport`, and `docs/agents-v0/requirements/<feature>.phase-result.md`. There is no `artifacts.release` key. Skip a story whose release is not approved.
- Intake writes `docs/agents-v0/presentations/<feature>-intake.md` and `docs/agents-v0/presentations/<feature>-intake.params.md`. Product and delivery write `docs/agents-v0/presentations/<roadmap-stem>.md` or `<roadmap-stem>-delivery.md`, and the matching params file. The deck states no number that is not already in those sources. For `Non-technical`, copy scenario names only. For `Technical` and `Mixed`, also copy `Kind:` and the `Then` line.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`.
