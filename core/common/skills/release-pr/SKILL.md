---
name: release-pr
description: Release phase playbook. Dry-run the delivery gate locally, render the merge-request description from the evidence, open it with glab, run a bounded CI fix loop, and stop for the human merge.
---

# release-pr

Release phase playbook for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-release`).

## Steps
1. Confirm Release gate inputs: README and sequence diagrams synced, Verify gate passed (no Critical findings), the changelog entry added when the profile names a changelog (`sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/<feature>.md --include-unreleased --insert CHANGELOG.md`). Do not edit `docs/agents-v0/architecture.md` or `docs/agents-v0/network.md` in this merge. Those stay on the docs-only follow-up (`doc-sync`).
2. **Evidence and MR body.** Confirm `verifyPassed: true` in `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json` for a maintenance note). If non-doc files changed after Verify was approved, send the change back through Verify (`--reopen verify --verify-passed false`). Render the merge-request description with `sh .agents-v0/scripts/render-mr-body.sh <artifact> --base origin/<default-branch> > <body-file>` (or `sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/<id>/note.md --base origin/<default-branch> > <body-file>`).
3. If `git remote get-url origin` fails or `glab` is not on `PATH`, set the phase `blocked` (reason "no origin" or "glab missing") and do not record `release` approval. Otherwise open the merge request only when explicitly requested; commit/push need separate authorization. Run `glab mr create` with the rendered body (`--description "$(cat <body-file>)"`). After the user authorizes git write, run the command and approve the IDE `beforeShellExecution` prompt from `pre-shell.sh` — never use env-var or command-prefix bypasses. Do not record the `release` approval until this command has returned a merge-request URL.
4. Run the **CI fix loop**, at most three rounds:
   - Read failing checks (`glab ci status` / pipeline jobs).
   - Route fixes to the responsible agent (backend/bff/frontend/test). A code fix re-enters Verify.
   - Push with its own authorization; re-run. After three rounds record `blocked` and escalate to the user.
5. **Release approval.** Only after `glab mr create` has returned a URL and the user approves, run `sh .agents-v0/scripts/sync-feature-state.sh --approve release --clear-active <artifact>` and optionally append the `release` row with the merge-request URL.
6. Publish a status report in the phase result and the merge-request description.
7. Optional compliance archive: after Verify/Release approval, run `sh .agents-v0/scripts/export-audit-pack.sh <feature-or-id>` and attach `docs/agents-v0/release/<feature-or-id>/audit-manifest.json` to the release record (regulated environments).
8. Never merge or approve the merge request, and do not commit, push, force-push, or hard reset without explicit user approval. The version and the tag belong to the release owner; propose the semantic version from the change.
9. Report merge-request readiness with CI green and stop for an authorized human merge; confirm the merge and CI green before reporting the change released. Deployment records, if any, go through `release-deploy`.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: no commits/force-push without approval; MR via `glab` when requested; no merge, no approval by an agent.
- [ ] `vapt-pr-review.mdc`: merge request template with VAPT sign-off. An applicable miss on F4, F8, F9, or F10 is Critical. HIGH and MEDIUM regression findings block merge when the diff touches that surface.
- [ ] `project-delivery-core.mdc`: docs synced.
- [ ] `code-review.mdc`: no Critical findings before merge.
- [ ] `verifyPassed: true` confirmed before the push; the CI fix loop stayed within three rounds.
- [ ] `release` recorded in `<feature>.state.json` after human approval.
- [ ] `workflow-orchestration.mdc`: merge-request readiness is not Release completion; the merge and CI green are confirmed before done.
