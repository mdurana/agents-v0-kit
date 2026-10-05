---
name: jira-export
description: Regenerate tickets.csv from the approved backlog index and approved Intake artifacts. The CSV is a copy. Jira is not read back.
---

# jira-export

Documentation playbook for `/v0-export`. It does not record a delivery approval.

## Steps
1. Read `docs/agents-v0/backlog/export-params.md`. Project key and Issue type must be non-empty. When either is empty, ask once and wait for `yes` or an explicit override. Do not invent a project key.
2. Collect rows in manifest order. For each story row in `docs/agents-v0/milestones/*.md` that has a concrete feature path:
   - When that artifact has an `Approved` Intake row, acceptance criteria are the Gherkin scenarios in the artifact.
   - Otherwise the acceptance criteria cell is the user-story sentence from the manifest, and only when the manifest has an `Approved` `plan` row.
   - Skip a manifest with no `Approved` `plan` row.
3. Write `docs/agents-v0/backlog/tickets-sources.md` first. One bullet per source: the path and the date from its `Approved` row. Include the export-params file.
4. Rewrite `docs/agents-v0/backlog/tickets.csv` in UTF-8 with this header row and no preamble:

   `Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact`

   The preamble is omitted so a Jira import can take the file as-is. The stamp lives in `tickets-sources.md`.
5. Do not update a ticket in Jira. Do not treat the CSV as the source of a later Intake.

## Rule-compliance checklist
- [ ] Export params were confirmed before the CSV was written.
- [ ] Every exported story comes from an approved plan row, or from an approved Intake artifact.
- [ ] `tickets-sources.md` names those paths and approval dates.
- [ ] Requirements, design, and `Delivery approvals` were not edited.
