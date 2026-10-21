---
description: Resume delivery — read the JSON state files and on-disk artifacts, then report the current phase and next command.
---

# /v0-status

Use the feature, maintenance id, program, or onboarding workstream the user names. When none is named, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. One matching open state file is that workstream. When none or more than one of these are open, list them and ask:
- `docs/agents-v0/requirements/*.state.json` (feature stories)
- `docs/agents-v0/maintain/*/state.json` (maintenance fixes, upgrades, hotfixes)
- `docs/agents-v0/onboarding/state.json` (brownfield onboarding)
- `docs/agents-v0/program.state.json` (greenfield program roadmap / architecture / plan)

Do not pick the newest state file (`workflow-orchestration.mdc` Parallel Features).

When none of those four state files exist, ask which start this is. An existing repo starts at `/v0-onboard`. A new program starts at `/v0-roadmap`. A docs-only edit or a 1-for-1 patch bump starts at `/v0-triage`. Do not guess.

Read the selected `.state.json` file and its primary artifact (`artifact` field). Also read the phase-result file when it exists: `docs/agents-v0/requirements/<feature>.phase-result.md`, `docs/agents-v0/maintain/<id>/phase-result.md`, or `docs/agents-v0/onboarding/phase-result.md`. For a program, also read `docs/agents-v0/roadmap/<program>.phase-result.md`, `docs/agents-v0/architecture.phase-result.md`, and `docs/agents-v0/milestones/plan.phase-result.md`. Do not advance a phase or infer approval.

1. **Change tier & state summary:** Report `feature`, `tier`, `lastApprovedPhase`, `approvedPhases`, `phaseDates`, `activePhase`, `activeStatus`, `verifyPassed`, `reopenCount`, `baseCommit`, and the `artifacts` map. For a milestone, list each story as passed or blocked from its own state file.
2. **Next command resolution:**
   - A feature story with `release` in `approvedPhases` is complete. Do not resume `activePhase`. Do not advise `/v0-verify <feature>`. A docs-only edit or a 1-for-1 patch bump starts at `/v0-triage`. Any other fix starts at `/v0-maintain` with a new id the user names. A new feature starts at `/v0-intake` with a new slug. When `docs/agents-v0/project-profile.md` has a **Deploy** table and no deploy record is on disk for this story, the next command is `release-deploy` until the last smoke check is recorded. Name `/v0-release <feature>` only when the user wants to push or open a remote merge request.
   - A maintenance note with `release` in `approvedPhases` is complete. Do not resume `activePhase`. Start a new `<id>` the user names. Exception: `tier: "emergency"` and `verify` is not in `approvedPhases` → `/v0-verify <id>`, owed by `Follow-up verify due`, unless `activeStatus` is `blocked` for a Critical finding in that owed Verify. That blocked note names a new `/v0-maintain` id.
   - For a non-P0-A feature story, run `git worktree list` and look for branch `feature/<feature>`. For a standard or emergency maintenance note, look for branch `maintain/<id>` only when `release` is not in `approvedPhases`. If that worktree exists and this checkout is not it, the next command is to open that folder and run `/v0-status <feature>` or `/v0-status <id>` there. Do not name `/v0-design`, `/v0-build`, or `/v0-verify` in the integration checkout. A released emergency note that still owes Verify stays in the integration checkout. A trivial note has no worktree.
   - `activeStatus` is `in_progress` or `blocked`: the next command is `/v0-<activePhase> <feature>` or `/v0-<activePhase> <id>`. When `activePhase` is `release`, resume `/v0-local-release <feature>` or `/v0-local-release <id>` unless a remote merge request is already in progress. A released emergency note whose `verify` phase is `blocked` for a Critical finding in owed Verify names a new `/v0-maintain` id instead of `/v0-verify <id>`. Report `blockedReason` when `blocked`. Re-entering that command continues from existing files on disk.
   - `activeStatus` is `awaiting_approval`: stop and ask the user to approve `activePhase`. Do not start the next phase.
   - No `activePhase`: name the next command from `lastApprovedPhase`:
     - Feature: empty → `/v0-intake <feature>` (`Story: P0-A` → `/v0-build <feature>`); `intake` → `/v0-design <feature>`; `design` → `/v0-build <feature>`; `build` → `/v0-verify <feature>`; `verify` → `/v0-local-release <feature>` (primary) or `/v0-release <feature>` (remote MR). `release` is already handled above.
     - Maintenance note: do not name `/v0-triage` once this note exists. empty → `/v0-maintain <id>`; `maintain` → `/v0-verify <id>` (when `tier` is `trivial`, Verify is abbreviated and does not run `security-reviewer` or `code-reviewer`), except `tier: "emergency"` with a rollback plan and `Follow-up verify due` → `/v0-local-release <id>` or `/v0-release <id>` (full `/v0-verify <id>` is owed by that date); `verify` → `/v0-local-release <id>` or `/v0-release <id>`. `release` is already handled above.
     - Onboarding: `onboard` → `/v0-roadmap` (multi-story program), `/v0-intake` (single story), `/v0-triage` (docs-only or a 1-for-1 patch bump), or `/v0-maintain` (any other fix). Name `/v0-plan` only when `program.state.json` already has `architecture` approved and `plan` does not.
     - Program (`program.state.json`): empty → `/v0-roadmap`; `roadmap` → `/v0-architecture`; `architecture` → `/v0-plan`; `plan` → `/v0-intake <first-story>`, or `/v0-build <first-story>` when that story is `P0-A`. `/v0-deliver <first-story>` runs that same path through its gates.
3. **Working-tree & commit check:** While `release` is not in `approvedPhases`, if `baseCommit` is set in `.state.json` and `verifyPassed` is `true`, check `git status --porcelain` and whether source files changed since the Verify reports were written; if code changed after Verify, advise re-running `/v0-verify <feature>` or `/v0-verify <id>` before release.
4. Ignore `docs/agents-v0/backlog/tickets.csv` and `docs/agents-v0/presentations/`. Never name `/v0-export` or `/v0-deck` as the next command.
