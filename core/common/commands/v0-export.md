---
description: Regenerate a Jira CSV from the approved plan index and approved Intake artifacts. Documentation only. It does not approve anything and it does not read Jira.
---

# /v0-export

Documentation command (`workflow-orchestration.mdc` Lifecycle). Not a delivery phase. `/v0-deliver` does not run it. A missing CSV does not block Build or Release. `/v0-status` does not report it.

## Prerequisite
This command writes every approved milestone manifest under `docs/agents-v0/milestones/`. It does not take a manifest argument. If `plan` is not approved in `docs/agents-v0/program.state.json` (`approvedPhases`) and no manifest there has an `Approved` `plan` row, stop and suggest `/v0-plan`. Do not write the CSV. Stories with `intake` approved in `docs/agents-v0/requirements/<feature>.state.json` (or an `Approved` Intake row) export their Gherkin. Stories that only have a sentence in the manifest export that sentence. Do not read Jira. Do not edit requirements, design, approvals, or the discovery file.

## Instructions
Subagents: `docs-author` (`shell: false`) — Skill: `jira-export`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-export.sh steps (scripts/generate-export-steps.sh); do not edit -->
1. **Pre-flight check & source discovery** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh check
   ```
   Wait for exit `0` (`OK check: ...` + JSON manifest of `projectKey`, `issueType`, `approvedManifests`, and `approvedRequirements`). If it exits `1` because `Project key` or `Issue type` in `docs/agents-v0/backlog/export-params.md` is empty, ask the user once in chat (`yes` or explicit values), update `docs/agents-v0/backlog/export-params.md`, and re-run `check`. If no approved plan manifest exists, stop and direct the user to `/v0-plan`.
2. **Draft `tickets-sources.md` and `tickets.csv`** — launch the shell-less **`docs-author`** subagent (`core/common/agents/docs-author.md`, `shell: false`) with skill `jira-export` (`core/common/skills/jira-export/SKILL.md`) and the JSON manifest from Step 1. `docs-author` writes only `docs/agents-v0/backlog/tickets-sources.md` and `docs/agents-v0/backlog/tickets.csv` (with exact header `Issue Type,Parent ID,Summary,Description,Acceptance Criteria,Priority,Story ID,Surface,Size,Milestone,Feature artifact` and no preamble). Do not edit any requirements, design, milestone, or `.state.json` files.
3. **Verify outputs & read-only source tree** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh verify
   ```
   Wait for exit `0` (`OK verify: ...`). Confirms the 11-column CSV header, verifies every path cited in `tickets-sources.md` is approved, and verifies `git status --porcelain -uall` shows zero modifications outside `docs/agents-v0/backlog/`.
4. **Safe-staged commit** — run:
   ```sh
   sh .agents-v0/scripts/guard-export.sh commit
   ```
   Stages only `docs/agents-v0/backlog/export-params.md`, `docs/agents-v0/backlog/tickets-sources.md`, and `docs/agents-v0/backlog/tickets.csv`, scans staged content for secrets, and commits `v0(export): regenerate tickets.csv`.
<!-- END generated -->

Tell the user the CSV is a copy for a manual Jira import. An edit in Jira is made again by editing the requirements file or the manifest, then running this command again.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`.
