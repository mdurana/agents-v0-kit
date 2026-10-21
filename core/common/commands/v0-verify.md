---
description: Verify phase. Run the native stack verify command, quality-gate test verification, VAPT security review, and code review.
---

# /v0-verify

You are entering the **Verify** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite & Resume
1. If `<feature>` or `<id>` was not given, follow the naming rule in `workflow-orchestration.mdc` Parallel Features. Do not set `in_progress` until it resolves. Read `docs/agents-v0/requirements/<feature>.state.json` (or `docs/agents-v0/maintain/<id>/state.json` when verifying a maintenance note; use `<id>` for `<feature>` and `docs/agents-v0/maintain/<id>/note.md` as `<artifact>`). A feature story with `release` in `approvedPhases` stops. Do not reopen it. A docs-only edit or a 1-for-1 patch bump starts at `/v0-triage`. Any other fix starts at `/v0-maintain`. A new feature starts at `/v0-intake` with a new slug. A maintenance note is a different record and is not this stop, except a note that already has `release` approved and is not an emergency note that still owes Verify: stop and start a new `<id>`. For a non-P0-A feature story, run `git worktree list` and look for branch `feature/<feature>`. For a standard or emergency maintenance note, look for `maintain/<id>`. If that worktree exists and this checkout is not it, stop. Open that folder and run `/v0-status <feature>` or `/v0-status <id>` there.
2. Confirm the producing phase is approved in `.state.json` (`build` in `approvedPhases` for a feature story, or `maintain` in `approvedPhases` for a maintenance note). `Story: P0-A` may enter Verify without `build` in `approvedPhases`. If missing for any other story, run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status blocked --reason "Build/Maintain not approved" <artifact>` and stop.
3. If `verify` is already in `approvedPhases`, stop and suggest `/v0-local-release`, unless non-doc files changed after Verify. In that case run `sh .agents-v0/scripts/sync-feature-state.sh --reopen verify --verify-passed false <artifact>` instead of `--active-phase verify --status in_progress`. Otherwise run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase verify --status in_progress <artifact>`.

## Collision
Check `git status` (`workflow-orchestration.mdc` Parallel Features). Stop if another feature's uncommitted changes are present.

## Instructions
1. **Quality Gate (`test-engineer`, skill: `quality-gate`):**
   - Resolve layout roots via `eval "$(sh .agents-v0/scripts/resolve-layout.sh)"`. Resolve the verify command with `sh .agents-v0/scripts/run-backend-verify.sh "Backend verify"`, `"Service verify"`, and/or `"Frontend verify"`, then execute the printed command. The script only prints. If it prints nothing, use the layout default.
   - Verify that every `AC-*` in `docs/agents-v0/requirements/<feature>.md` (or Acceptance in `docs/agents-v0/maintain/<id>/note.md` for a maintenance note), including negative and edge ACs, has a passing test, changed-line coverage meets `docs/agents-v0/quality-gates.md` (default $\ge 80\%$ changed lines; whole-module $\ge 80\%$ backend / $\ge 70\%$ frontend), and no unsuppressed HIGH/CRITICAL dependency vulnerabilities remain.
   - For UI changes, verify automated accessibility checks (axe-core) and UX acceptance criteria from `docs/agents-v0/design/<feature>/ux-spec.md`, writing `docs/agents-v0/verify/<feature>/ux-report.md`.
   - For integration stories, vertical slices, P2 journeys, or P4 stories, follow `e2e-perf-testing` (`docs/agents-v0/verify/<feature>/e2e-report.md`) and `slo-evidence` (`docs/agents-v0/design/system/slo-evidence.md`) when applicable.
   - Write `docs/agents-v0/verify/<feature>/quality-gate.md` summarizing test execution, coverage, and AC traceability.
   - When `docs/agents-v0/verify/<feature>/helper-brief.md` exists, launch `schema-author` from this session and delete the brief. The phase agent already synced the primary artifact.
2. **Abbreviated Verify (`P0-A` or `Tier: trivial`):**
   - When the story is `P0-A` or a maintenance note with `tier: "trivial"`, skip step 3 (`security-reviewer` and `code-reviewer`) once `test-engineer` and the native verify command pass.
   - A maintenance note with `tier: "emergency"` is full Verify, owed by the note's `Follow-up verify due` date, and is not this shortcut.
3. **Role-Separated Security & Code Review (`security-reviewer` + `code-reviewer`):**
   - Launch `security-reviewer` (skill: `vapt-review`) and `code-reviewer` (skill: `pr-review`) against `git diff <baseCommit>...HEAD` (using `baseCommit` from `.state.json`), `docs/agents-v0/requirements/<feature>.md` (or `docs/agents-v0/maintain/<id>/note.md` for a maintenance note), and `design/<feature>/` when that directory exists. A maintenance note may have no design directory; that absence is not a failed Verify. (In single-agent IDEs, execute `vapt-review` and `pr-review` sequentially.)
   - `security-reviewer` checks always-on VAPT controls (`F4` access control, `F8` same-role `{id}` access → 403 or 404, `F9` JWT `alg`/`iss`/`aud`/`exp` with a fail-closed blacklist, `F10` audit events without a token) plus surface-specific findings and writes `docs/agents-v0/verify/<feature>/vapt-checklist.md`.
   - `code-reviewer` checks `code-review.mdc` and stack pack rules, labeling findings `Critical`, `Suggestion`, or `Nice to have`, and writes `docs/agents-v0/verify/<feature>/code-review.md`.
4. **Evaluate Verdict:**
   - Gather any `Critical` findings across `quality-gate.md`, `vapt-checklist.md`, and `code-review.md` into `docs/agents-v0/requirements/<feature>.phase-result.md` (or `docs/agents-v0/maintain/<id>/phase-result.md` for a maintenance note).
   - **If any `Critical` finding exists:** Run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed false --reopen build <artifact>` (or `--reopen maintain` for a maintenance note) and route back to `/v0-build` (or `/v0-maintain`). If `sync-feature-state.sh` exits 2 (`reopenCount > 3`), stop and escalate to the user.
   - **If zero `Critical` findings exist and the story is not `P0-A`:** Write that phase-result file (`phase: verify`, `status: awaiting_approval`), then run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --active-phase verify --status awaiting_approval <artifact>`.
5. **P0-A deferred gate:** When the story is `P0-A` and Verify found no `Critical` finding, run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --active-phase release --status in_progress <artifact>` and proceed directly to Release (`/v0-local-release` or `/v0-release`). Skip step 6. Do not run `--approve verify`. The Release approval records the earlier phases.
6. **Stop** and present the Verify reports (`quality-gate.md`, `vapt-checklist.md`, `code-review.md`) to the user. After explicit user approval:
   - Update that phase-result file to `status: approved`.
   - Run `sh .agents-v0/scripts/sync-feature-state.sh --verify-passed true --approve verify <artifact>`.
   - Next command: `/v0-local-release` (primary local workflow) or `/v0-release` (optional remote MR workflow).

## Rules
`workflow-orchestration.mdc`, `quality-and-testing.mdc`, `vapt.mdc`, `vapt-webapp.mdc`, `vapt-pr-review.mdc`, `code-review.mdc`, `security-baseline.mdc`, `api-and-events.mdc`.
