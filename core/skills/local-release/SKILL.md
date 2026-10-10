---
name: local-release
description: Local release checkpoint after Verify. Fast-forward the integration branch, record Decision Local, and stop so the next story can start. Does not open a merge request.
---

# local-release

Local checkpoint for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-local-release`). This is not `/v0-release`.

## Steps
1. Confirm Verify passed with no Critical findings. A maintenance note does not use this skill; it uses `release-pr`. For `Story: P0-A` with `Milestone: P0`, the test report's `commit:` equals `HEAD` and the earlier approval rows may still be absent.
2. When the build and verify reports already name `HEAD`, do not commit them again. Otherwise commit the code, write reports whose `commit:` line is that SHA, then commit the reports. Each git write needs its own authorization.
3. Resolve the base with `sh .agents-v0/scripts/resolve-integration-branch.sh`. For a story that already has Approved Build and Verify rows, run `sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> --base <that-ref>` before asking for approval. Fix what it reports. A code change after the reports' `commit:` goes back through Verify. Do not re-stamp a report to make it pass.
4. Stop for explicit user approval. Do not infer it.
5. On that approval, append the `release` row with Decision `Local` (not `Approved`). The Artifacts cell is the current branch name and the full `HEAD` SHA. The Approver is the person who approved. For P0-A, the same approval also appends Intake, Design, Build, and Verify when those rows are missing, then run the local gate from step 3. If the gate fails, set `blocked` and do not clear the active phase.
6. Commit the approval row (its own authorization). When the resolved ref is a local branch name with no slash, and it is an ancestor of `HEAD`, fast-forward it with `git merge --ff-only` of that SHA. That merge asks. If it is not a fast-forward, stop with `blocked` and reason `integration branch is not a fast-forward`. When the ref is `HEAD` or contains a slash, skip the fast-forward and tell the user to set `Integration branch` in `docs/agents-v0/project-profile.md` to a local branch name.
7. Write `docs/agents-v0/requirements/<feature>.phase-result.md` with `phase` `release`, `status` `local`, the branch and SHA, and no GitLab blocker. Run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --clear-active`. Decision `Local` does not advance `lastApprovedPhase`. The next story may start at `/v0-intake`. This story's next command is `/v0-release`.

## Do not
- Call `glab`, push, or write Decision `Approved` on the release row.
- Merge or approve a merge request.
- Treat this checkpoint as Release completion. Completion remains the human merge after `/v0-release`.
