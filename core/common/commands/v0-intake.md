---
description: Intake phase. Turn a Jira/Confluence/user spec into the requirements artifact with Gherkin acceptance criteria, NFRs, regulations, and structured state.
---

# /v0-intake

You are entering the **Intake** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
- If `<feature>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not start Intake or create `docs/agents-v0/requirements/<feature>.md` until the lowercase `<feature>` slug is named.
- Read `docs/agents-v0/project-profile.md` and `docs/agents-v0/lessons.md`.
- `guard-intake.sh check <feature> [--tier trivial|emergency|standard|major] [--reopen]` verifies the `<feature>` slug, rejects `p0-a*` (greenfield platform skeleton runs `/v0-scaffold`), routes `trivial` to `/v0-triage` and `emergency` to `/v0-maintain` before touching disk, verifies the integration branch, checks Sensei's external `onboard` / `plan` / `scaffold` approval records when applicable, and ensures `<feature>` is not already released or approved (unless `--reopen`).
- `guard-intake.sh start <feature> [--reopen]` verifies a clean working tree on the integration branch, seeds `docs/agents-v0/requirements/<feature>.md` if absent, and sets `docs/agents-v0/requirements/<feature>.state.json` to `in_progress`. Do not edit `docs/agents-v0/requirements/<feature>.state.json` directly; only the guard scripts write it.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-branch-guard --> <!-- kitfix-20261031-gate-commit --> The gate commit is step 7: after Sensei's explicit approval in his external terminal and branch authorisation in its own turn (Do not run the script in the same turn as the Intake approval), `guard-intake.sh commit <feature>` creates/attaches the `feature/<feature>` worktree and makes one commit `"<story>: intake approved"` on `feature/<feature>`, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-intake.sh steps (scripts/generate-intake-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-intake.sh check <feature> [--tier trivial|emergency|standard|major] [--reopen]`. It validates the `<feature>` slug, blocks `p0-a*` (redirecting to `/v0-scaffold`), routes `trivial` to `/v0-triage` and `emergency` to `/v0-maintain`, verifies the integration branch, checks Sensei's external `onboard`/`plan`/`scaffold` approvals when applicable, and ensures the story is not already released or approved. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-intake.sh start <feature> [--reopen]`. It verifies a clean working tree on the integration branch, seeds `docs/agents-v0/requirements/<feature>.md` if absent, and sets `docs/agents-v0/requirements/<feature>.state.json` to `in_progress`.
3. Read `docs/agents-v0/lessons.md` and launch the `requirements-analyst` subagent (skill: `spec-intake`) to author `docs/agents-v0/requirements/<feature>.md` (user story sentence, Gherkin `AC-1`..`AC-8` with `Kind: happy | negative | edge` and observable `Then` outcomes, security-review triggers, NFRs, regulations, and `Open questions: none`). It runs no shell commands and leaves `Delivery approvals` tables empty.
4. If `docs/agents-v0/requirements/<feature>.helper-brief.md` exists or the story requires `## Proposed split`, run `sh .agents-v0/scripts/guard-intake.sh block <feature> "<plain reason>"` (which deduplicates helper briefs and records `blocked`). If a helper brief was written, launch `explore-researcher`, pass findings back to `requirements-analyst`, remove the brief, and resume; if split or blocked on user input, stop.
5. When `docs/agents-v0/requirements/<feature>.md` is complete, run `sh .agents-v0/scripts/guard-intake.sh ready <feature>`. It validates the user story sentence, Gherkin acceptance criteria, negative/edge and security-trigger refusal rules, single-surface / vertical-slice budget, milestone size alignment, mandatory sections, and `Open questions: none`, writes `docs/agents-v0/requirements/<feature>.phase-result.md`, and sets state to `awaiting_approval`. When it prints `REFUSED`, fix what it names and run `ready` again.
6. Stop. Present the requirements summary to Sensei and wait for explicit approval. Next: Sensei reviews docs/agents-v0/requirements/<feature>.md and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve intake <feature>. Never run approve yourself; the agent cannot approve this gate.
7. After Sensei runs approve in his own terminal and authorises branch `feature/<feature>` in its own turn (Do not run the script in the same turn as the Intake approval), run `sh .agents-v0/scripts/guard-intake.sh commit <feature>`. It verifies Sensei's external approval record, appends the verified `Intake` row to `Delivery approvals`, creates or attaches the `feature/<feature>` worktree via `feature-worktree.sh`, moves untracked intake artifacts into the worktree, stages only the story's intake files, scans staged content for secrets, and commits `"<story>: intake approved"` on `feature/<feature>`. Then open the worktree and suggest: /v0-design <feature>.
<!-- END generated -->

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`, `frontend-web.mdc`, `security-baseline.mdc` §11.
