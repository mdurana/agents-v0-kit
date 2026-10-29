---
description: Optional remote release workflow via GitLab merge request (glab), CI fix loop, readiness report, and human-authorized merge.
---

# /v0-release

You are entering the **Remote Release** phase (`workflow-orchestration.mdc`). Teams releasing locally use `/v0-local-release`; use `/v0-release` when publishing a remote GitLab merge request (`glab`).

## Prerequisite & Resume
1. If `<feature>` or `<id>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not set `in_progress` until it resolves. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json` for a maintenance change). If `release` is already in `approvedPhases`, stop. Do not set `in_progress`. A feature story suggests `/v0-triage` for a docs-only edit or a 1-for-1 patch bump, `/v0-maintain` for any other fix, or `/v0-intake` with a new slug for a new feature. A maintenance note suggests a new `<id>`. An emergency note that still owes Verify (`verify` is not in `approvedPhases`) suggests `/v0-verify <id>`.
2. Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (or for `P0-A`, `verifyPassed` is `true` and the user is approving the single P0-A release gate now). A maintenance note with `tier: "emergency"` may proceed when `maintain` is approved and the note records a rollback plan and `Follow-up verify due`. Full `/v0-verify` stays owed by that date. If Verify has not passed and neither exception applies, stop and run `/v0-verify` first.
3. Only after the checks above pass, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress <artifact>`.

## Instructions
1. Launch the `release-manager` subagent (skill: `release-pr`).
2. Sync `README.md`, sequence diagrams, and `CHANGELOG.md` (`sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md` when configured).
3. Render the merge-request description with `sh .agents-v0/scripts/render-mr-body.sh <feature> --base origin/<default-branch> > <body-file>` for a feature story, or `sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/<id>/note.md --base origin/<default-branch> > <body-file>` for a maintenance note. The script only prints.
4. Verify `git remote get-url origin` and that `glab` is on `PATH`. If the remote lookup fails or `glab` is missing, recommend `/v0-local-release`, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status blocked --reason "no origin or glab" <artifact>`, and stop.
5. Ask for explicit user authorization before committing, pushing (`git push`), or creating the merge request (`glab mr create`). Never run `glab mr merge` or `glab mr approve` (permanently blocked by `pre-shell.sh`).
6. **CI fix loop (at most 3 rounds, prompt-only):** If remote CI reports a failure, route the fix to the responsible engineer agent, re-verify locally via `/v0-verify`, and push only with explicit user authorization. After 3 failed rounds, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status blocked --reason "CI fix loop exhausted" <artifact>` and escalate to the user.
7. When the merge request is open and CI is green, write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`) with `phase: release`, `status: awaiting_approval`, and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`.
<!-- kitfix-20261029-step4-p1e: --approve release runs only on the integration branch (sync-feature-state.sh refuses elsewhere). -->
8. **Stop** and present merge-request readiness and the MR URL. Do not run `--approve release` yet. After the human merge has succeeded and explicit user approval of release completion, run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>` in the integration checkout, after it holds the merge (the script refuses on any other branch; never on the feature branch), then update that phase-result file to `status: approved`.
9. When `docs/agents-v0/project-profile.md` defines a **Deploy** table, follow `release-deploy` after the human merge, requiring explicit authorization, smoke check, and rollback readiness per environment.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt-pr-review.mdc`, `project-delivery-core.mdc`, `code-review.mdc`.
