---
name: jira-export
description: Regenerate tickets.csv from the approved backlog index and approved Intake artifacts. The CSV is a copy. Jira is not read back.
---

# jira-export

Documentation playbook for `/v0-export`, executed by the shell-less **`docs-author`** subagent (`core/common/agents/docs-author.md`, `shell: false`) after the main session runs `sh .agents-v0/scripts/guard-export.sh check`. It does not record a delivery approval.

## Steps
1. Read `docs/agents-v0/backlog/export-params.md` and the JSON manifest emitted by `sh .agents-v0/scripts/guard-export.sh check` (`projectKey`, `issueType`, `approvedManifests`, `approvedRequirements`). Project key and Issue type must be non-empty. When either is empty, the main session asks once and waits for `yes` or an explicit override before launching `docs-author`. Do not invent a project key.
2. Collect rows in manifest order across `approvedManifests`. Skip a manifest when neither `program.state.json` nor the manifest records `plan` as approved. For each story row in a remaining `docs/agents-v0/milestones/*.md` that has a concrete feature path:
   - When that artifact is in `approvedRequirements` (`intake` in `docs/agents-v0/requirements/<feature>.state.json` `approvedPhases` or an `Approved` Intake row), acceptance criteria are the Gherkin scenarios in the artifact.
   - Otherwise the acceptance criteria cell is the user-story sentence from the manifest.
3. Write `docs/agents-v0/backlog/tickets-sources.md` first. One row/bullet per source: the path and the approval date from `.state.json` (`phaseDates.<phase>` or `updatedAt` date) or its `Approved` row. Include `docs/agents-v0/backlog/export-params.md` with the date the user confirmed the fields, and record `Project key` there. That file has no `.state.json` and no `Approved` row.
4. Rewrite `docs/agents-v0/backlog/tickets.csv` in UTF-8 with this header row and no preamble:

   `Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact`

   The `Issue Type` cell is the confirmed Issue type from `export-params.md`. `Project key` is not a column. The preamble is omitted so a Jira import can take the file as-is. The stamp lives in `tickets-sources.md`.
5. Do not update a ticket in Jira. Do not treat the CSV as the source of a later Intake. After `docs-author` returns, the main session runs `sh .agents-v0/scripts/guard-export.sh verify` and `sh .agents-v0/scripts/guard-export.sh commit`.

## Rule-compliance checklist
- [ ] Export params were confirmed and verified by `guard-export.sh check` before the CSV was written.
- [ ] Every exported manifest has `plan` approved in `program.state.json` or an `Approved` `plan` row. Acceptance criteria come from an approved Intake artifact when one exists, otherwise from the manifest sentence.
- [ ] `tickets-sources.md` names those paths and approval dates.
- [ ] Requirements, design, and `Delivery approvals` were not edited (`guard-export.sh verify` enforces read-only tree outside `docs/agents-v0/backlog/`).
