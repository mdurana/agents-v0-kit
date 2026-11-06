---
description: Trivial lane — a docs-only or 1-for-1 patch version bump confirmed by the user, routed through /v0-maintain with abbreviated Verify.
---

# /v0-triage

Use `/v0-triage` for changes that qualify for the **Trivial** tier (`workflow-orchestration.mdc` Change Tiers).

## What qualifies
- Documentation-only edits, or 1-for-1 patch version bumps in dependency manifests/lockfiles.
- Zero changes to security surfaces (controllers, authentication, authorization, sessions, uploads, CORS, security/deployment config), database schemas/migrations, or API/event contracts.

## Instructions
1. Inspect `git diff` (or the requested change scope) against the qualification criteria above.
2. **If not eligible:** Explain why (e.g., touches application logic, auth, or schema) and route to `/v0-maintain` (`Tier: standard`) or `/v0-intake`.
3. **If eligible:** Ask for `<id>` when the user did not name one (`workflow-orchestration.mdc` Parallel Features). Do not create the note until `<id>` is named. Once `<id>` is named, run `sh .agents-v0/scripts/guard-maintain.sh check <id> --tier trivial` and `sh .agents-v0/scripts/guard-maintain.sh start <id> --tier trivial` (which stays on the integration branch, seeds `docs/agents-v0/maintain/<id>/note.md` with `Tier: trivial` and `docs/agents-v0/build/<id>/build-report.md`, and sets `state.json` to `in_progress` with `maintainGuardManaged: true`), and ask the user to confirm the `trivial` tier in chat.
4. Once the user confirms, record `Tier confirmed by` in `docs/agents-v0/maintain/<id>/note.md`. That confirmation is not external maintain approval (`guard-common.sh approve maintain <id>`). Launch shell-less `maintenance-engineer`: a documentation edit follows `doc-sync`, and a 1-for-1 patch version bump follows `dependency-upgrade`. Then follow `/v0-maintain`: run `sh .agents-v0/scripts/guard-maintain.sh ready <id>` (which validates `Tier confirmed by`, enforces the docs/lockfile-only scope rule, writes `docs/agents-v0/maintain/<id>/phase-result.md`, and sets `awaiting_approval`), stop for Sensei's external approval (`sh .agents-v0/scripts/guard-common.sh approve maintain <id>`), and run `sh .agents-v0/scripts/guard-maintain.sh commit <id>`. Next is `/v0-verify <id> --maintain` (Abbreviated Verify: the stack's native build/test command, without `security-reviewer` or `code-reviewer`), then `/v0-local-release <id> --maintain`.
