---
description: Primary local release workflow after Verify. Re-verify the clean tree with the stack's native build/test command, merge into the integration branch on user confirmation, and mark the work released in state.json.
---

# /v0-local-release

You are entering the **Local Release** phase (`workflow-orchestration.mdc`). This is the primary local completion path after `/v0-verify` for both feature stories (`docs/agents-v0/requirements/<feature>.md`) and maintenance notes (`docs/agents-v0/maintain/<id>/note.md`).

## Prerequisite & Resume
1. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json`).
2. Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (or for `P0-A`, `verifyPassed` is `true` and the user is approving the single P0-A release gate now). A maintenance note with `tier: "emergency"` may proceed when `maintain` is approved and the note records a rollback plan and `Follow-up verify due`. If Verify has not passed and neither exception applies, stop and run `/v0-verify` first.
3. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress <artifact>`.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel Features). Stop if another feature's uncommitted changes are in the working tree.

## Instructions
1. Launch the `release-manager` subagent (skill: `local-release`) or execute `local-release` directly in single-agent IDEs:
   - Sync `README.md` or sequence diagrams if the feature changed user-facing setup or flows.
   - Update `CHANGELOG.md` via `sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md` when the profile uses a changelog.
2. **Final Native Stack Check:**
   - Resolve the command with `sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`, then execute the printed command. The script only prints. If it prints nothing, use the layout default. Stop when the tree is not green, and do not mark the work released.
3. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`) with `phase: release`, `status: awaiting_approval`, and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`.
4. **Stop** and ask for explicit user approval to complete the local release (committing any release notes/state updates and merging into the target integration branch resolved by `sh .agents-v0/scripts/resolve-integration-branch.sh`).
5. **After explicit user approval:**
   - Commit any pending delivery evidence/changelog files (`git commit` requires your confirmation in the IDE prompt).
   - For `Story: P0-A`, do not merge. `HEAD` must already be the integration ref printed by `sh .agents-v0/scripts/resolve-integration-branch.sh`. If it is not, stop.
   - For every other story, if working on a feature branch separate from the integration branch, check out the ref printed by `sh .agents-v0/scripts/resolve-integration-branch.sh` (`git checkout <ref>`), then merge that branch upon user confirmation. A feature story's branch is `feature/<feature>` from Intake (`git merge --no-ff feature/<feature>`). If the merge fails or conflicts, stop and do not mark the feature released.
   - Once the merge succeeds (or when already on the integration branch), run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>`, update that phase-result file to `status: approved`, and commit the updated release state on user confirmation.
   - When `docs/agents-v0/project-profile.md` has a **Deploy** table, follow `release-deploy`: one explicit authorization per environment, a smoke check, and a rollback command. Until the last smoke check is recorded, the story is not complete.
   - Do not call `glab` or push to a remote unless the user explicitly asks to push or run `/v0-release`.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`.
