---
description: Primary local release workflow after Verify. Re-verify the clean tree with the stack's native build/test command, merge into the integration branch on user confirmation, and mark the work released in state.json.
---

# /v0-local-release

You are entering the **Local Release** phase (`workflow-orchestration.mdc`). This is the primary local completion path after `/v0-verify` for both feature stories (`docs/agents-v0/requirements/<feature>.md`) and maintenance notes (`docs/agents-v0/maintain/<id>/note.md`).

## Prerequisite & Resume
1. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json`).
2. Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (or for `P0-A`, `verifyPassed` is `true` and the user is approving the single P0-A release gate now). If Verify has not passed, stop and run `/v0-verify` first.
3. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress <artifact>`.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel features). Stop if another feature's uncommitted changes are in the working tree.

## Instructions
1. Launch the `release-manager` subagent (skill: `local-release`) or execute `local-release` directly in single-agent IDEs:
   - Sync `README.md` or sequence diagrams if the feature changed user-facing setup or flows.
   - Update `CHANGELOG.md` via `sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md` when the profile uses a changelog.
2. **Final Native Stack Check:**
   - Run the bound pack's native verify command (`sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`) to ensure the tree is green before merging.
3. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `maintain/<id>/phase-result.md`) with `phase: release`, `status: awaiting_approval`, and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`.
4. **Stop** and ask for explicit user approval to complete the local release (committing any release notes/state updates and merging into the target integration branch resolved by `sh .agents-v0/scripts/resolve-integration-branch.sh`).
5. **After explicit user approval:**
   - Commit any pending delivery evidence/changelog files (`git commit` requires your confirmation in the IDE prompt).
   - If working on a feature branch separate from the integration branch (`sh .agents-v0/scripts/resolve-integration-branch.sh`), merge into the integration branch (`git merge --no-ff <feature-branch>`) upon user confirmation. If the merge fails or conflicts, stop and do not mark the feature released.
   - Once the merge succeeds (or when already on the integration branch), run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>`, update `phase-result.md` to `status: approved`, and commit the updated release state on user confirmation.
   - Do not call `glab` or push to a remote unless the user explicitly asks to push or run `/v0-release`.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`.
