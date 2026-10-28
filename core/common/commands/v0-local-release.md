---
description: Primary local release workflow after Verify. Re-verify the clean tree with the stack's native build/test command, merge into the integration branch on user confirmation, and mark the work released in state.json.
---

# /v0-local-release

You are entering the **Local Release** phase (`workflow-orchestration.mdc`). This is the primary local completion path after `/v0-verify` for both feature stories (`docs/agents-v0/requirements/<feature>.md`) and maintenance notes (`docs/agents-v0/maintain/<id>/note.md`).

## Prerequisite & Resume
1. If `<feature>` or `<id>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not set `in_progress` until it resolves. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json`). If `release` is already in `approvedPhases`, stop. Do not set `in_progress`. A feature story suggests `/v0-triage` for a docs-only edit or a 1-for-1 patch bump, `/v0-maintain` for any other fix, or `/v0-intake` with a new slug for a new feature. A maintenance note suggests a new `<id>`. An emergency note that still owes Verify (`verify` is not in `approvedPhases`) suggests `/v0-verify <id>`.
2. Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (or for `P0-A`, `verifyPassed` is `true` and the user is approving the single P0-A release gate now). A maintenance note with `tier: "emergency"` may proceed when `maintain` is approved and the note records a rollback plan and `Follow-up verify due`. If Verify has not passed and neither exception applies, stop and run `/v0-verify` first.
3. Only after the checks above pass, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress <artifact>`.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel Features). Stop if another feature's uncommitted changes are in the working tree.

## Instructions
1. Launch the `release-manager` subagent (skill: `local-release`) or execute `local-release` directly in single-agent IDEs:
   - Sync `README.md` or sequence diagrams if the feature changed user-facing setup or flows.
   - Update `CHANGELOG.md` via `sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md` when the profile uses a changelog.
2. **Final Native Stack Check:**
   - Resolve the command with `sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`, then execute the printed command. The script only prints. If it prints nothing, use the layout default. Stop when the tree is not green, and do not mark the work released.
<!-- MEM-06: the release gate is where a human turns this story's lesson candidates into cross-story memory. Candidates are proposed here, decided by the user at the gate, and only accepted ones are appended to docs/agents-v0/lessons.md in the integration checkout after the merge. -->
3. **Proposed lessons** (in this checkout, before the gate): run `sh .agents-v0/scripts/check-lessons.sh --unchanged-since <integration-ref> --phase-result <phase-result>` (`<integration-ref>` from `resolve-integration-branch.sh`; `<phase-result>` is the file in step 4). Exit 1: report its `FAIL` lines and stop; a story branch never edits `docs/agents-v0/lessons.md`. Then add at most 3 `release` candidates under `## Lessons` → `### release`, and collect every candidate under `## Lessons` into a `## Proposed lessons` section of that phase-result, one bullet each: `- P-<n> · pending · <phase> · Trigger: … · What happened: … · Do instead: … · Scope: …` (or `- none`). Drop exact duplicates and say which active lesson a near-duplicate repeats. Run the same `check-lessons.sh` command again.
4. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`) with `phase: release`, `status: awaiting_approval`, and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`.
5. **Stop** and ask for explicit user approval to complete the local release (committing any release notes/state updates and merging into the target integration branch resolved by `sh .agents-v0/scripts/resolve-integration-branch.sh`). In the same message, list each `P-<n>` and ask the user to accept or reject it. Any `P-<n>` without an explicit accept when the user approves the release is marked `rejected` and is not appended.
6. **After explicit user approval:**
   - Commit any pending delivery evidence/changelog files (`git commit` requires your confirmation in the IDE prompt).
   - For `Story: P0-A`, do not merge. `HEAD` must already be the integration ref printed by `sh .agents-v0/scripts/resolve-integration-branch.sh`. If it is not, stop.
   - For every other story, if working on a feature branch separate from the integration branch, resolve the integration ref with `sh .agents-v0/scripts/resolve-integration-branch.sh`. When `git worktree list` shows that ref checked out in another worktree, `cd` to that worktree and merge there. Do not run `git checkout <ref>` inside the feature or maintain worktree. Merge on user confirmation. A feature story's branch is `feature/<feature>` from Intake (`git merge --no-ff feature/<feature>`). A standard or emergency maintenance note's branch is `maintain/<id>` (`git merge --no-ff maintain/<id>`). A trivial note is already on the integration branch and does not merge. If the merge fails or conflicts, stop and do not mark the feature released.
   - Once the merge succeeds (or when already on the integration branch), in that integration checkout, run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>`, update that phase-result file to `status: approved`, do the Lessons step below, and then commit the updated release state on user confirmation.
   - **Lessons, in that integration checkout, before that commit:** set each `P-<n>` to `accepted` (when explicitly accepted by the user) or `rejected` (when rejected or not mentioned in the user's release approval), then run `sh .agents-v0/scripts/check-lessons.sh --decided --phase-result <phase-result>`. For each accepted one, append an entry under `## Active lessons` in `docs/agents-v0/lessons.md` using the file edit tool (not shell redirection) and remove the `_No entries yet._` line: `### L-NNN · <today> · accepted` with the id from `sh .agents-v0/scripts/check-lessons.sh --next-id` (run it again for each entry), then `- Story/phase: <feature or id> / <phase>`, `- Trigger:`, `- What happened:`, `- Do instead:`, `- Scope:`. Rejected ones stay in the phase-result only. Run `sh .agents-v0/scripts/check-lessons.sh`. When it fails on the active cap, ask the user which entries to move to `docs/agents-v0/lessons-archive.md` (promoted with a pointer, or retired); do not drop any. Include `docs/agents-v0/lessons.md` in the release-state commit.
   - When `docs/agents-v0/project-profile.md` has a **Deploy** table, follow `release-deploy`: one explicit authorization per environment, a smoke check, and a rollback command. Until the last smoke check is recorded, the story is not complete.
   - Do not call `glab` or push to a remote unless the user explicitly asks to push or run `/v0-release`.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`.
