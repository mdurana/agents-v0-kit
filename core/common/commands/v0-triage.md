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
3. **If eligible:** Ask for `<id>` when the user did not name one (`workflow-orchestration.mdc` Parallel Features). Do not create the note until the id is named. Then create `docs/agents-v0/maintain/<id>/note.md` with `Tier: trivial`, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status in_progress docs/agents-v0/maintain/<id>/note.md`, and ask the user to confirm the `trivial` tier in chat.
4. Once the user confirms, record `Tier confirmed by` in the note. That confirmation is not `--approve maintain`. Launch `maintenance-engineer`: a documentation edit follows `doc-sync`, and a 1-for-1 patch version bump follows `dependency-upgrade`. Then follow `/v0-maintain`. Its approval stop writes `docs/agents-v0/maintain/<id>/phase-result.md`, and `--approve maintain` is recorded only after the user approves that diff. Next is `/v0-verify <id>` (Abbreviated Verify: the stack's native build/test command, without `security-reviewer` or `code-reviewer`), then `/v0-local-release` (or `/v0-release`).
