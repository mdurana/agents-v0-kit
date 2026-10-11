---
name: quality-gate
description: Verify phase playbook. Run ./mvnw -B clean verify / frontend tests, check coverage and CVEs, write AAA tests.
---

# quality-gate

Verify phase playbook for the `test-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the changed files and existing tests.
2. Write tests: Arrange–Act–Assert; naming `methodName_scenario_expectedOutcome` (Java) or `should_expectation_whenCondition` (frontend) — match existing suite style.
3. Cover happy, error, and edge paths; every `@ExceptionHandler`/catch that changes behavior.
4. Use Testcontainers for integration (API+DB+messaging) and Pact for BFF↔service contracts where the repo already depends on them.
5. When a single-file unit test or mock data should be drafted by `schema-author`, write `docs/agents-v0/verify/<feature>/helper-brief.md` (`helper: schema-author`) and return. Do not launch the helper (`workflow-orchestration.mdc` Helper agents).
6. When `git rev-parse HEAD` equals the `commit:` line in `docs/agents-v0/build/<feature>/build-report.md` and this phase is not adding or changing tests, quote that build run. Do not run the full verify command again. Still run `ci/check-gate-metrics.sh` with both `DIFF_BASE` (the ref from `sh .agents-v0/scripts/resolve-integration-branch.sh`) and `REQUIRE_CVE_REPORT=1`, and run OWASP Dependency-Check. If this phase adds or changes tests, run the full `./mvnw -B clean verify` (Java) or the full frontend verify command from `docs/agents-v0/project-profile.md` once on the new commit. This is the gate command, not the fast red–green loop.
7. Generate JaCoCo report for changed backend/frontend code; confirm coverage ≥ 80% backend / 70% frontend.
8. Run OWASP Dependency-Check; confirm no new high/critical CVEs (document exceptions).
9. Add the VAPT-required tests (User A logout → User B login; renamed wrong-type file → 400; restricted role → 403; idempotent consumer dedupe).
10. For UI-affecting changes: run the automated accessibility check (axe-core) on changed routes of the built UI, not on the Design HTML mockups; confirm no serious/critical violations; map each UX acceptance criterion from `docs/agents-v0/design/<feature>/ux-spec.md` to a test of the built UI, including component defaults that the criterion names; persist the UX report to `docs/agents-v0/verify/<feature>/ux-report.md` (violations with severity, UX acceptance criteria status).
11. When this story is the P4 SLO story, or the requirements artifact cites `docs/agents-v0/design/system/nfr-slo.md`, follow `slo-evidence` and write `docs/agents-v0/design/system/slo-evidence.md` before the gate.
12. Persist the test report to `docs/agents-v0/verify/<feature>/test-report.md` — build status, coverage numbers, CVE scan results, documented exceptions.

## Rule-compliance checklist
- [ ] `quality-and-testing.mdc`: AAA; naming; coverage ≥ 80%/70%; methods ≤ 30 lines; cognitive complexity ≤ 15; no new high/critical CVEs.
- [ ] `vapt-spring.mdc` / `vapt-webapp.mdc`: required tests per finding included.
- [ ] `api-and-events.mdc`: idempotent consumer tests.
- [ ] UX spec: for UI-affecting changes, a11y check green (no serious/critical violations), UX acceptance criteria covered; UX report persisted to `docs/agents-v0/verify/<feature>/ux-report.md`.
- [ ] Mocks: external I/O only; domain tests deterministic.
- [ ] P4 SLO story: `docs/agents-v0/design/system/slo-evidence.md` records a measurement or a waiver for every filled NFR/SLO row (`slo-evidence`).
- [ ] `workflow-orchestration.mdc`: Verify gate (quality) criteria met; report persisted to `docs/agents-v0/verify/<feature>/test-report.md`.
