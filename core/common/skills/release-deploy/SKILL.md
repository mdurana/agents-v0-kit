---
name: release-deploy
description: Release phase playbook. Promote a merged change through the Deploy rows of the project profile, with a smoke check, a rollback, and feature flags for risky changes.
---

# release-deploy

Release phase playbook for the `release-manager` agent (`workflow-orchestration.mdc`). Use it after the authorized merge, and only when `docs/agents-v0/project-profile.md` has a **Deploy** table. A project with no Deploy rows stops at the merge, as `release-pr` says.

## Steps
1. Read the **Deploy** table in `docs/agents-v0/project-profile.md`: one row per environment, in promotion order, with the deploy command, the smoke check, and the rollback command. A missing smoke check or rollback command is a blocker; do not guess one.
2. Confirm the merged commit: CI is green on the default branch and the image or artifact tag names that commit. When `docs/agents-v0/design/system/ops-readiness.md` exists, a production deploy waits until each checklist box is ticked or names a reason.
3. For each environment, in table order:
   - Ask the user to authorize deploying to that environment. One authorization covers one environment. Hooks ask before publish and deploy commands; do not bypass them.
   - Run the row's deploy command, then its smoke check. Save the command, exit code, and output summary to `docs/agents-v0/release/<feature>/deploy-<environment>.md` (start with `commit:`) in the working tree, or in the release issue. No secrets in the file. The merge is done and the default branch takes no direct commit: commit these records only in a separate docs-only follow-up merge request, which needs its own authorization.
   - On a failed smoke check, run the rollback command, save that output too, and stop. Do not promote to the next environment.
4. A change that touches a migration, an auth model, or a public route ships behind a feature flag that is off by default, or as an expand/contract migration (`migration-safety`). Record the flag name, its default, and who turns it on in the deploy record.
5. Rollback rehearsal: before the first production deploy of a service, confirm the rollback command ran successfully once in a lower environment. Record the date.
6. Report: environments deployed, smoke results, flags, rollback status. Release is complete for a deployable project only after the last environment's smoke check passes.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: no deploy, publish, or push without explicit user approval; no force-push or hard reset.
- [ ] `migration-safety`: expand/contract for schema changes; rollback notes recorded.
- [ ] `security-baseline.mdc`: no secrets in deploy records.
- [ ] Each environment has its own authorization, smoke result, and rollback command on record.
- [ ] `workflow-orchestration.mdc`: Release gate met; completion is reported only after the merge and the last smoke check.
