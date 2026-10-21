---
description: Run one story through the lifecycle by following each phase command in order, stopping at every gate for explicit user approval; resumes from the state file.
---

# /v0-deliver

Run **one story** through **Intake → Design → Build → Verify → Local Release (`/v0-local-release`) or Remote Release (`/v0-release`)** by following each phase command in order. `/v0-deliver` holds no phase detail of its own: every prerequisite, resume rule, collision check, helper step, skill invocation, and approval update lives in `/v0-intake`, `/v0-design`, `/v0-build`, `/v0-verify`, `/v0-local-release`, and `/v0-release`. A new program of more than one story starts with `/v0-roadmap`, then `/v0-architecture`, then `/v0-plan`. `/v0-deliver` then runs one story of the approved manifest in dependency order. `/v0-export` and `/v0-deck` are not steps in this pipeline.

## Start or resume
1. Name the feature (the slug of `docs/agents-v0/requirements/<feature>.md`) and, for a new one, the source spec (Jira, Confluence, or a description). Ask when either is missing. Do not guess the feature from the newest state file.
2. If `docs/agents-v0/requirements/<feature>.state.json` exists, read it as `/v0-status` does:
   - `activeStatus` is `in_progress` or `blocked`: run `activePhase` again.
   - `activeStatus` is `awaiting_approval`: ask for approval of `activePhase` and stop.
   - No active phase: run the command after `lastApprovedPhase` (empty → `/v0-intake`, or `/v0-build` when `Story: P0-A`; `intake` → `/v0-design`; `design` → `/v0-build`; `build` → `/v0-verify`; `verify` → `/v0-local-release` by default, or `/v0-release` when requested).
   - With no artifact yet, start `/v0-build` when the story is P0-A; otherwise start `/v0-intake`.
3. Before the first phase, verify prerequisites: a brownfield repo has `onboard` approved in `docs/agents-v0/onboarding/state.json` (`/v0-onboard`); a story from a milestone manifest has every dependency story Verify-approved in its `.state.json`; no other feature's code or shared-file edit is in the working tree. Report the first unmet prerequisite and stop.

## Tier routing
- **Trivial** — use `/v0-triage`, then `/v0-maintain` with the abbreviated Verify.
- **Emergency** — use `/v0-maintain` with a rollback plan and `Follow-up verify due`, then release. Full `/v0-verify` is owed by that date.
- **Major** — the full pipeline; Design includes `system-design`, threat-model notes, and the ARC pack when `Material: yes`.
- **Standard** — the pipeline below.

## Pipeline
| Step | Command | Stops at |
|------|---------|----------|
| 1 | `/v0-intake` | Intake gate |
| 2 | `/v0-design` (contract or N/A, `design.md`, `design-reviewer` when there is a contract, UI, public route, or `Material: yes`) | Design gate (skipped for `Contract: None`) |
| 3 | `/v0-build` | Build gate |
| 4 | `/v0-verify` | Verify gate |
| 5 | `/v0-local-release` (primary) or `/v0-release` (optional remote MR) | Release completion |

- **STOP at every gate.** Present the phase summary, set `--status awaiting_approval` via `sh .agents-v0/scripts/sync-feature-state.sh`, and wait for the user's explicit approval. Do not auto-advance.
- **P0-A** skips `/v0-intake` and `/v0-design`: `/v0-build` copies the milestone story and `AC-1` through `AC-4` and writes the minimal `N/A` design, then continues through `/v0-verify` to a single approval stop at Release (`/v0-local-release` or `/v0-release`).
- **Contract-free stories (`Contract: None`):** When a story has no OpenAPI draft, no AsyncAPI or `events/` contract, no UX spec, no new public route other than `/health`, `/ready`, or `/live`, and `Material: no`, `/v0-design` writes `design.md` (`N/A: no /api/v1 operation`, `N/A: no event contract`) and transitions directly into `/v0-build` without a separate Design stop.
- **Known helpers launch in the same turn.** When Design needs a contract, launch `schema-author` with `solution-architect`. Helper briefs (`<slug>.helper-brief.md`) are for mid-phase needs (`explore-researcher`, `debug-investigator`, `docs-author`).
- **After each approval**, record the approval in `<feature>.state.json` via `sh .agents-v0/scripts/sync-feature-state.sh --approve <phase> docs/agents-v0/requirements/<feature>.md`.
- **A Critical finding** at Verify routes back to Build (or `/v0-maintain` for a defect in released code) via `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed false --reopen build <artifact>`, then re-enters Verify after the fix is approved.

## Who runs it
Prefer launching the `orchestrator` subagent, which follows this file. In single-agent IDEs or sessions where subagents cannot spawn subagents, the main session executes each phase command and skill sequentially.

## Conduct
Per `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report at each phase. No commits, merges, or pushes without explicit user approval. Follow `workflow-orchestration.mdc`.
