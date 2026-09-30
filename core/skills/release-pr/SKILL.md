---
name: release-pr
description: Release phase playbook. Open the MR (glab/GitLab) or PR (gh/GitHub) with the VAPT sign-off template; run the CI fix loop.
---

# release-pr

Release phase playbook for the `release-manager` agent (`workflow-orchestration.mdc`).

## Steps
1. Confirm Release gate inputs: docs synced, Verify gate passed (no Critical findings).
2. Open the merge request/PR only when explicitly requested; commit/push need separate authorization. **GitLab (default):** `glab mr create` with `.gitlab/merge_request_templates/default.md`. **GitHub:** `gh pr create` with `.github/pull_request_template.md`. After the user authorizes git write, run the command and approve the IDE `beforeShellExecution` prompt from `pre-shell.sh` — never use env-var or command-prefix bypasses.
3. Fill the MR/PR title/link, reviewer, date, and sign-off rows (include `Feature-Artifact:` for delivery linkage).
4. Run the **CI fix loop**:
   - Read failing checks (`glab ci status` / pipeline jobs, or `gh pr checks` on GitHub).
   - On GitLab, the live approver match is the manual `delivery-approval` job. Run it after the MR is approved. `GITLAB_TOKEN` is `read_api`, masked, and scoped to the `delivery-approval` environment. The job accepts the release or verify approver.
   - Route fixes to the responsible agent (backend/bff/frontend/test).
   - Re-run; bounded retries; escalate to the user on repeated failure.
5. Publish a status report (use the Atlassian `generate-status-report` skill if connected).
6. Do not commit, push, force-push, or hard reset without explicit user approval.
7. Report merge-request readiness with CI green and stop for an authorized human merge; confirm the merge and CI green before reporting Release complete.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: no commits/force-push without approval; MR via `glab` or PR via `gh`.
- [ ] `vapt-pr-review.mdc`: merge request template with VAPT sign-off; any applicable unchecked item flagged Critical.
- [ ] `project-delivery-core.mdc`: docs synced.
- [ ] `code-review.mdc`: no Critical findings before merge.
- [ ] `workflow-orchestration.mdc`: merge-request readiness is not Release completion; the merge and CI green are confirmed before done.
