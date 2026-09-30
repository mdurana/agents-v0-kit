---
description: Release phase. Merge request via glab (GitLab default) or pull request via gh, CI fix loop, readiness report, human-authorized merge.
---

# /release

You are entering the **Release** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching the release manager, read `docs/requirements/<feature>.phase-result.md` when it exists. Confirm the Intake artifact records explicit Verify approval and names the test, VAPT, and review evidence. Confirm applicable VAPT and code-review findings have no Critical items. If evidence is missing, run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<one line>"` when the artifact exists, then stop and report it; do not infer approval.

## Resume
Run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When readiness is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh scripts/sync-feature-state.sh <artifact> --active-phase release --status blocked --reason "<paths>"` and stop. Doc updates that touch `README.md`, `docs/architecture.md`, or `docs/network.md` are shared-file edits.

## Instructions
1. Launch the `release-manager` subagent (skill: `release-pr`).
2. Confirm Release gate inputs:
   - Docs synced (README, architecture, network, sequence diagrams).
   - Merge request template complete (GitLab default), including the VAPT sign-off table. GitHub uses the pull request template.
3. Open the merge request only when explicitly requested by the user. **Default (on-prem GitLab):** `glab mr create` using `.gitlab/merge_request_templates/default.md` (set `Feature-Artifact:` in the description). **GitHub:** `gh pr create` using `.github/pull_request_template.md`. Obtain separate explicit authorization before committing or pushing. When the user approves, run the command and **approve the IDE shell prompt** from `pre-shell.sh` — do not set bypass env vars or prefixes on git commands. On GitLab, after a human approves the MR, run the manual `delivery-approval` job. `GITLAB_TOKEN` is a masked project access token with `read_api` scope, limited to the `delivery-approval` environment. That job matches the approver to an Approved release or verify row, using the ci scripts from the default branch.
4. Run the **CI fix loop**: read failing checks, route fixes to the responsible agent, re-run. Bounded retries; escalate to the user on repeated failure.
5. Publish a status report (org MCP/Confluence integration when configured — see `docs/mcp-baseline.md`).
6. Do not commit, push, force-push, or hard reset without explicit user approval.
7. Check **merge-request readiness**: docs and VAPT sign-off complete, merge request open, CI green. Write `docs/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result). After explicit approval, record the `release` row (Decision: `Approved`, approver, date, merge request link) in the Intake artifact **on the merge request branch, before merge**. Stop and report readiness; do not merge on behalf of the user without explicit authorization.
8. Completion is the authorized human merge itself — that merge (reviews, CI checks, merge commit) is the system of record. Confirm it is merged and CI on the default branch is green, and report the outcome; do not push a follow-up commit to the default branch just to record completion. If no merge request or merge authorization is available, report the blocked status instead.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt-pr-review.mdc`, `project-delivery-core.mdc`, `code-review.mdc`.
