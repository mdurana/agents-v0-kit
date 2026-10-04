---
description: Verify phase. Quality gate, VAPT review, and code review with persisted evidence.
---

# /v0-verify

You are entering the **Verify** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching verification agents, read `docs/agents-v0/requirements/<feature>.phase-result.md` when it exists. Confirm the change was explicitly approved by its producing phase: the linear path requires Build approval in the Intake artifact's `Delivery approvals`, and the `docs/agents-v0/build/<feature>/` evidence paths that row records must exist; a maintenance change (`docs/agents-v0/maintain/<id>/note.md`; use `<id>` wherever `<feature>` appears below, and the note as `<artifact>`) requires an `Approved` `maintain` row in the note. If evidence is missing, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase verify --status blocked --reason "<one line>"` when the artifact exists, then stop and report it; do not infer approval.

## Resume
Run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase verify --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves. If this phase's approval row says `Re-opened` (`/v0-deliver`), the phase is open again: continue from the files, and set `Approved` only after the user approves the re-run.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh .agents-v0/scripts/sync-feature-state.sh <artifact> --active-phase verify --status blocked --reason "<paths>"` and stop.

## Instructions
0. Each Verify report must start with provenance headers: `commit: <full-sha>` (tree verified), `kit-version:` (from `.agents-kit-version` if present), `agent:` (role name). When Verify adds or changes tests, commit those first (the hook asks). Stamp the reports with that SHA, then commit them with `git commit -m "<message>" -- docs/agents-v0/verify/<feature>`. That second commit does not ask again. Security and code review, when they run, use that same code commit.
1. Launch the `test-engineer` subagent (skill: `quality-gate`):
   - Write AAA tests; cover happy/error/edge paths.
   - Use Testcontainers + Pact where the repo already depends on them.
   - **Helpers.** If `docs/agents-v0/verify/<feature>/helper-brief.md` exists, launch the helper it names (`schema-author` unless the brief says otherwise) from this session. Pass the result into a second launch of `test-engineer`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
   - Run the full `mvn -B clean verify` / full frontend verify command for changed code; confirm coverage ≥ 80% backend / 70% frontend.
   - Run the machine checks CI runs, so a failure shows here and not after the push. For each Maven root set both flags together: `DIFF_BASE=origin/<default-branch> REQUIRE_CVE_REPORT=1 sh .agents-v0/ci/check-gate-metrics.sh <root>` (executed tests, diff coverage, and a present CVE report with no unsuppressed HIGH/CRITICAL). Omit both flags only when this story's Out of scope names a later story id in the same milestone whose user story wires coverage and CVE scanning, and that story has no Approved Verify row yet. The seeded P0 skeleton binds that gate in the same story, so it does not use this skip. The test report must quote that story id and say diff coverage and the CVE report were skipped until it. Any other story sets both flags. Also run `sh .agents-v0/ci/check-design.sh <feature> --verify-lock` and `sh .agents-v0/ci/check-build-plan.sh <feature> --complete` when the story has a design and a plan; `sh .agents-v0/ci/check-endpoint-auth.sh <base>` and `sh .agents-v0/ci/check-frontend-calls.sh`. Quote their results in the test report; the report does not replace them.
   - When this story is the P4 SLO story, or the requirements artifact cites `docs/agents-v0/design/system/nfr-slo.md`, follow `slo-evidence` and write `docs/agents-v0/design/system/slo-evidence.md`.
   - For an integration story, a vertical slice, a P2 journey, or a P4 story, follow `e2e-perf-testing` and persist `docs/agents-v0/verify/<feature>/e2e-report.md`.
   - Run OWASP Dependency-Check when `REQUIRE_CVE_REPORT=1` is set, so `dependency-check-report.json` exists for `check-gate-metrics.sh`. No new high/critical CVEs without a documented exception. When both metric flags are omitted under the quality-story deferral above, do not run the scan; the test report quotes the deferral instead.
   - For UI-affecting changes: run the automated accessibility check (axe-core) on changed routes of the built UI, not on the Design HTML mockups; confirm no serious/critical violations; cover each UX acceptance criterion from `docs/agents-v0/design/<feature>/ux-spec.md` with a test of the built UI; persist the UX report to `docs/agents-v0/verify/<feature>/ux-report.md` (violations with severity and file:line, UX acceptance criteria status).
   - Persist the test report to `docs/agents-v0/verify/<feature>/test-report.md` (build status, coverage numbers, CVE scan results, documented exceptions).
