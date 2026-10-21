---
description: Regenerate a Jira CSV from the approved plan index and approved Intake artifacts. Documentation only. It does not approve anything and it does not read Jira.
---

# /v0-export

Documentation command (`workflow-orchestration.mdc` Lifecycle). Not a delivery phase. `/v0-deliver` does not run it. A missing CSV does not block Build or Release. `/v0-status` does not report it.

## Prerequisite
`plan` is approved in `docs/agents-v0/program.state.json` (`approvedPhases`) or via an `Approved` `plan` row on the milestone manifest being exported. Stories with `intake` approved in `docs/agents-v0/requirements/<feature>.state.json` (or an `Approved` Intake row) export their Gherkin. Stories that only have a sentence in the manifest export that sentence. Do not read Jira. Do not edit requirements, design, approvals, or the discovery file.

## Instructions
1. Follow `jira-export`.
2. Ask for the export fields when `docs/agents-v0/backlog/export-params.md` has an empty Project key or Issue type. Write the CSV only after the user confirms those fields (`yes` or an explicit override list).
3. Write `docs/agents-v0/backlog/tickets-sources.md` first. One line per source path and the date from its `.state.json` (`phaseDates.<phase>` or `updatedAt`) or `Approved` row. Include `docs/agents-v0/backlog/export-params.md` with the date the user confirmed the fields, and record `Project key` there. Then regenerate the whole of `docs/agents-v0/backlog/tickets.csv`. The `Issue Type` column is the confirmed Issue type. `Project key` is not a CSV column.
4. Stop. Do not add an `Approved` row. Tell the user the CSV is a copy for a manual Jira import. An edit in Jira is made again by editing the requirements file or the manifest, then running this command again.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`.
