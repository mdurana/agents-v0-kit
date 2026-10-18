---
description: Local release checkpoint after Verify. Fast-forward the integration branch, record Decision Local, and stop so the next story can start. GitLab release stays /v0-release.
---

# /v0-local-release

You are entering the **local release** checkpoint (`workflow-orchestration.mdc`). It is optional. After Verify, `/v0-release` may run without it. It does not open a merge request and it does not complete Release.

## Prerequisite
Before launching the release manager, read `docs/agents-v0/requirements/<feature>.phase-result.md` when it exists. The feature artifact needs an `Approved` verify row, and the verify reports' `commit:` lines equal `HEAD`. For `Story: P0-A` with `Milestone: P0`, `docs/agents-v0/verify/<feature>/test-report.md` with `commit:` equal to `HEAD` is enough; Intake, Design, Build, and Verify rows are written at the approval below. A maintenance note does not use this command: run `/v0-release`. If the feature evidence is missing, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<one line>"` when the artifact exists, then stop.

## Resume
Run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase release --status in_progress`. If this checkpoint is already `in_progress` or `blocked`, continue from files on disk. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. For a story with existing Approved Build and Verify rows, run the local gate; when the local gate has passed, re-run with `--status awaiting_approval` and stop. For P0-A, stop for explicit approval first because the Build and Verify rows do not exist until approved, commit the reports and state, write the approval rows, and run the gate. Do not write the `Local` row until the user approves. If the release row's Decision is already `Local`, check if the checkpoint is complete (`--clear-active` has run and `docs/agents-v0/requirements/<feature>.phase-result.md` records `phase: release`, `status: local`): if complete, stop and name `/v0-release` for this story; if incomplete, resume the remaining fast-forward, phase-result, and `--clear-active` steps. The next story starts with `/v0-intake` from the integration branch. If the release row is `Approved`, stop: this story is past the checkpoint.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<paths>"` and stop.

## Instructions
1. Launch the `release-manager` subagent (skill: `local-release`).
2. Follow that skill. The base ref is `sh .agents-v0/scripts/resolve-integration-branch.sh`. The gate is `sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> --base <that-ref>`.
3. Stop for explicit user approval of this checkpoint. Record Decision `Local`, then `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --clear-active` only after the local gate has passed and the integration branch fast-forward has succeeded or been skipped because the profile names no local branch.
4. Do not call `glab`. Do not write Decision `Approved`. Do not push. The next command for this story, when the user wants the merge request, is `/v0-release`.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`.