2. After the test engineer has finished and any helper brief is gone, launch `security-reviewer` (skill: `vapt-review`) and `code-reviewer` (skill: `pr-review`) together. Each writes only its own report. Wait for both before routing anywhere, including when one report already contains a Critical finding.
   - Security: VAPT F1–F7 for the affected surface. Any applicable unchecked item is **Critical**. N/A only for an unaffected surface, with the reason. Persist `docs/agents-v0/verify/<feature>/vapt-checklist.md` (finding ID, pass/fail/N/A + reason, evidence file:line, retest step).
   - Review: `code-review.mdc`, labels Critical/Suggestion/Nice to have. Persist `docs/agents-v0/verify/<feature>/review-notes.md` (finding, label, file:line, rule clause).
3. Gather one Critical list from both reports into `docs/agents-v0/requirements/<feature>.phase-result.md`.
4. Check the **Verify gate** (`workflow-orchestration.mdc`):
   - Quality: build green, coverage met for changed code, no new high/critical CVEs without a documented exception. P4 SLO story: `docs/agents-v0/design/system/slo-evidence.md` has a measurement or a waiver for every filled NFR/SLO row.
   - Security: applicable VAPT F1–F7 checks have no Critical findings; applicable checks cannot be waived as N/A.
   - UX: for UI-affecting changes, automated a11y check green (no serious/critical violations) and UX acceptance criteria covered; N/A only when the change has no UI surface, with the reason recorded.
   - Review: no Critical findings.
   - Evidence: the reports exist under `docs/agents-v0/verify/<feature>/`.
5. On any Critical finding in the gathered list, route back to the responsible Build/Maintain agent and re-enter Verify after the fix.
6. **Stop** and present the gate result to the user. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result) before stopping, including when status is `blocked`. After explicit approval, append the Verify decision (Decision: `Approved`), approver (the GitLab username of the person approving, for example `@ada`: CI may bind the merge request approval to this row), date, the `docs/agents-v0/verify/<feature>/` report paths, and documented CVE exceptions as a row in the delivery record's `Delivery approvals` table — the Intake artifact for the linear path, or the `verify` row of the maintenance note. Do not advance to Release without that approval.

## Abbreviated Verify (P0 skeleton)

When the requirements artifact contains `Story: P0-A` and `Milestone: P0`, only `test-engineer` runs (skill `quality-gate`): the full verify command, `ci/check-gate-metrics.sh` for each Maven root with both flags set, and `docs/agents-v0/verify/<feature>/test-report.md` with `commit:`. `security-reviewer`, `code-reviewer`, the UX audit, and `e2e-perf-testing` are skipped. The Verify approval is still required before Release. Release still waits for `glab mr create` to return a URL. Any other story uses the full Verify below.

## Abbreviated Verify (Tier trivial)
For a maintenance note with `Tier: trivial`, after `sh .agents-v0/ci/classify-change.sh <base> --require-trivial` passes, only `test-engineer` runs (skill `quality-gate`): the full verify command, `ci/check-gate-metrics.sh` for each changed Maven root, and a CVE re-scan for a dependency bump. Persist `docs/agents-v0/verify/<id>/test-report.md` with `commit:`. `security-reviewer`, `code-reviewer`, the UX audit, and `e2e-perf-testing` are skipped. The moment the classifier stops saying eligible, the abbreviated path ends: set `Tier: standard` (a person confirms) and run the full Verify. For `Tier: emergency`, this Verify is owed by the note's `Follow-up verify due` date; run the full Verify then.

## Rules
`workflow-orchestration.mdc`, `quality-and-testing.mdc`, `vapt-spring.mdc`, `vapt-webapp.mdc`, `vapt-pr-review.mdc`, `code-review.mdc`, `security-baseline.mdc`, `api-and-events.mdc`.
