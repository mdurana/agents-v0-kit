---
name: release-pr
description: Release phase playbook. Dry-run the delivery gate locally, render the merge-request description from the evidence, open it with glab, run a bounded CI fix loop, and stop for the human merge.
---

# release-pr

Release phase playbook for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-release`).

## Steps
1. Confirm Release gate inputs: README and sequence diagrams synced, and the changelog entry added when the profile names a changelog (`sh .agents-v0/scripts/release-notes.sh <artifact> --include-unreleased --insert CHANGELOG.md`). Step 2 holds the Verify check, including `P0-A` and a maintenance note with `tier: "emergency"`. Do not edit `docs/agents-v0/architecture.md` or `docs/agents-v0/network.md` in this merge. Those stay on the docs-only follow-up (`doc-sync`).
2. **Evidence and MR body.** Confirm `"verifyPassed": true` and `"verify"` is in `approvedPhases` (or for `P0-A`, `verifyPassed` is `true` and the user is approving the single P0-A release gate now). A maintenance note with `tier: "emergency"` may proceed when `maintain` is approved and the note records a rollback plan and `Follow-up verify due`. If neither exception applies and Verify has not passed, stop and run `/v0-verify` first. If non-doc files changed after Verify was approved, send the change back through Verify (`sh .agents-v0/scripts/sync-feature-state.sh --reopen verify --verify-passed false <artifact>`). Render the merge-request description with `sh .agents-v0/scripts/render-mr-body.sh <feature> --base origin/<default-branch> > <body-file>` (or `sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/<id>/note.md --base origin/<default-branch> > <body-file>`).
3. If `git remote get-url origin` fails or `glab` is not on `PATH`, set the phase `blocked` (reason "no origin" or "glab missing") and do not record `release` approval. Otherwise, when the merge request is explicitly requested, give the user the exact `git push` and `glab mr create --description "$(cat <body-file>)"` commands to run in their own terminal: the hook refuses push and every `gh` or `glab` write in every mode, and commit needs its own authorization. Never use env-var or command-prefix bypasses. Do not record the `release` approval when this command returns a merge-request URL.
4. Run the **CI fix loop**, at most three rounds (prompt-only):
   - Read failing checks (`glab ci status` / pipeline jobs).
   - Route fixes to the responsible agent (backend/bff/frontend/test). A code fix re-enters Verify.
   - Ask the user to push the fix from their own terminal; re-run. After three rounds record `blocked` and escalate to the user.
5. When the merge request is open and CI is green, write `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md`) with `phase: release`, `status: awaiting_approval`, and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase release --status awaiting_approval <artifact>`. Publish that status in the phase result and the merge-request description. Stop for the human merge. Do not run `--approve release`.
6. Never merge or approve the merge request, do not commit or hard reset without explicit user approval, and never push (the hook refuses it; the user pushes). The version and the tag belong to the release owner; propose the semantic version from the change.
<!-- kitfix-20261029-step4-p1e: --approve release runs only on the integration branch (sync-feature-state.sh refuses elsewhere). -->
7. After the human merge has succeeded and the user confirms release completion, run `sh .agents-v0/scripts/sync-feature-state.sh --approve release <artifact>` in the integration checkout, after it holds the merge (the script refuses on any other branch; never on the feature branch), then update that phase-result file to `status: approved`. Optionally append the `release` row with the merge-request URL. Deployment records, if any, go through `release-deploy`.
8. Optional compliance archive: after that approval, run `sh .agents-v0/scripts/export-audit-pack.sh <feature-or-id>` and attach `docs/agents-v0/release/<feature-or-id>/audit-manifest.json` to the release record (regulated environments).

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: no commits without approval; no push and no `glab` write by an agent (the user runs them); no merge, no approval by an agent.
- [ ] `vapt-pr-review.mdc`: merge request template with VAPT sign-off. An applicable miss on F4, F8, F9, or F10 is Critical. HIGH and MEDIUM regression findings block merge when the diff touches that surface.
- [ ] `project-delivery-core.mdc`: docs synced.
- [ ] `code-review.mdc`: no Critical findings before merge.
- [ ] `verifyPassed: true` confirmed before the push, except a maintenance note with `tier: "emergency"` when `maintain` is approved and the note records a rollback plan and `Follow-up verify due`; the CI fix loop stayed within three rounds (prompt-only).
- [ ] `release` recorded in `<feature>.state.json` only after the human merge and the user's confirmation.
- [ ] `workflow-orchestration.mdc`: merge-request readiness is not Release completion; the merge and CI green are confirmed before done.
