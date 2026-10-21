---
description: Build phase. Implement with red-green tests, wired quality gates, bounded fixes, and persisted build evidence.
---

# /v0-build

You are entering the **Build** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
1. On Intel macOS, run `sh .agents-v0/scripts/host-tools-macports.sh` before the baseline (exit 2 means a required host tool is missing; stop and ask the user before `--install`).
2. Read `docs/agents-v0/project-profile.md` and confirm `Pack` names a complete pack under `.agents-v0/packs/<id>/pack.json`.
3. Read `docs/agents-v0/requirements/<feature>.state.json` (and `<feature>.phase-result.md` when present):
   - For `Story: P0-A` (`Milestone: P0`), if `docs/agents-v0/requirements/p0-a-platform-skeleton.md` does not exist yet, create it from `docs/agents-v0/milestones/p0-platform-skeleton.md` (`AC-1` through `AC-4`) along with a minimal `N/A` `docs/agents-v0/design/p0-a-platform-skeleton/design.md`.
   - For all other stories, confirm `design` is in `approvedPhases` in `<feature>.state.json` (or `Delivery approvals` records an `Approved` Design row), or `docs/agents-v0/design/<feature>/design.md` records `N/A: no /api/v1 operation` and `N/A: no event contract` and does not say `Material: yes` (`Contract: None`; `--approve build` backfills `design`). If neither is true, mark `--active-phase build --status blocked --reason "Design not approved"` and stop.
   - Milestone story: every story ID in this story's Dependency column in `docs/agents-v0/milestones/<milestone>.md` must have `verify` in `approvedPhases` and `verifyPassed: true`. If one does not, mark `--active-phase build --status blocked --reason "Dependency <id> not verified"` and stop.
4. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status in_progress docs/agents-v0/requirements/<feature>.md`. Continue from existing files on disk (`docs/agents-v0/build/<feature>/plan.md` and `build-report.md`). If Build was re-opened from Verify, read the Critical findings in `docs/agents-v0/requirements/<feature>.phase-result.md` and `docs/agents-v0/verify/<feature>/`, reset affected `AC-*` rows in `plan.md` to `pending`, and write failing reproduction/assertion tests before applying the fix.

## Collision
Before editing shared files or source code, check `git status` (`workflow-orchestration.mdc` Parallel Features). Stop if another feature's uncommitted changes are present.

## Instructions
1. **Baseline check:** Unless the working tree is clean at the default branch tip (or this story is `P0-A`), run the bound pack's verify command (`sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` or `"Frontend verify"`) before editing. If the baseline is broken outside `known_failures`, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status blocked --reason "Baseline broken outside known_failures" docs/agents-v0/requirements/<feature>.md` and stop.
2. **Build plan (`plan.md`):** Before the first implementation edit, write `docs/agents-v0/build/<feature>/plan.md` with one row per approved `AC-*` (`AC`, `Status` `pending`/`done`/`blocked`, `Test`, `Risk` `standard`/`critical`).
3. **Contract catalog merge:** When `docs/agents-v0/design/<feature>/openapi.yaml` exists, merge the approved operations and schemas into the repo catalog (`openapi/api-v1.yaml` or `openapi/<service>-v1.yaml`).
4. **Execute implementation units (`implement-*` skills):**
   - Launch the engineer subagent matching each unit's surface: `backend-engineer` (`implement-service`), `bff-engineer` (`implement-bff`), or `frontend-engineer` (`implement-frontend`).
   - **Critical-unit model routing:** For units touching authentication, authorization, uploads, public routes, cryptography, ledger/money, or message consumers/sagas (`implement-messaging`), use the `plan` model from `.cursor/model-config.json` (`docs/agents-v0/model-routing-matrix.md` Critical units).
   - Follow strict **red-to-green TDD**: write the failing test first, run the profile's fast verify command, log the attempt card in `docs/agents-v0/build/<feature>/build-report.md`, implement the minimal code to pass, and mark the `plan.md` row `done` with the test name.
5. **Bounded failure & debug loop:**
   - Before each new attempt, run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md` (max 8 failed attempts). If it exits 1, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status blocked --reason "Attempt budget spent" docs/agents-v0/requirements/<feature>.md` and stop.
   - If the same test fails twice consecutively, write `docs/agents-v0/build/<feature>/failure-brief.md` (`helper: debug-investigator`, `return:`, `ask:`, the failing test name, and a `file:line`), run `debug-investigator` from this session, verify with `sh .agents-v0/scripts/check-failure-brief.sh <feature>`, and allow one final attempt. A third consecutive failure stops Build (prompt-only; `check-failure-brief.sh` does not count it). Record `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status blocked --reason "Third consecutive failure" docs/agents-v0/requirements/<feature>.md` and stop.
   - If implementation reveals a flaw in the approved design, stop and follow `/v0-design` (Amending an Approved Design).
6. **Full native verify gate:** Run the bound pack's full verify command (`sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"` and/or `"Frontend verify"`). Confirm:
   - All tests pass, coverage meets the project bar, and static/security checks wired into the pack build succeed.
   - Every endpoint has explicit authentication/authorization (or the pack's intentional public marker on public routes).
   - DTOs are used at API boundaries, migrations follow `migration-safety`, and no secrets or unsanitized log values exist.
   - Record the final verify command output summary and per-AC `file:line` citations in `docs/agents-v0/build/<feature>/build-report.md`, and the raw verify output in `docs/agents-v0/build/<feature>/build-output.txt`. Do not read `build-output.txt` on the next attempt. The full-verify fix cap is ≤ 3 attempts per failure (prompt-only).
7. **P0-A deferred gate:** When `/v0-deliver` runs `P0-A`, proceed directly to `/v0-verify` and skip steps 8 and 9. Do not run `--approve build`. The single human approval is at Release, and `--approve release` records the earlier phases.
8. **Standard Build gate stop:** Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`phase: build`, `status: awaiting_approval`) and run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase build --status awaiting_approval docs/agents-v0/requirements/<feature>.md`.
9. **Stop** and present the Build report and `file:line` citations to the user. After explicit user approval:
   - Update `<feature>.phase-result.md` to `status: approved`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --approve build docs/agents-v0/requirements/<feature>.md`.
   - Commit the changes only when the user authorizes `git commit`. Do not advance to `/v0-verify` without Build approval.

## Rules
`workflow-orchestration.mdc`, `backend.mdc`, `frontend-web.mdc`, `vapt.mdc`, `vapt-webapp.mdc`, `api-and-events.mdc`, `security-baseline.mdc`, `quality-and-testing.mdc`.
