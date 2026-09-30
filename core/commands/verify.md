---
description: Verify phase. Quality gate, VAPT review, and code review with persisted evidence.
---

# /verify

You are entering the **Verify** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching verification agents, confirm the change was explicitly approved by its producing phase: the linear path requires Build approval in the Intake artifact's `Delivery approvals`, and the `docs/build/<feature>/` evidence paths that row records must exist; a maintenance change requires the maintain approval recorded by `/maintain` (scope, evidence, approval to enter Verify). If evidence is missing, run `sh scripts/sync-feature-state.sh <artifact> --active-phase verify --status blocked --reason "<one line>"` when the artifact exists, then stop and report it; do not infer approval.

## Resume
Run `sh scripts/sync-feature-state.sh <artifact> --active-phase verify --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh scripts/sync-feature-state.sh <artifact> --active-phase verify --status blocked --reason "<paths>"` and stop.

## Instructions
0. Each Verify report must start with provenance headers: `commit: <full-sha>` (tree verified), `kit-version:` (from `.agents-kit-version` if present), `agent:` (role name). When Verify adds or changes tests, those changes must be committed (with explicit user authorization) before the reports are stamped; security and code review then run against that same commit.
1. Launch the `test-engineer` subagent (skill: `quality-gate`):
   - Write AAA tests; cover happy/error/edge paths.
   - Use Testcontainers + Pact where the repo already depends on them.
   - Run `mvn -B clean verify` / frontend script for changed code; confirm coverage ≥ 80% backend / 70% frontend.
   - Run OWASP Dependency-Check; no new high/critical CVEs without a documented exception.
   - For UI-affecting changes: run the automated accessibility check (axe-core) on changed routes of the built UI, not on the Design HTML mockups; confirm no serious/critical violations; cover each UX acceptance criterion from `docs/design/<feature>/ux-spec.md` with a test of the built UI; persist the UX report to `docs/verify/<feature>/ux-report.md` (violations with severity and file:line, UX acceptance criteria status).
   - Persist the test report to `docs/verify/<feature>/test-report.md` (build status, coverage numbers, CVE scan results, documented exceptions).
2. Launch the `security-reviewer` subagent (skill: `vapt-review`):
   - Run the VAPT F1–F7 checklist for the affected surface.
   - Mark any applicable unchecked item as **Critical**; mark a finding N/A only for an unaffected surface and record the reason.
   - Persist the checklist results to `docs/verify/<feature>/vapt-checklist.md` (finding ID, pass/fail/N/A + reason, evidence file:line, retest step).
3. Launch the `code-reviewer` subagent (skill: `pr-review`):
   - Apply the `code-review.mdc` checklist; label findings Critical/Suggestion/Nice to have.
   - Persist review notes to `docs/verify/<feature>/review-notes.md` (finding, label, file:line, rule clause).
4. Check the **Verify gate** (`workflow-orchestration.mdc`):
   - Quality: build green, coverage met for changed code, no new high/critical CVEs without a documented exception.
   - Security: applicable VAPT F1–F7 checks have no Critical findings; applicable checks cannot be waived as N/A.
   - UX: for UI-affecting changes, automated a11y check green (no serious/critical violations) and UX acceptance criteria covered; N/A only when the change has no UI surface, with the reason recorded.
   - Review: no Critical findings.
   - Evidence: the reports exist under `docs/verify/<feature>/`.
5. On any Critical finding, route back to the responsible Build/Maintain agent and re-enter Verify after the fix.
6. **Stop** and present the gate result to the user. After explicit approval, append the Verify decision (Decision: `Approved`), approver, date, the `docs/verify/<feature>/` report paths, and documented CVE exceptions as a new row in the delivery record's `Delivery approvals` table — the Intake artifact for the linear path, or the requirements artifact / linked issue/PR for a maintenance change. Do not advance to Release without that approval.

## Rules
`workflow-orchestration.mdc`, `quality-and-testing.mdc`, `vapt-spring.mdc`, `vapt-webapp.mdc`, `vapt-pr-review.mdc`, `code-review.mdc`, `security-baseline.mdc`, `api-and-events.mdc`.
