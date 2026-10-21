---
name: local-release
description: Local release checkpoint after Verify. Fast-forward the integration branch, record Decision Local, and stop so the next story can start. Does not open a merge request.
---

# local-release

Local checkpoint for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-local-release`). This is not `/v0-release`.

## Steps
1. Confirm Verify passed (`verifyPassed: true` in `docs/agents-v0/requirements/<feature>.state.json` or `docs/agents-v0/maintain/<id>/state.json`) with no Critical findings.
2. Ensure verify reports, test evidence, and the artifact (`docs/agents-v0/requirements/<feature>.md` or `docs/agents-v0/maintain/<id>/note.md`) are tracked on disk. Only when non-doc files changed after `verifyPassed: true` does the change go back through Verify (`sh .agents-v0/scripts/sync-feature-state.sh --reopen verify --verify-passed false <artifact>`).
3. Resolve the base with `sh .agents-v0/scripts/resolve-integration-branch.sh`.
4. Stop for explicit user approval. Do not infer it.
5. On that approval, write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `maintain/<id>/phase-result.md`) with `phase` `release`, `status` `local`, the branch and SHA, and no GitLab blocker, and optionally append the `release` row with Decision `Local` (not `Approved`). When the user authorizes a commit, commit the feature code, reports, and phase result together.
6. Check the current branch (`git symbolic-ref --quiet --short HEAD`). When the current branch is already the resolved ref (for example, both are `main`), skip `git merge --ff-only` because the commit in step 5 already advanced that branch. When the current branch is a separate feature branch and the resolved ref is a local branch name with no slash that is an ancestor of `HEAD`, fast-forward the integration branch to `HEAD` (`git checkout <that-ref> && git merge --ff-only <checkpoint-sha>`, its own authorization); if it is not a fast-forward, stop with `blocked` and reason `integration branch is not a fast-forward`. When the ref is `HEAD` or contains a slash, skip the fast-forward and tell the user to set `Integration branch` in `docs/agents-v0/project-profile.md` to a local branch name.
7. After the merge succeeds (or is skipped because already on the integration branch), run `sh .agents-v0/scripts/sync-feature-state.sh --approve release --clear-active <artifact>` (which also backfills earlier phases and sets `verifyPassed: true` for `Story: P0-A`) and commit the updated state file on user confirmation. The next story may start at `/v0-intake`. This story's next command is `/v0-release`.

## Do not
- Call `glab`, push, or write Decision `Approved` on the release row.
- Merge or approve a merge request.
- Treat this checkpoint as Release completion. Completion remains the human merge after `/v0-release`.
