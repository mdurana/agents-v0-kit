---
name: implement-spring-service
description: Build phase playbook. Implement a layered Spring Boot service with Flyway migrations, auth, tracing, and red–green tests.
---

# implement-spring-service

Build phase playbook for the `backend-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts (OpenAPI, event schemas, ADR) and existing repo.
2. **Baseline:** run the Backend verify command from `docs/project-profile.md` (directory profile in `project-delivery-core.mdc`) before the first edit. If it fails, stop and report the pre-existing failure; never build on a broken baseline. Put code under that backend root.
3. **Wire the quality gate** if missing (`maven/quality-plugins.xml`: JaCoCo/Checkstyle/SpotBugs/OWASP bound to `verify`; `maven/contract-conformance.xml` when OpenAPI is generated; ArchUnit where wired) — unwired tooling makes `mvn clean verify` compile-only.
4. Work **red–green (TDD where practical)** per behavior unit: failing test first, then implement until green (`quality-and-testing.mdc`).
5. Implement layers: Controller (`@Valid`, DTOs) → Service (`@Transactional(readOnly=true)` default) → Repository → Domain.
6. Add `@PreAuthorize` on **every** admin/mutation controller method.
7. Auth/upload/RBAC changes ship with their VAPT-required tests in the same diff.
8. Add Flyway migrations for all schema changes.
9. Wire correlation ID (`X-Correlation-ID` + MDC) and `traceparent` (W3C Trace Context).
10. Sanitize log values with `Encode.forJava`; no PII/secrets/tokens in logs.
11. For uploads: non-empty check, explicit size limit, magic-byte sniff + structure parse, extension allowlist supplemental, `@PreAuthorize`.
12. For logout: blacklist JWT + purge session state; blacklist fail-closed.
13. Use parameterized queries/JPA named parameters only.
14. Run the Backend verify command from `docs/project-profile.md` with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. For a security-critical or complex unit, hand it to `solution-architect` for a design review instead of a further attempt.
15. Persist evidence to `docs/build/<feature>/build-report.md` (command, result, per-criterion file:line evidence) and `docs/build/<feature>/build-output.txt` (raw output; no secrets).

## Rule-compliance checklist
- [ ] `java-spring-backend.mdc`: constructor injection; `@Transactional(readOnly=true)`; `@Enumerated(STRING)`; no N+1; DTOs only; `Encode.forJava`; no empty catch; methods ≤ 30 lines.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; methods ≤ 30 lines; cognitive complexity ≤ 15; coverage targets on changed code.
- [ ] Baseline green before the first edit; quality gate wired and executed in `mvn -B clean verify`.
- [ ] Contract conformance diff clean (or recorded N/A reason); ArchUnit layer rules where wired.
- [ ] `vapt-spring.mdc` F1: logout blacklists JWT + purges session; fail-closed.
- [ ] `vapt-spring.mdc` F3: uploads validated server-side (size, content, structure, authz).
- [ ] `vapt-spring.mdc` F4: `@PreAuthorize` on every admin/mutation method; `permit-all` local dev only.
- [ ] `api-and-events.mdc`: `/api/v1/`; 201/204; idempotency keys; one error envelope per surface.
- [ ] `security-baseline.mdc` §2: BOLA authorized lookup; §3: no secrets in code/logs.
- [ ] Build evidence persisted under `docs/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
