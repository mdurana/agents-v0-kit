---
description: Resume delivery — read the JSON state files and on-disk artifacts, then report the current phase and next command.
---

# /v0-status

Use the feature, maintenance id, program, or onboarding workstream the user names. When none is named, list every open state file and ask:
- `docs/agents-v0/requirements/*.state.json` (feature stories)
- `docs/agents-v0/maintain/*/state.json` (maintenance fixes, upgrades, hotfixes)
- `docs/agents-v0/onboarding/state.json` (brownfield onboarding)
- `docs/agents-v0/program.state.json` (greenfield program roadmap / architecture / plan)

Do not assume the newest state file is the one the user means (`workflow-orchestration.mdc` Parallel features).

Read the selected `.state.json` file and its primary artifact (`artifact` field, plus `<feature>.phase-result.md` when present). Do not advance a phase or infer approval.

1. **Change tier & state summary:** Report `feature`, `tier`, `lastApprovedPhase`, `approvedPhases`, `activePhase`, `activeStatus`, `verifyPassed`, `reopenCount`, and `baseCommit`.
2. **Next command resolution:**
   - `activeStatus` is `in_progress` or `blocked`: the next command is `/v0-<activePhase>`. Report the `artifacts` map already recorded in `.state.json` and `blockedReason` when `blocked`. Re-entering that command continues from existing files on disk.
   - `activeStatus` is `awaiting_approval`: stop and ask the user to approve `activePhase`. Do not start the next phase.
   - No `activePhase`: name the next command from `lastApprovedPhase`:
     - Feature: empty → `/v0-intake`; `intake` → `/v0-design`; `design` → `/v0-build`; `build` → `/v0-verify`; `verify` → `/v0-local-release` (primary) or `/v0-release` (remote MR); `release` → complete (use `/v0-maintain` for later changes).
     - Maintenance note: `maintain` → `/v0-verify <id>`; `verify` → `/v0-local-release` or `/v0-release`.
     - Onboarding: `onboard` → `/v0-roadmap` (multi-story program), `/v0-intake` (single story), or `/v0-maintain` (fix/upgrade).
     - Program (`program.state.json`): empty → `/v0-roadmap`; `roadmap` → `/v0-architecture`; `architecture` → `/v0-plan`; `plan` → `/v0-deliver <first-story>`.
3. **Working-tree & commit check:** If `baseCommit` is set in `.state.json` and `verifyPassed` is `true`, check `git status --porcelain` and whether source files changed since the Verify reports were written; if code changed after Verify, advise re-running `/v0-verify` before release.
4. Ignore `docs/agents-v0/backlog/tickets.csv` and `docs/agents-v0/presentations/`. Never name `/v0-export` or `/v0-deck` as the next command.
