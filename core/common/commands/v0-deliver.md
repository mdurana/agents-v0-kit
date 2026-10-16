---
description: Run one story through the lifecycle by following each phase command in order, stopping at every gate for explicit user approval; resumes from the state file.
---

# /v0-deliver

Run **one story** through **Intake → Design → Build → Verify → Release** by following each phase command in order. `/v0-local-release` is optional after Verify and is not required before `/v0-release`. `/v0-deliver` holds no phase detail of its own: every prerequisite, resume rule, collision check, helper step, mechanical check, gate, and approval record lives in `/v0-intake`, `/v0-design`, `/v0-build`, `/v0-verify`, and `/v0-release`. A new program of more than one story starts with `/v0-roadmap`, then `/v0-architecture`, then `/v0-plan`. `/v0-deliver` then runs one story of the approved manifest, in dependency order. `/v0-export` and `/v0-deck` are not steps in this pipeline.

## Start or resume
1. Name the feature (the slug of `docs/agents-v0/requirements/<feature>.md`) and, for a new one, the source spec (Jira, Confluence, or a description). Ask when either is missing. Do not guess the feature from the newest state file.
2. If `docs/agents-v0/requirements/<feature>.state.json` exists, read it as `/v0-status` does. `in_progress` or `blocked`: run that same phase command again. `awaiting_approval`: ask for the approval and stop. No active phase: run the command after `lastApprovedPhase`. With no artifact yet, start `/v0-build` when the story is P0-A. A named ticket, or a milestone that already has an `Approved` `plan` row, starts `/v0-intake`. Skip list: `workflow-orchestration.mdc` Architecture. Otherwise route by tier and start `/v0-intake`.
3. Before the first phase, check what the phase commands would otherwise only find late: a brownfield repo has an `Approved` `onboard` row (`/v0-onboard`); a story from a milestone manifest has every dependency story Verify-approved; no other feature's code or shared-file edit is in the working tree. Report the first unmet prerequisite and stop.

## Tier routing
- **Trivial** — use `/v0-triage`, then `/v0-maintain` with the abbreviated Verify.
- **Major** — the full pipeline; Design includes `system-design`, threat-model notes, and the ARC pack when `Material: yes`; use the milestone manifest when applicable.
- **Standard** — the pipeline below.

## Pipeline
| Step | Command | Stops at |
|------|---------|----------|
| 1 | `/v0-intake` | Intake gate |
| 2 | `/v0-design` (contract or N/A, `design.md`, mechanical checks, `design-reviewer` when there is a contract, a UI, or a public route, pin) | Design gate |
| 3 | `/v0-build` | Build gate |
| 4 | `/v0-verify` | Verify gate |
| 5 | `/v0-release` | merge-request readiness, then the human merge |

- **STOP at every gate.** Present the gate result and wait for the user's explicit approval. Do not auto-advance. An `in_progress` or `blocked` state resumes that phase; it does not approve it. **P0-A** skips `/v0-intake` and `/v0-design`. `/v0-build` copies the milestone story and AC-1 through AC-4, writes the N/A design, and pins it. Do not stop at Build or Verify. Stop once at Release. That one approval writes the five rows. Optional `/v0-local-release` after Verify writes Intake, Design, Build, and Verify instead; Release then writes only the Release row. A later story with `N/A: no /api/v1 operation`, no UX spec, and no public route does not stop at Design: pin and continue, and the Build approval writes the Design row.
- **Known helpers launch in the same turn.** When Design needs a contract, launch `schema-author` with `solution-architect`, not after the architect returns a brief. A helper brief is only for work that appears mid-phase (a second red test, or doc-sync).
- **Before each transition**, verify the previous handoff artifact exists, its evidence is named and the recorded evidence paths exist on disk, and its `Delivery approvals` section records the explicit phase approval. If that evidence is absent, stop and report the missing prerequisite; never infer approval from a prior chat message or a passing command. P0-A starts at Build. Build creates the requirements file and the lock, and Release writes the rows. Optional `/v0-local-release` may write Intake, Design, Build, and Verify first. A no-contract story enters Build with a lock and no Design row; the Build approval writes that row.
- **After each approval**, the phase command records the row and runs `sh .agents-v0/scripts/sync-feature-state.sh`. Two named stories may share one Intake or Design approval only as `workflow-orchestration.mdc` Batch approval allows.
- **A Critical finding** at Verify routes back to Build (or `/v0-maintain` for a defect in released code), then re-enters Verify. The phase being re-run is reopened: set its Decision to `Re-opened` (not a positive token, so CI and the state file show it is open), and set `Approved` with the new date only after the user approves again. Code changed since a report's `commit:` makes that report stale. `/v0-verify` sets an Approved Verify row to `Re-opened` and stamps the new SHA. A same-commit re-entry keeps the test report and writes only a missing reviewer report.
- **A flaw in the approved design** found in Build or Verify is an amendment (`/v0-design` Amending an approved design), not an in-place edit.

## Who runs it
Prefer launching the `orchestrator` subagent, which follows this file. If subagents cannot launch subagents in your session, the main session runs the phases and launches every agent and helper itself, following the same commands. Helpers always run from the main session, never from a phase agent (`workflow-orchestration.mdc` Helper agents).

## After release
Fixes, patches, upgrades, and hotfixes use `/v0-maintain` (or `/v0-triage`): each has its own maintenance note and approvals, and routes to Verify.

## Conduct
Per `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report at each phase. No commits or force-push without explicit user approval. Follow `workflow-orchestration.mdc`, including Phase resume and Parallel features.
