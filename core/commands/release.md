---
description: Release phase. Merge request via glab, local gate dry run, CI fix loop, readiness report, human-authorized merge, then deploy records, changelog, and tag by the release owner.
---

# /release

You are entering the **Release** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching the release manager, read `docs/requirements/<feature>.phase-result.md` when it exists. Confirm the Intake artifact records explicit Verify approval and names the test, VAPT, and review evidence (a maintenance change: see Maintenance change below). Confirm applicable VAPT and code-review findings have no Critical items. If evidence is missing, run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<one line>"` when the artifact exists, then stop and report it; do not infer approval.

## Resume
Run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When readiness is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<paths>"` and stop. Doc updates that touch `README.md`, `docs/architecture.md`, or `docs/network.md` are shared-file edits.

## Instructions
1. Launch the `release-manager` subagent (skill: `release-pr`).
2. Confirm Release gate inputs:
   - Docs synced (README, architecture, network, sequence diagrams).
   - A changelog entry for the change: `sh scripts/release-notes.sh docs/requirements/<feature>.md --include-unreleased --insert CHANGELOG.md` when the profile names a changelog. The version number is the release owner's decision; propose it from the change (a breaking contract change is major, a feature minor, a fix patch) and edit the version file only when the profile names one.
3. **Dry run the delivery gate locally** before anything is pushed: `sh scripts/check-delivery-gate-local.sh <feature> --base origin/<default-branch>` (linkage with `CHECK_MR_APPROVER=0`, design contracts, build plan, endpoint authorization). A maintenance note still renders with `sh scripts/render-mr-body.sh --note docs/maintain/<id>/note.md --base origin/<default-branch>` and `CHECK_MR_APPROVER=0 sh ci/check-delivery-linkage.sh`. Fix what the checks report. Any code change made after the Verify reports' `commit:` makes that evidence stale: the change goes back through Verify (a fix made in this phase is not exempt).
4. Open the merge request only when explicitly requested by the user: `glab mr create` using `.gitlab/merge_request_templates/default.md` with `--description "$(cat <body-file>)"` (the body names the `Feature-Artifact:` or `Maintain-Note:`). Obtain separate explicit authorization before committing or pushing. When the user approves, run the command and **approve the IDE shell prompt** from `pre-shell.sh` — do not set bypass env vars or prefixes on git commands.
5. Run the **CI fix loop**, at most three rounds: read the failing checks, route the fix to the responsible agent, push with its own authorization, re-run. A fix that changes code sends the change back through Verify (step 3). After three rounds, record `--status blocked --reason "CI fix loop exhausted"` and escalate to the user.
6. Publish a status report in the phase result (and the merge-request description). Do not call an external tracker.
7. Do not commit, push, force-push, or hard reset without explicit user approval. Never merge or approve the merge request: those are human acts (`glab mr merge` and `glab mr approve` are blocked).
8. Check **merge-request readiness**: docs and VAPT sign-off complete, merge request open, CI green. Write `docs/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result). After explicit approval, record the `release` row (Decision: `Approved`, date, merge request link) in the Intake artifact **on the merge request branch, before merge**. The Approver cell is the **GitLab username of the person who will approve the merge request** (for example `@ada`), because CI matches it to the real approval; ask for it and do not record a display name. Stop and report readiness; do not merge on behalf of the user.
9. After a person approves the merge request, the manual `delivery-approval` job must be played: a person plays it, or you do with the user's explicit authorization via `glab ci trigger delivery-approval` (the hooks ask). `GITLAB_TOKEN` is a masked project access token with `read_api` scope, limited to the `delivery-approval` environment. That job matches the approver to an Approved release or verify row, using the ci scripts from the default branch.
10. **Completion of the change** is the authorized human merge itself — that merge (reviews, CI checks, merge commit) is the system of record. Confirm it is merged and CI on the default branch is green, and report the outcome; do not push a follow-up commit to the default branch to record it. If no merge request or merge authorization is available, report the blocked status instead.
11. **Deploy.** When `docs/project-profile.md` has a **Deploy** table, the `release-manager` follows `release-deploy` after the merge: each environment needs its own explicit user authorization, a recorded smoke check, and a rollback command. Deployment is complete at the last environment's passing smoke check. Its records (`docs/release/<feature>/`) are committed only through a separate docs-only follow-up merge request, or kept in the release issue; they are never a direct commit to the default branch.
12. **Version and tag.** The release owner (`Release owner` in the profile) creates the tag, or CI does on merge; `git tag` and `glab release create` ask. A **milestone release** is the same after the `milestone` go/no-go row: `sh scripts/release-notes.sh docs/milestones/<milestone>.md --version <x.y.z>` prints the notes from the stories whose release is approved.

## Maintenance change
A fix, patch, upgrade, or hotfix is released from its maintenance note (`docs/maintain/<id>/note.md`), not from an Intake artifact. Use `<id>` for `<feature>` above. The prerequisite is an `Approved` `maintain` row and, unless `Tier: emergency`, an `Approved` `verify` row with its evidence. There is no `release` row: CI binds the merge request approver to the note's `verify` row (the `maintain` row for an emergency), so that row's Approver must be the approving person's GitLab username. Render the body with `--note`, and the merge request names `Maintain-Note:`. A trivial or emergency note still needs its "Tier confirmed by" line. An emergency owes its full Verify by the note's `Follow-up verify due` date.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt-pr-review.mdc`, `project-delivery-core.mdc`, `code-review.mdc`.
