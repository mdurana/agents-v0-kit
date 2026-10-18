---
name: local-release
description: Local release checkpoint after Verify. Fast-forward the integration branch, record Decision Local, and stop so the next story can start. Does not open a merge request.
---

# local-release

Local checkpoint for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-local-release`). This is not `/v0-release`.

## Steps
1. Confirm Verify passed with no Critical findings. A maintenance note does not use this skill; it uses `release-pr`. For `Story: P0-A` with `Milestone: P0`, non-doc files are unchanged since the test report's `commit:` (or `commit:` equals `HEAD`) and the earlier approval rows may still be absent.
2. Ensure verify reports, test evidence, and the Intake artifact (`docs/agents-v0/requirements/<feature>.md`) are tracked and committed in `HEAD`. A report's `commit:` header names the **verified code/test commit**, not the subsequent doc commit that adds the report or approval row. Check with `git cat-file -e "HEAD:<path>"` and `git diff --quiet HEAD -- <path>`. When reports or the `Approved` verify row are untracked or uncommitted on disk and no non-doc files changed since `commit:`, commit them without changing `commit:` (`git commit -m "<message>" -- <artifact> docs/agents-v0/verify/<feature> docs/agents-v0/requirements/<feature>.state.json`; own authorization) so `HEAD` advances to a doc-only commit while `commit:` stays on the verified code SHA. Only when non-doc files changed after `commit:` does the change go back through Verify (do not re-stamp a report to cover unverified code). When the reports and approval rows are already committed in `HEAD` with no uncommitted changes and no non-doc changes since `commit:`, do not commit them again.
3. Resolve the base with `sh .agents-v0/scripts/resolve-integration-branch.sh`. For a story that already has committed Approved Build and Verify rows, run `sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> --base <that-ref>` before asking for approval (when the current branch is already `<that-ref>`, the script diffs from the commit before the story started). Fix what it reports.
4. Stop for explicit user approval. Do not infer it.
5. On that approval, append the `release` row with Decision `Local` (not `Approved`). The Artifacts cell is the current branch name and the full `HEAD` SHA. The Approver is the person who approved. For P0-A, the same approval also appends Intake, Design, Build, and Verify with Decision `Approved` (advancing `lastApprovedPhase` to `verify`; Decision `Local` on release does not advance it further) when those rows are missing.
6. Write `docs/agents-v0/requirements/<feature>.phase-result.md` with `phase` `release`, `status` `local`, the branch and SHA, and no GitLab blocker. Run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --clear-active`. Commit the approval rows, reports (if P0-A), phase result, and cleared state together (its own authorization). For P0-A, run `sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> --base <that-ref>` after that commit; if the gate fails, set `blocked` and do not proceed.
7. Check the current branch (`git symbolic-ref --quiet --short HEAD`). When the current branch is already the resolved ref (for example, both are `main`), skip `git merge --ff-only` because the commit in step 6 already advanced that branch. When the current branch is a separate feature branch and the resolved ref is a local branch name with no slash that is an ancestor of `HEAD`, fast-forward the integration branch to `HEAD` (`git checkout <that-ref> && git merge --ff-only <checkpoint-sha>`, its own authorization); if it is not a fast-forward, stop with `blocked` and reason `integration branch is not a fast-forward`. When the ref is `HEAD` or contains a slash, skip the fast-forward and tell the user to set `Integration branch` in `docs/agents-v0/project-profile.md` to a local branch name. The next story may start at `/v0-intake`. This story's next command is `/v0-release`.

## Do not
- Call `glab`, push, or write Decision `Approved` on the release row.
- Merge or approve a merge request.
- Treat this checkpoint as Release completion. Completion remains the human merge after `/v0-release`.
