---
name: quality-gate
description: Verify phase playbook. Run the profile Backend verify command or frontend tests, check coverage and CVEs, write AAA tests.
---

# quality-gate

Verify phase playbook for the `test-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the changed files and existing tests.
2. Write tests: Arrange–Act–Assert; naming `methodName_scenario_expectedOutcome` (Java) or `should_expectation_whenCondition` (frontend) — match existing suite style.
3. Cover happy, error, and edge paths; every `@ExceptionHandler`/catch that changes behavior.
4. Use Testcontainers for integration (API+DB+messaging) and Pact for BFF↔service contracts where the repo already depends on them. A migration or SQL change still needs a test against the profile database; H2 does not satisfy `check-gate-metrics.sh` when `DIFF_BASE` is set.
5. When a single-file unit test or mock data should be drafted by `schema-author`, write `docs/agents-v0/verify/<feature>/helper-brief.md` (`helper: schema-author`) and return. Do not launch the helper (`workflow-orchestration.mdc` Helper agents).
6. When non-doc files are unchanged between `HEAD` and the `commit:` line in `docs/agents-v0/build/<feature>/build-report.md` (or `git rev-parse HEAD` equals that commit; matching `.agents-v0/ci/check-evidence.sh`) and this phase is not adding or changing tests, quote that build run. Do not run the full verify command again. Still run `sh .agents-v0/ci/check-design-contracts.sh`, `sh .agents-v0/ci/collect-gate-reports.sh <root>`, and `sh .agents-v0/ci/check-gate-metrics.sh <root>` with both `DIFF_BASE` (the ref from `sh .agents-v0/scripts/resolve-integration-branch.sh`) and `REQUIRE_CVE_REPORT=1`. Pack `java` refreshes or validates `target/dependency-check-report.json` via `collect-gate-reports.sh` (or runs `./mvnw -B verify -Pci-security -DskipTests` if missing). Other packs refresh the file named by `cve.path` via `collect-gate-reports.sh`, and `check-gate-metrics.sh` fails when that file is missing or names an unsuppressed HIGH or CRITICAL. If this phase adds or changes tests, run the profile Backend verify command once on the new commit (Pack `java`: `./mvnw -B clean verify -Pci-security`) or the full frontend verify command from `docs/agents-v0/project-profile.md`, and run `sh .agents-v0/ci/check-design-contracts.sh`. This is the gate command, not the fast red–green loop.
7. Confirm coverage ≥ 80% backend / 70% frontend from the pack's coverage report (Pack `java`: JaCoCo at `target/site/jacoco/index.html`). CI fails changed lines under 80% for every pack when `DIFF_BASE` is set. Whole-module line coverage fails when the pack wires it (Pack `java`: JaCoCo 0.80 in `core/java/starters/maven/quality-plugins.xml`), when a Whole-module lines row in `docs/agents-v0/quality-gates.md` sets the bundle minimum, or when `MIN_LINE_PCT` is set. A `coverage_ratchet` row does not change that JaCoCo minimum. The GitLab `coverage-ratchet` job does not pass `LINE_COVERAGE_PCT`, so `.agents-v0/ci/check-coverage-ratchet.sh` checks the approver and the removal date, and compares a measured number only when that variable or `JACOCO_LINE_PCT` is set.
8. Confirm no new high/critical CVEs (document exceptions). Pack `java` uses OWASP Dependency-Check (refreshed via `collect-gate-reports.sh`). Other packs refresh the file named by `cve.path` via `sh .agents-v0/ci/collect-gate-reports.sh <root>`.
9. Add the VAPT-required tests for the surface (User A logout → User B login; same-role peer `{id}` → 403 or 404; disallowed JWT `alg` or wrong `aud` rejected; renamed wrong-type file → 400; restricted role → 403; one audit event without a bearer token; idempotent consumer dedupe).
10. For UI-affecting changes: run the automated accessibility check (axe-core) on changed routes of the built UI, not on the Design HTML mockups; confirm no serious/critical violations; map each UX acceptance criterion from `docs/agents-v0/design/<feature>/ux-spec.md` to a test of the built UI, including component defaults that the criterion names; persist the UX report to `docs/agents-v0/verify/<feature>/ux-report.md` (violations with severity, UX acceptance criteria status).
11. When this story is the P4 SLO story, or the requirements artifact cites `docs/agents-v0/design/system/nfr-slo.md`, follow `slo-evidence` and write `docs/agents-v0/design/system/slo-evidence.md` before the gate.
12. Persist the test report to `docs/agents-v0/verify/<feature>/test-report.md` — build status, coverage numbers, CVE scan results, documented exceptions.

## Rule-compliance checklist
- [ ] `quality-and-testing.mdc`: AAA; naming; report coverage ≥ 80% backend / 70% frontend; CI changed lines ≥ 80% when `DIFF_BASE` is set; methods ≤ 30 lines (Pack `java` targets ≤ 20); cognitive complexity ≤ 15; no new high/critical CVEs.
- [ ] Pack VAPT rule (`vapt.mdc`) / `vapt-webapp.mdc`: required tests per finding included.
- [ ] `api-and-events.mdc`: idempotent consumer tests.
- [ ] UX spec: for UI-affecting changes, a11y check green (no serious/critical violations), UX acceptance criteria covered; UX report persisted to `docs/agents-v0/verify/<feature>/ux-report.md`.
- [ ] Mocks: external I/O only; domain tests deterministic.
- [ ] P4 SLO story: `docs/agents-v0/design/system/slo-evidence.md` records a measurement or a waiver for every filled NFR/SLO row (`slo-evidence`).
- [ ] `workflow-orchestration.mdc`: Verify gate (quality) criteria met; report persisted to `docs/agents-v0/verify/<feature>/test-report.md`. The `Approved` verify row may not be written until `sh .agents-v0/ci/check-evidence.sh <artifact> verify` and `sh .agents-v0/ci/check-gate-metrics.sh` with `REQUIRE_CVE_REPORT=1` pass.
