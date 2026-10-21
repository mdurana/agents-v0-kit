---
description: Optional remote release workflow via GitLab merge request (glab), CI fix loop, readiness report, and human-authorized merge.
---

# /v0-release

You are entering the **Remote Release** phase (`workflow-orchestration.mdc`). Teams releasing locally use `/v0-local-release`; use `/v0-release` when publishing a remote GitLab merge request (`glab`).

## Prerequisite & Resume
1. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json` for a maintenance change).
2. Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (unless `tier` is `emergency` with human confirmation). If missing, stop and run `/v0-verify` first.
3. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status in_progress <artifact>`.

## Instructions
1. Launch the `release-manager` subagent (skill: `release-pr`).
2. Sync `README.md`, sequence diagrams, and `CHANGELOG.md` (`sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md` when configured).
3. Render the merge-request description using `sh .agents-v0/scripts/render-mr-body.sh` (pass `--note docs/agents-v0/maintain/<id>/note.md` for a maintenance change).
4. Verify `git remote get-url origin` and `glab` availability. If no remote or `glab` is configured, recommend `/v0-local-release` instead, mark `--status blocked --reason "no origin or glab"`, and stop.
5. Ask for explicit user authorization before committing, pushing (`git push`), or creating the merge request (`glab mr create`). Never run `glab mr merge` or `glab mr approve` (permanently blocked by `pre-shell.sh`).
6. **CI fix loop (at most 3 rounds):** If remote CI reports a failure, route the fix to the responsible engineer agent, re-verify locally via `/v0-verify`, and push only with explicit user authorization. After 3 failed rounds, set `--status blocked --reason "CI fix loop exhausted"` and escalate to the user.
7. Write `<feature>.phase-result.md` (`phase: release`, `status: awaiting_approval`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`.
8. **Stop** and present merge-request readiness and the MR URL to the user. After explicit user approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>`.
9. When `docs/agents-v0/project-profile.md` defines a **Deploy** table, follow `release-deploy` after the human merge, requiring explicit authorization, smoke check, and rollback readiness per environment.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt-pr-review.mdc`, `project-delivery-core.mdc`, `code-review.mdc`.
