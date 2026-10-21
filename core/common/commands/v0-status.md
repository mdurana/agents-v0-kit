---
description: Resume delivery — read the JSON state files and on-disk artifacts, then report the current phase and next command.
---

# /v0-status

Use the feature, maintenance id, program, or onboarding workstream the user names. When none is named, list every open state file and ask:
- `docs/agents-v0/requirements/*.state.json` (feature stories)
- `docs/agents-v0/maintain/*/state.json` (maintenance fixes, upgrades, hotfixes)
- `docs/agents-v0/onboarding/state.json` (brownfield onboarding)
- `docs/agents-v0/program.state.json` (greenfield program roadmap / architecture / plan)

Do not assume the newest state file is the one the user means (`workflow-orchestration.mdc` Parallel Features).

Read the selected `.state.json` file and its primary artifact (`artifact` field). Also read the phase-result file when it exists: `docs/agents-v0/requirements/<feature>.phase-result.md`, `docs/agents-v0/maintain/<id>/phase-result.md`, or `docs/agents-v0/onboarding/phase-result.md`. For a program, also read `docs/agents-v0/roadmap/<program>.phase-result.md`, `docs/agents-v0/architecture.phase-result.md`, and `docs/agents-v0/milestones/plan.phase-result.md`. Do not advance a phase or infer approval.

1. **Change tier & state summary:** Report `feature`, `tier`, `lastApprovedPhase`, `approvedPhases`, `phaseDates`, `activePhase`, `activeStatus`, `verifyPassed`, `reopenCount`, `baseCommit`, and the `artifacts` map. For a milestone, list each story as passed or blocked from its own state file.
2. **Next command resolution:**
   - `activeStatus` is `in_progress` or `blocked`: the next command is `/v0-<activePhase>`. When `activePhase` is `release`, resume `/v0-local-release` unless a remote merge request is already in progress. Report `blockedReason` when `blocked`. Re-entering that command continues from existing files on disk.
   - `activeStatus` is `awaiting_approval`: stop and ask the user to approve `activePhase`. Do not start the next phase.
   - No `activePhase`: name the next command from `lastApprovedPhase`:
     - Feature: empty → `/v0-intake` (`Story: P0-A` → `/v0-build`); `intake` → `/v0-design`; `design` → `/v0-build`; `build` → `/v0-verify`; `verify` → `/v0-local-release` (primary) or `/v0-release` (remote MR); `release` → complete. Do not reopen the story. A fix or a small change starts at `/v0-maintain`. A new feature starts at `/v0-intake` with a new slug. When `docs/agents-v0/project-profile.md` has a **Deploy** table and no deploy record is on disk for this story, the next command is `release-deploy` until the last smoke check is recorded. Name `/v0-release` only when the user wants to push or open a remote merge request.
     - Maintenance note: empty → `/v0-maintain`; `maintain` → `/v0-verify <id>`, except `tier: "emergency"` with a rollback plan and `Follow-up verify due` → `/v0-local-release` or `/v0-release` (full `/v0-verify <id>` is owed by that date); `verify` → `/v0-local-release` or `/v0-release`; `release` → complete, with `/v0-release` only when the user wants a remote merge request. After an emergency release, if `verify` is not in `approvedPhases`, the next command is `/v0-verify <id>`, owed by `Follow-up verify due`. Otherwise, when the profile has a **Deploy** table and no deploy record is on disk, the next command is `release-deploy` until that smoke check is recorded.
     - Onboarding: `onboard` → `/v0-roadmap` (multi-story program), `/v0-intake` (single story), or `/v0-maintain` (fix/upgrade). Name `/v0-plan` only when `program.state.json` already has `architecture` approved and `plan` does not.
     - Program (`program.state.json`): empty → `/v0-roadmap`; `roadmap` → `/v0-architecture`; `architecture` → `/v0-plan`; `plan` → `/v0-intake` for the first story, or `/v0-build` when that story is `P0-A`. `/v0-deliver <first-story>` runs that same path through its gates.
3. **Working-tree & commit check:** If `baseCommit` is set in `.state.json` and `verifyPassed` is `true`, check `git status --porcelain` and whether source files changed since the Verify reports were written; if code changed after Verify, advise re-running `/v0-verify` before release.
4. Ignore `docs/agents-v0/backlog/tickets.csv` and `docs/agents-v0/presentations/`. Never name `/v0-export` or `/v0-deck` as the next command.
