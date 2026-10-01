---
description: Build phase. Implement with red-green tests, wired quality gates, bounded fixes, and persisted build evidence.
---

# /build

You are entering the **Build** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Prerequisite
Before launching build agents, read `docs/requirements/<feature>.phase-result.md` when it exists. Confirm the Intake artifact records explicit Design approval and names the approved contract/ADR/diagram paths (and, for UI-affecting changes, the approved `docs/design/<feature>/ux-spec.md` plus the `docs/design/<feature>/mockups/` files that spec links). If the evidence is missing, run `sh scripts/sync-feature-state.sh <artifact> --active-phase build --status blocked --reason "<one line>"` when the artifact exists, then stop and report it; do not infer approval. Run `sh ci/check-design.sh <feature> --verify-lock`: the design must still match the one the user approved. If it does not, stop and follow `/design` Amending an approved design. On a brownfield repo also read the `docs/onboarding/modules/` document for each touched module.

## Resume
Run `sh scripts/sync-feature-state.sh <artifact> --active-phase build --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a red baseline or exhausted fix attempts, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves. If this phase's approval row says `Re-opened` (`/deliver`), the phase is open again: continue from the files, and set `Approved` only after the user approves the re-run.

## Collision
Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this feature's approved diff, run `sh scripts/sync-feature-state.sh <artifact> --active-phase build --status blocked --reason "<paths>"` and stop. Do not rewrite `docs/project-profile.md` from this feature.

## Instructions
1. **Baseline first:** run the full Backend verify or Frontend verify command from `docs/project-profile.md` **before any edit** (`Service verify` with the story's `Service root:` when the profile lists `Service roots`). If it fails, stop and report the pre-existing failure; never build on a broken baseline.
2. **Wire the quality gate before implementing** if the repo has not wired it (`maven/quality-plugins.xml`: JaCoCo/Checkstyle/SpotBugs/OWASP bound to `verify`; `maven/contract-conformance.xml`; `maven/archunit/LayerRulesTest.java`) — unwired tooling makes `mvn clean verify` compile-only.
3. Launch the build agents per the Design artifacts:
   - `backend-engineer` (skill: `implement-spring-service`) for Spring services.
   - `bff-engineer` (skill: `implement-bff`) for the BFF.
   - `frontend-engineer` (skill: `implement-frontend`) for SvelteKit/React, implementing the approved UX spec: per-screen state matrix, component default behavior, layout from the linked HTML mockups, and accessibility. The real API client lives in the app and calls only the OpenAPI operation named on each component row. Mockups stay static design artifacts.
4. When `docs/design/<feature>/openapi.yaml` exists, the contract-owning engineer merges that approved draft into the org catalog (`openapi/api-v1.yaml`, or the catalog path in the profile) before other implementation edits. Stop if that catalog is already modified by another feature. A story with no draft records N/A in the build report. Merge with `sh ci/check-openapi.sh merge docs/design/<feature>/openapi.yaml <catalog>` (it rewrites the catalog's formatting: review the diff) or by hand, then prove it: `sh ci/check-openapi.sh merged docs/design/<feature>/openapi.yaml <catalog>` must pass. In a vertical slice the backend merges the contract first, then the BFF, then the frontend; each re-runs its baseline.
5. Before the first implementation edit, write `docs/build/<feature>/plan.md`: one row per approved `AC-*` (AC, Status `pending`/`done`/`blocked`, Test). Mark a row `done` only after that unit's fast command is green, and name the test. Do not add, delete, or rewrite AC rows (`workflow-orchestration.mdc`).
6. Each agent works the plan red–green as its `implement-*` skill describes (step 6): failing test first, auth/upload/RBAC VAPT-required tests in the same diff, the fast verify loop, a command-result card per attempt in `docs/build/<feature>/build-report.md`, and `sh scripts/check-attempt-budget.sh` before each new attempt. When the budget is spent, run `sh scripts/sync-feature-state.sh <artifact> --active-phase build --status blocked --reason "attempt budget exhausted"` and stop.
   - Units the requirements artifact marks as security-review triggers (auth, RBAC, upload, public route) or that implement a saga or consumer (`implement-messaging`) run on the Plan-role model, not the Build-role model (`docs/model-routing-matrix.md` Critical units).
7. The second red result for the same test writes `docs/build/<feature>/failure-brief.md` (`helper: debug-investigator`) and returns. Launch `debug-investigator` from this session, pass the note back, and let the engineer take attempt three. A third red result stops. Launch each failure brief once.
7a. A flaw in the approved design (a missing operation, a wrong field, an authorization rule that cannot hold) is not fixed in place. Set the phase `blocked` (reason "design amendment") and follow `/design` Amending an approved design.
8. Each agent then runs the full verify command once (`mvn -B clean verify` when the profile's Backend verify row names it, or the full Frontend verify command) with **bounded fix attempts (≤ 3 per failure)**. On exhaustion, stop and present the blocker; hand security-critical or complex units to `solution-architect` for a design review instead of a further attempt. The fast loop does not replace this gate.
9. Check the **Build gate** (`workflow-orchestration.mdc`):
   - Baseline green on the full verify command; the gate run is that same full command, with the quality plugins executed (coverage/static/CVE fail machine-side). The fast command is only the red–green loop.
   - Approved feature draft merged into the org catalog (`ci/check-openapi.sh merged` passes), or N/A recorded.
   - Mechanical checks pass: `sh ci/check-build-plan.sh <feature> --complete` (every AC has a row; each done row names an existing test and has a red card first), `sh ci/check-endpoint-auth.sh <base>` (no new endpoint without a security annotation; `@PermitAll` marks a public one on purpose), `sh ci/check-frontend-calls.sh` (the frontend calls only catalog operations), and `sh ci/check-design.sh <feature> --verify-lock`.
   - New/changed behavior covered by tests; contract-conformance diff has no breaking change (or a recorded N/A reason); ArchUnit layer rules where wired.
   - Methods ≤ 30 lines; cognitive complexity ≤ 15.
   - Every endpoint has authentication + authorization (`@PreAuthorize` on admin/mutation).
   - Correlation ID and `traceparent` wired in.
   - DTOs only at the edge; Flyway migrations present, written with `migration-safety` (expand/contract, an up-migration test).
   - No secrets in code; log values sanitized.
   - UI changes implement the approved UX spec: per-screen state matrix, component defaults (including an override when one is recorded), layout matching the linked mockups, WCAG 2.1 AA a11y, design-system conformance. API integration uses the named OpenAPI operations. It does not add endpoints the contract does not list.
10. Commit the work first, with explicit user authorization, so the stamped SHA contains it: a stamp for an earlier tree is stale and `ci/check-evidence.sh` rejects it. Persist build evidence to `docs/build/<feature>/build-report.md` (include a `commit: <full-sha>` line for the tree tested; command, result, per-criterion **file:line citations**, and the attempt cards). Optional `build-output.txt` — prefer CI artifacts for raw logs (no secrets). Do not read that log back on the next attempt.
11. **Stop** and present the gate result to the user with the evidence citations (per criterion: file:line; per tool: command + result). Write `docs/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result). After explicit approval, append the Build decision (Decision: `Approved`), approver, date, changed-area summary, and the `docs/build/<feature>/` evidence paths to the Intake artifact's `Delivery approvals` section. Do not advance to Verify without that approval.

## Rules
`workflow-orchestration.mdc`, `java-spring-backend.mdc`, `frontend-web.mdc`, `vapt-spring.mdc`, `vapt-webapp.mdc`, `api-and-events.mdc`, `security-baseline.mdc`, `quality-and-testing.mdc`.
