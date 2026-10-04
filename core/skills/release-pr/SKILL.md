---
name: release-pr
description: Release phase playbook. Dry-run the delivery gate locally, render the merge-request description from the evidence, open it with glab, run a bounded CI fix loop, and stop for the human merge.
---

# release-pr

Release phase playbook for the `release-manager` agent (`workflow-orchestration.mdc`, `/v0-release`).

## Steps
1. Confirm Release gate inputs: docs synced, Verify gate passed (no Critical findings), the changelog entry added when the profile names a changelog (`sh .agents-v0/scripts/release-notes.sh docs/agents-v0/requirements/<feature>.md --include-unreleased --insert CHANGELOG.md`).
2. **Evidence, then the dry run.** If code changed after the reports' `commit:` lines, send it back through Verify. Do not re-stamp a report to make it pass. When the reports are not yet committed, use this order, each git write with its own authorization: commit the code, write the reports with `commit:` set to that SHA, commit the reports. Then run `sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> --base origin/<default-branch>`. It renders the description (`Feature-Artifact:`, VAPT rows, commit stamps, reviewer checkboxes left unticked) and runs linkage, design contracts, the build plan, and endpoint authorization. A maintenance note uses `sh .agents-v0/scripts/render-mr-body.sh --note docs/agents-v0/maintain/<id>/note.md --base origin/<default-branch>` and `CHECK_MR_APPROVER=0 sh .agents-v0/ci/check-delivery-linkage.sh`. Fix what the checks report.
3. If `git remote get-url origin` fails or `glab` is not on `PATH`, set the phase `blocked` (reason "no origin" or "glab missing") and do not write an `Approved` release row. Otherwise open the merge request only when explicitly requested; commit/push need separate authorization. Run `glab mr create` with the rendered body (`--description "$(cat <body-file>)"`). After the user authorizes git write, run the command and approve the IDE `beforeShellExecution` prompt from `pre-shell.sh` — never use env-var or command-prefix bypasses. Do not record the `release` row until this command has returned a merge-request URL.
4. Run the **CI fix loop**, at most three rounds:
   - Read failing checks (`glab ci status` / pipeline jobs).
   - Route fixes to the responsible agent (backend/bff/frontend/test). A code fix re-enters Verify.
   - Push with its own authorization; re-run. After three rounds record `blocked` and escalate to the user.
5. **Release row.** Only after `glab mr create` has returned a URL. Ask for the **GitLab username** of the person who will approve the merge request and record it as the Approver. Put that URL in the Artifacts cell. CI matches the Approver to the real approval; a display name fails the final job. Do not write `Approved` when the URL is missing.
6. After a person approves the MR, the manual `delivery-approval` job is played by a person, or by you with the user's explicit authorization (`glab ci trigger delivery-approval`). `GITLAB_TOKEN` is `read_api`, masked, and scoped to the `delivery-approval` environment. The job accepts the release or verify approver.
7. Publish a status report in the phase result and the merge-request description.
8. Optional compliance archive: after Verify/Release approval, run `sh .agents-v0/scripts/export-audit-pack.sh <feature>` and attach `docs/agents-v0/release/<feature>/audit-manifest.json` to the release record (regulated environments).
9. Never merge or approve the merge request, and do not commit, push, force-push, or hard reset without explicit user approval. The version and the tag belong to the release owner; propose the semantic version from the change.
10. Report merge-request readiness with CI green and stop for an authorized human merge; confirm the merge and CI green before reporting the change released. Deployment records, if any, go through `release-deploy`.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: no commits/force-push without approval; MR via `glab` when requested; no merge, no approval by an agent.
- [ ] `vapt-pr-review.mdc`: merge request template with VAPT sign-off; any applicable unchecked item flagged Critical.
- [ ] `project-delivery-core.mdc`: docs synced.
- [ ] `code-review.mdc`: no Critical findings before merge.
- [ ] The local dry run of `ci/check-delivery-linkage.sh` passed before the push; the CI fix loop stayed within three rounds.
- [ ] The `release` row's Approver is the approving GitLab username.
- [ ] `workflow-orchestration.mdc`: merge-request readiness is not Release completion; the merge and CI green are confirmed before done.
