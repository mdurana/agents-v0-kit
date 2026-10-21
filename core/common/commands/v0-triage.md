---
description: Trivial lane — a docs-only or 1-for-1 patch version bump confirmed by the user, routed through /v0-maintain with abbreviated Verify.
---

# /v0-triage

Use `/v0-triage` for changes that qualify for the **Trivial** tier (`workflow-orchestration.mdc` Change tiers).

## What qualifies
- Documentation-only edits, or 1-for-1 patch version bumps in dependency manifests/lockfiles.
- Zero changes to security surfaces (controllers, authentication, authorization, sessions, uploads, CORS, security/deployment config), database schemas/migrations, or API/event contracts.
- Small scope ($\le 10$ files and $\le 200$ changed lines).

## Instructions
1. Inspect `git diff` (or the requested change scope) against the qualification criteria above.
2. **If not eligible:** Explain why (e.g., touches application logic, auth, or schema) and route to `/v0-maintain` (`Tier: standard`) or `/v0-intake`.
3. **If eligible:** Create `docs/agents-v0/maintain/<id>/note.md` with `Tier: trivial`, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status awaiting_approval docs/agents-v0/maintain/<id>/note.md`, and ask the user to confirm the `trivial` tier in chat.
4. Once the user confirms, record `Tier confirmed by` in the note, complete `/v0-maintain` with the minimal diff, and run `/v0-verify <id>` (Abbreviated Verify: runs the stack's native build/test command without launching `security-reviewer` or `code-reviewer`), followed by `/v0-local-release` (or `/v0-release`).
