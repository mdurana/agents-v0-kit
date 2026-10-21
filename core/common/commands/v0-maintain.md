---
description: Maintain phase. Bug fix, CVE or dependency upgrade, doc drift, refactor — recorded in a maintenance note with its own state.json and evidence; routes to Verify.
---

# /v0-maintain

You are entering the **Maintain** phase of the delivery lifecycle (`workflow-orchestration.mdc`). Every maintenance change has its own record (`docs/agents-v0/maintain/<id>/note.md`) and its own state file (`docs/agents-v0/maintain/<id>/state.json`).

## Resume
Choose `<id>` (issue key or lowercase slug). If `docs/agents-v0/maintain/<id>/state.json` has `release` in `approvedPhases`, stop. Do not set `in_progress`. Start a new `<id>`. Exception: `tier: "emergency"` and `verify` is not in `approvedPhases` → the next command is `/v0-verify <id>`, owed by `Follow-up verify due`. If `activeStatus` is `awaiting_approval`, stop and ask the user to approve `maintain`. Do not set `in_progress`. Otherwise copy `docs/agents-v0/maintain/_note.template.md` to `docs/agents-v0/maintain/<id>/note.md` when absent, then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status in_progress docs/agents-v0/maintain/<id>/note.md`. Continue from existing files on disk.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel Features). Stop if another feature's uncommitted changes are present.

## Instructions
1. **Tier & Acceptance:** If this change is documentation-only or a 1-for-1 patch version bump and the note has no `Tier confirmed by` line, stop. Suggest `/v0-triage`. Do not record `Tier: trivial` here first. Otherwise record `Type`, `Trigger`, `Tier` (`standard`, `trivial`, or `emergency`), and what "done" means in `docs/agents-v0/maintain/<id>/note.md` (for a bug: expected vs. actual and the reproducing test; for a CVE/upgrade: package versions from → to). Changes over 800 lines should use `/v0-intake`. After the tier is `standard` or `emergency`, ask the user to authorize the branch, then run `sh .agents-v0/scripts/feature-worktree.sh --maintain <id>`. The branch is `maintain/<id>`, cut from the integration branch. Do not reuse `feature/<feature>`. A reopened note whose `release` is not approved reuses `maintain/<id>`. A `trivial` note stays on the integration branch and does not get a worktree. Open the printed folder before editing.
2. **Baseline check:** Resolve the command with `sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`, then execute the printed command before editing. The script only prints. If it prints nothing, use the layout default.
3. Launch the `maintenance-engineer` subagent (using the `plan` model from `.cursor/model-config.json` when touching auth, RBAC, uploads, public routes, or sagas/consumers):
   - Bug fix → `bugfix-triage` (write the failing reproduction test first, then the minimal fix).
   - Dependency/CVE upgrade → `dependency-upgrade`.
   - Documentation sync → `doc-sync` (when `docs/agents-v0/onboarding/report.md` exists, re-verify citations with `sh .agents-v0/scripts/check-onboarding-docs.sh`).
   - Brownfield refactor without behavior change → `characterization-tests`.
   - Schema/migration change → `migration-safety`.
4. **Helpers & Attempt Budget:**
   - If `docs/agents-v0/maintain/<id>/helper-brief.md` exists, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/maintain/<id>/note.md` to check for duplicate brief loops, run the helper (`explore-researcher`, `debug-investigator`, or `docs-author`), pass the result back, and delete the brief.
   - Log each verify attempt in `docs/agents-v0/build/<id>/build-report.md` and check `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<id>/build-report.md` before each retry.
   - Run the full native verify command once the fix is green.
5. Write `docs/agents-v0/maintain/<id>/phase-result.md` (`phase: maintain`, `status: awaiting_approval`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase maintain --status awaiting_approval docs/agents-v0/maintain/<id>/note.md`.
6. **Stop** and present the fix and `build-report.md` to the user. After explicit user approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve maintain docs/agents-v0/maintain/<id>/note.md`. When `Tier: emergency` and the note records a rollback plan and `Follow-up verify due`, proceed to `/v0-local-release` or `/v0-release`. Full `/v0-verify <id>` is owed by that date, including the VAPT reviewers when the diff touches a security surface. Every other tier proceeds to `/v0-verify <id>`.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt.mdc`, `vapt-webapp.mdc`, `security-baseline.mdc` §9, `quality-and-testing.mdc`, `architecture-and-diagrams.mdc`.
