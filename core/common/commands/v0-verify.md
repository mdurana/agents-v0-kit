---
description: Verify phase. Run the native stack verify command, quality-gate test verification, VAPT security review, and code review.
---

# /v0-verify

You are entering the **Verify** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
1. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json` when verifying a maintenance note; use `<id>` for `<feature>` and `docs/agents-v0/maintain/<id>/note.md` as `<artifact>`).
2. Confirm the producing phase is approved in `.state.json` (`build` in `approvedPhases` for a feature story, or `maintain` in `approvedPhases` for a maintenance note). If missing, mark `--active-phase verify --status blocked --reason "Build/Maintain not approved"` and stop.
3. Run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status in_progress <artifact>`.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel features). Stop if another feature's uncommitted changes are present.

## Instructions
1. **Quality Gate (`test-engineer`, skill: `quality-gate`):**
   - Resolve layout roots via `eval "$(sh .agents-v0/scripts/resolve-layout.sh)"` and run the bound pack's native verify command (`sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"`, `"Service verify"`, and/or `"Frontend verify"`).
   - Verify that every `AC-*` in `docs/agents-v0/requirements/<feature>.md` (including negative and edge ACs) has a passing test, changed-line coverage meets `docs/agents-v0/quality-gates.md` (default $\ge 80\%$ backend / $\ge 70\%$ frontend), and no unsuppressed HIGH/CRITICAL dependency vulnerabilities remain.
   - For UI changes, verify automated accessibility checks (axe-core) and UX acceptance criteria from `docs/agents-v0/design/<feature>/ux-spec.md`, writing `docs/agents-v0/verify/<feature>/ux-report.md`.
   - For integration stories, vertical slices, P2 journeys, or P4 stories, follow `e2e-perf-testing` (`docs/agents-v0/verify/<feature>/e2e-report.md`) and `slo-evidence` (`docs/agents-v0/design/system/slo-evidence.md`) when applicable.
   - Write `docs/agents-v0/verify/<feature>/quality-gate.md` (and `test-report.md` when needed for compatibility) summarizing test execution, coverage, and AC traceability.
2. **Abbreviated Verify (`P0-A` or `Tier: trivial`):**
   - When the story is `P0-A` or a maintenance note with `tier: "trivial"`, skip step 3 (`security-reviewer` and `code-reviewer`) once `test-engineer` and the native verify command pass.
3. **Role-Separated Security & Code Review (`security-reviewer` + `code-reviewer`):**
   - Launch `security-reviewer` (skill: `vapt-review`) and `code-reviewer` (skill: `pr-review`) against `git diff <baseCommit>...HEAD` (using `baseCommit` from `.state.json`), `requirements/<feature>.md`, and `design/<feature>/`. (In single-agent IDEs, execute `vapt-review` and `pr-review` sequentially.)
   - `security-reviewer` checks always-on VAPT controls (`F4` access control, `F8` error/log hygiene, `F9` secure defaults, `F10` input validation) plus surface-specific findings and writes `docs/agents-v0/verify/<feature>/vapt-checklist.md`.
   - `code-reviewer` checks `code-review.mdc` and stack pack rules, labeling findings `Critical`, `Suggestion`, or `Nice to have`, and writes `docs/agents-v0/verify/<feature>/code-review.md` (or `review-notes.md`).
4. **Evaluate Verdict:**
   - Gather any `Critical` findings across `quality-gate.md`, `vapt-checklist.md`, and `code-review.md` into `<feature>.phase-result.md`.
   - **If any `Critical` finding exists:** Run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed false --reopen build <artifact>` (or `--reopen maintain` for a maintenance note) and route back to `/v0-build` (or `/v0-maintain`). If `sync-feature-state.sh` exits 2 (`reopenCount > 3`), stop and escalate to the user.
   - **If zero `Critical` findings exist:** Run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --active-phase verify --status awaiting_approval <artifact>` and write `<feature>.phase-result.md` (`phase: verify`, `status: awaiting_approval`).
5. **P0-A deferred gate:** When `/v0-deliver` runs `P0-A`, run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --approve verify <artifact>` and proceed directly to Release (`/v0-local-release` or `/v0-release`) for the single human approval stop.
6. **Stop** and present the Verify reports (`quality-gate.md`, `vapt-checklist.md`, `code-review.md`) to the user. After explicit user approval:
   - Update `<feature>.phase-result.md` to `status: approved`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --approve verify <artifact>`.
   - Next command: `/v0-local-release` (primary local workflow) or `/v0-release` (optional remote MR workflow).

## Rules
`workflow-orchestration.mdc`, `quality-and-testing.mdc`, `vapt.mdc`, `vapt-webapp.mdc`, `vapt-pr-review.mdc`, `code-review.mdc`, `security-baseline.mdc`, `api-and-events.mdc`.
