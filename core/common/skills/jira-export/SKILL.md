---
name: jira-export
description: Regenerate tickets.csv from the approved backlog index and approved Intake artifacts. The CSV is a copy. Jira is not read back.
---

# jira-export

Documentation playbook for `/v0-export`. It does not record a delivery approval.

## Steps
1. Read `docs/agents-v0/backlog/export-params.md`. Project key and Issue type must be non-empty. When either is empty, ask once and wait for `yes` or an explicit override. Do not invent a project key.
2. Collect rows in manifest order. Skip a manifest when neither `program.state.json` nor the manifest records `plan` as approved. For each story row in a remaining `docs/agents-v0/milestones/*.md` that has a concrete feature path:
   - When that artifact has `intake` in `docs/agents-v0/requirements/<feature>.state.json` (`approvedPhases`) or an `Approved` Intake row, acceptance criteria are the Gherkin scenarios in the artifact.
   - Otherwise the acceptance criteria cell is the user-story sentence from the manifest.
3. Write `docs/agents-v0/backlog/tickets-sources.md` first. One bullet per source: the path and the approval date from `.state.json` (`phaseDates.<phase>` or `updatedAt` date) or its `Approved` row. Include `docs/agents-v0/backlog/export-params.md` with the date the user confirmed the fields, and record `Project key` there. That file has no `.state.json` and no `Approved` row.
4. Rewrite `docs/agents-v0/backlog/tickets.csv` in UTF-8 with this header row and no preamble:

   `Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact`

   The `Issue Type` cell is the confirmed Issue type from `export-params.md`. `Project key` is not a column. The preamble is omitted so a Jira import can take the file as-is. The stamp lives in `tickets-sources.md`.
5. Do not update a ticket in Jira. Do not treat the CSV as the source of a later Intake.

## Rule-compliance checklist
- [ ] Export params were confirmed before the CSV was written.
- [ ] Every exported manifest has `plan` approved in `program.state.json` or an `Approved` `plan` row. Acceptance criteria come from an approved Intake artifact when one exists, otherwise from the manifest sentence.
- [ ] `tickets-sources.md` names those paths and approval dates.
- [ ] Requirements, design, and `Delivery approvals` were not edited.
