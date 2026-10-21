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
4. Use Testcontainers for integration (API+DB+messaging) and Pact for BFF↔service contracts where the repo already depends on them. A migration or SQL change still needs a test against the profile database rather than relying only on H2/in-memory substitutes.
5. When a single-file unit test or mock data should be drafted by `schema-author`, write `docs/agents-v0/verify/<feature>/helper-brief.md` (`helper: schema-author`) and return. Do not launch the helper (`workflow-orchestration.mdc` Helper Subagents).
6. When no code or tests changed since `docs/agents-v0/build/<feature>/build-report.md` and this phase is not adding or changing tests, quote that build run. Otherwise run the full stack verify command via `sh .agents-v0/scripts/run-backend-verify.sh` (Pack `java`: `./mvnw -B clean verify -Pci-security`) or the full frontend verify command from `docs/agents-v0/project-profile.md`. This is the gate command, not the fast red–green loop.
7. Confirm coverage ≥ 80% backend / 70% frontend and ≥ 80% changed lines from the pack's coverage report (Pack `java`: JaCoCo at `target/site/jacoco/index.html`). Whole-module line coverage follows the pack configuration (Pack `java`: JaCoCo 0.80 in `core/java/starters/maven/quality-plugins.xml`) or the Whole-module lines row in `docs/agents-v0/quality-gates.md`. Verify that any `coverage_ratchet` row in `docs/agents-v0/project-profile.md` has a valid approver and an unexpired removal date.
8. Confirm no new high/critical CVEs (document exceptions) from the pack's CVE report (`cve.path` in `pack.json`; Pack `java` uses OWASP Dependency-Check).
9. Add the VAPT-required tests for the surface (User A logout → User B login; same-role peer `{id}` → 403 or 404; disallowed JWT `alg` or wrong `aud` rejected; renamed wrong-type file → 400; restricted role → 403; one audit event without a bearer token; idempotent consumer dedupe).
10. For UI-affecting changes: run the automated accessibility check (axe-core) on changed routes of the built UI, not on the Design HTML mockups; confirm no serious/critical violations; map each UX acceptance criterion from `docs/agents-v0/design/<feature>/ux-spec.md` to a test of the built UI, including component defaults that the criterion names; persist the UX report to `docs/agents-v0/verify/<feature>/ux-report.md` (violations with severity, UX acceptance criteria status).
11. When this story is the P4 SLO story, or the requirements artifact cites `docs/agents-v0/design/system/nfr-slo.md`, follow `slo-evidence` and write `docs/agents-v0/design/system/slo-evidence.md` before the gate.
12. Persist the test report to `docs/agents-v0/verify/<feature>/test-report.md` — build status, coverage numbers, CVE scan results, documented exceptions.

## Rule-compliance checklist
- [ ] `quality-and-testing.mdc`: AAA; naming; report coverage ≥ 80% backend / 70% frontend and ≥ 80% changed lines; methods ≤ 30 lines (Pack `java` targets ≤ 20); cognitive complexity ≤ 15; no new high/critical CVEs.
- [ ] Pack VAPT rule (`vapt.mdc`) / `vapt-webapp.mdc`: required tests per finding included.
- [ ] `api-and-events.mdc`: idempotent consumer tests.
- [ ] UX spec: for UI-affecting changes, a11y check green (no serious/critical violations), UX acceptance criteria covered; UX report persisted to `docs/agents-v0/verify/<feature>/ux-report.md`.
- [ ] Mocks: external I/O only; domain tests deterministic.
- [ ] P4 SLO story: `docs/agents-v0/design/system/slo-evidence.md` records a measurement or a waiver for every filled NFR/SLO row (`slo-evidence`).
- [ ] `workflow-orchestration.mdc`: Verify gate (quality) criteria met; report persisted to `docs/agents-v0/verify/<feature>/test-report.md`.
