---
name: local-release
description: Primary local release after Verify. Guard-enforced via guard-local-release.sh: re-run the native verify command, collect proposed lessons, pause for the user's external approval, squash-merge a feature branch (--no-ff for a maintenance branch), append accepted lessons, and record the release approved.
---

# local-release

Primary local completion for `/v0-local-release` (`workflow-orchestration.mdc`) and the shell-less `release-manager` subagent. All shell commands and state mutations run in the main session via `sh .agents-v0/scripts/guard-local-release.sh`.

## Steps
1. **Check & Start (main session):**
   - Run `sh .agents-v0/scripts/guard-local-release.sh check <feature>` (append `--maintain` for a maintenance note) to verify `feature/<feature>` (or `maintain/<id>`), no collision, `not-released`, and `verify-approved` (`"verifyPassed": true`, `"verify"` in `approvedPhases`, external verify approval record, and committed Verify gate; or `tier: "emergency"` maintenance note with rollback plan and `Follow-up verify due`).
   - Run `sh .agents-v0/scripts/guard-local-release.sh start <feature>` (or `--maintain`). If non-doc files changed since Verify approval, `start` automatically reopens `verify` (`verifyPassed: false`), increments `reopenCount`, and exits 1 so the story routes back to `/v0-verify <feature>`.
2. **Release Preparation & Final Native Stack Check:**
   - When `CHANGELOG.md` is used by the profile, the main session updates it via `sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/<feature>.md --include-unreleased --insert CHANGELOG.md`.
   - The main session resolves the final native verify command (`sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`), runs it into `docs/agents-v0/release/<feature>/release-output.txt`, and verifies tests ran (`sh .agents-v0/scripts/check-tests-ran.sh docs/agents-v0/release/<feature>/release-output.txt`). If the tree is not green, run `sh .agents-v0/scripts/guard-local-release.sh block <feature> "<reason>"` and stop.
<!-- MEM-06: lesson candidates become proposed lessons at this gate; the user decides each one; accepted ones are appended to docs/agents-v0/lessons.md in the integration checkout after the merge. -->
3. **Docs Sync & Proposed Lessons (`release-manager` subagent, no shell):**
   - Sync `README.md` or sequence diagrams (`docs/agents-v0/diagrams/`) when the feature changed user-facing setup or flows.
   - In `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`), add at most 3 `### release` candidates under `## Lessons`, then collect every candidate into `## Proposed lessons` as `- P-<n> · pending · <phase> · Trigger: … · What happened: … · Do instead: … · Scope: …` (or `- none`), dropping exact duplicates of active entries in `docs/agents-v0/lessons.md`.
4. **Ready Gate & External Approval (main session + the user's external terminal):**
   - Run `sh .agents-v0/scripts/guard-local-release.sh ready <feature>`. This runs `check-lessons.sh --unchanged-since <integration-ref> --phase-result <phase-result>` before and after normalizing `## Proposed lessons`, scans for secrets, and sets `activePhase: "release"`, `activeStatus: "awaiting_approval"`.
   - **Stop** for explicit user approval. Present the release readiness summary and every `P-<n>` in `## Proposed lessons` so the user can accept or reject each one when running:
     `sh .agents-v0/scripts/guard-common.sh approve local-release <feature>`
     in an external terminal outside the IDE.
<!-- MEM-14: check-lessons.sh --approval-text compares the marks and lessons.md with the user's verbatim approval message. -->
<!-- kitfix-20261029-step4-p1e: after the merge, no commit or state change on the story branch; check it is fully merged; list every commit. -->
<!-- kitfix-20261031-keep-branches -->
5. **Two-Step Release Commit & Squash Merge (main session, after the user's approval):**
   - Run `sh .agents-v0/scripts/guard-local-release.sh commit <feature>` (or `--maintain`).
   - It verifies the user's external approval record (`local-release-<feature>.json`), commits the release preparation on `feature/<feature>` (`<story>: release approved`), switches to the integration worktree (`resolve-integration-branch.sh`), runs `git merge --squash feature/<feature>` (or `git merge --no-ff --no-commit maintain/<id>`), marks each `P-<n>` `accepted` or `rejected` from the user's verbatim approval words, appends accepted lessons to `docs/agents-v0/lessons.md` using `check-lessons.sh --next-id`, validates with `check-lessons.sh --decided` and `check-lessons.sh --phase-result <phase-result> --approval-text '<approval words>'`, runs `sync-feature-state.sh --approve release <artifact>`, commits the single squash commit (`<story>: release approved (squash-merge of feature/<feature>)` with `Story-Branch` and `Story-Tip` trailers), and verifies `check-release-evidence.sh <artifact>`.
   - Keep `feature/<feature>` and `maintain/<id>` branches after release (never delete or rename them).
   - List every commit made in this turn (short SHA, branch, subject) across both worktrees.

## Do not
- Call `sync-feature-state.sh`, `git add -A`, `git commit`, or `git merge` directly; `guard-local-release.sh` owns all state transitions, staging, and merges.
- Commit to `feature/<feature>` or `maintain/<id>` after it is merged into the integration branch, or mark `release` approved on a story branch.
- Edit `docs/agents-v0/lessons.md` on a feature or maintain branch, or append a lesson the user did not accept.
- Delete or rename `feature/<feature>` or `maintain/<id>` branches.
