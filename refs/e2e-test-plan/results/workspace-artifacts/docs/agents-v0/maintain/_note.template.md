# Maintenance note: <title>

> Copy to `docs/agents-v0/maintain/<id>/note.md`. `<id>` is the issue key or a slug (lowercase letters, digits, hyphens). The id is also the folder name for this change's evidence: `docs/agents-v0/build/<id>/build-report.md` (attempt cards), `docs/agents-v0/verify/<id>/`. Put the merge request line `Maintain-Note: docs/agents-v0/maintain/<id>/note.md` in the description.

Id: <id>
Tier: <trivial | standard | emergency>
Tier confirmed by: <name of the person who agreed to this tier, in chat> on <YYYY-MM-DD>
Type: <bug | cve | dependency | refactor | docs | migration>
Trigger: <issue, alert, or incident link>
Follow-up verify due: <YYYY-MM-DD; Tier emergency only, delete the line otherwise>

Tier rules (`workflow-orchestration.mdc` Change Tiers):
- **trivial** — docs only, or a 1-for-1 patch version bump in build files and lockfiles; no security surface, schema, major bump, or delivery artifact. Needs "Tier confirmed by". Verify is the abbreviated Verify.
- **standard** — any other fix or upgrade within `MAINTAIN_MAX_LINES` source lines (default 800). Full Verify. A larger change is a feature: use `/v0-intake`.
- **emergency** — a production incident. Needs "Tier confirmed by", a rollback below, and "Follow-up verify due". The change may merge before Verify; Verify is owed by that date.

## Scope

<!-- TEMPLATE: the files or areas this change touches and why. -->

## Acceptance

<!-- TEMPLATE: what "done" means, checkable.
  bug: expected versus actual, and the test that reproduces it. That test fails before the fix.
  cve: the CVE IDs that must be gone from the scan, and the scan command.
  dependency: each dependency from version -> to version, and the release notes you read.
-->

## Security surface

<!-- TEMPLATE: record whether any security surface (auth, sessions, routes, controllers, uploads, deployment security config), schema, or major bump is touched. A security surface means the full Verify with the VAPT checklist. -->

## Rollback

<!-- TEMPLATE: how to undo this change (revert commit, redeploy the previous artifact, feature flag, migration down). Required for emergency. -->

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
