---
description: Run one story through the lifecycle by following each phase command in order, stopping at every gate for explicit user approval; resumes from the state file.
---

# /v0-deliver

Run **one story** through **Intake → Design → Build → Verify → Local Release (`/v0-local-release`)** by following each phase command in order. `/v0-deliver` holds no phase detail of its own: every prerequisite, resume rule, collision check, helper step, skill invocation, and approval update lives in `/v0-intake`, `/v0-design`, `/v0-build`, `/v0-verify`, and `/v0-local-release`. A new program of more than one story starts with `/v0-roadmap`, then `/v0-architecture`, then `/v0-plan`, then `/v0-scaffold` for greenfield platform skeleton. `/v0-deliver` then runs one story of the approved manifest in dependency order. `/v0-export` and `/v0-deck` are not steps in this pipeline.

## Start or resume
1. Name the feature (the slug of `docs/agents-v0/requirements/<feature>.md`) and, for a new one, the source spec (Jira, Confluence, or a description). When the slug is missing, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. One open story resumes. A new story still needs a slug and a source spec; ask when either is missing. Do not pick the newest state file. Do not create the requirements file until the user has named the slug.
2. If `docs/agents-v0/requirements/<feature>.state.json` exists, read it as `/v0-status` does. If `release` is in `approvedPhases`, stop. Do not reopen the story. A fix or a small change starts at `/v0-maintain`. A new feature starts at `/v0-intake` with a new slug. Otherwise:
   - `activeStatus` is `in_progress` or `blocked`: run `activePhase` again.
   - `activeStatus` is `awaiting_approval`: ask for approval of `activePhase` and stop.
   - No active phase: run the command after `lastApprovedPhase` (empty → `/v0-intake`; `intake` → `/v0-design`; `design` → `/v0-build`; `build` → `/v0-verify`; `verify` → `/v0-local-release`).
   - With no artifact yet, start `/v0-scaffold` when the story is P0-A; otherwise start `/v0-intake`.
3. Before the first phase, verify prerequisites: a brownfield repo has `onboard` approved in `docs/agents-v0/onboarding/state.json` (`/v0-onboard`); a story from a milestone manifest has every dependency story Verify-approved in its `.state.json`; no other feature's code or shared-file edit is in the working tree. Report the first unmet prerequisite and stop.

## Tier routing
- **Trivial** — use `/v0-triage`, then `/v0-maintain` with the abbreviated Verify.
- **Emergency** — use `/v0-maintain` with a rollback plan and `Follow-up verify due`, then `/v0-local-release`. Full `/v0-verify` is owed by that date.
- **Major** — the full pipeline; Design includes `system-design`, threat-model notes, and the ARC pack when `Material: yes`.
- **Standard** — the pipeline below.

## Pipeline
| Step | Command | Stops at |
|------|---------|----------|
| 1 | `/v0-intake` | Intake gate |
| 2 | `/v0-design` (contract or N/A, `design.md`, `design-reviewer` when there is a contract, UI, public route, or `Material: yes`) | Design gate (skipped for `Contract: None`) |
| 3 | `/v0-build` | Build gate |
| 4 | `/v0-verify` | Verify gate |
| 5 | `/v0-local-release` | Release completion |

- **STOP at every gate.** Present the phase summary, set `--status awaiting_approval` via the phase guard, and wait for the user's explicit approval. Do not auto-advance.
- **P0-A** runs via `/v0-scaffold` on the integration branch before feature stories start at `/v0-intake`.
- **Contract-free stories (`Contract: None`):** When a story has no OpenAPI draft, no AsyncAPI or `events/` contract, no UX spec, no new public route other than `/health`, `/ready`, or `/live`, and `Material: no`, `/v0-design` writes `design.md` (`N/A: no /api/v1 operation`, `N/A: no event contract`) and transitions directly into `/v0-build` without a separate Design stop.
- **Known helpers launch in the same turn.** When Design needs a contract, launch `schema-author` with `solution-architect`. Helper briefs (`<slug>.helper-brief.md`) are for mid-phase needs (`explore-researcher`, `debug-investigator`, `docs-author`).
- **After each approval**, record the approval in `<feature>.state.json` via `sh .agents-v0/scripts/sync-feature-state.sh --approve <phase> docs/agents-v0/requirements/<feature>.md`.
- **A Critical finding** at Verify routes back to Build (or `/v0-maintain` for a defect in released code) via `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed false --reopen build <artifact>`, then re-enters Verify after the fix is approved.

## Who runs it
Prefer launching the `orchestrator` subagent, which follows this file. In single-agent IDEs or sessions where subagents cannot spawn subagents, the main session executes each phase command and skill sequentially.

## Conduct
Per `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report at each phase. No commits, merges, or pushes without explicit user approval. Follow `workflow-orchestration.mdc`.
