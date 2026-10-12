---
name: implement-spring-service
description: Build phase playbook. Implement a layered Spring Boot service with Flyway migrations, auth, tracing, and red–green tests.
pack: java
---

# implement-spring-service

Build phase playbook for the `backend-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts (OpenAPI, event schemas, ADR) and existing repo.
2. **Baseline:** run the full Backend verify command from `docs/agents-v0/project-profile.md` (directory profile in `project-delivery-core.mdc`) before the first edit, unless `/v0-build` skips a checkout that is already the default branch tip. If it fails, stop and report the pre-existing failure; never build on a broken baseline. Put code under that backend root. When the profile lists `Service roots`, use the `Service verify` and `Service verify (fast, no OWASP)` rows instead of the `Backend verify` rows, with `{root}` set to the story's `Service root:`. In the rest of this skill, "Backend verify" means that row.
3. **Wire the quality gate** if missing (`maven/quality-plugins.xml`: JaCoCo/Checkstyle/SpotBugs/OWASP bound to `verify`; `maven/contract-conformance.xml` when OpenAPI is generated; ArchUnit where wired) — unwired tooling makes `./mvnw -B clean verify` compile-only.
4. When `docs/agents-v0/design/<feature>/openapi.yaml` exists, merge that approved draft into the org catalog (`openapi/api-v1.yaml`, or the catalog path in the profile) before other implementation edits. Stop if that catalog file is already modified by another feature. Merge with `sh .agents-v0/ci/check-openapi.sh merge <draft> <catalog>` (review the diff) or by hand, then `sh .agents-v0/ci/check-openapi.sh merged <draft> <catalog>` must pass. Copy event schemas from `docs/agents-v0/design/<feature>/events/` to the event-schema path in the profile when that path is set. A story with no draft records N/A in the build report. When the profile lists `Service roots`, work inside the `Service root:` the requirements artifact names, and merge into that service's catalog (`openapi/<service>-v1.yaml`).
5. Before the first implementation edit, write `docs/agents-v0/build/<feature>/plan.md` with one row per approved `AC-*` (AC, Status `pending`/`done`/`blocked`, Test). Do not add, delete, or rewrite AC rows.
6. Work **red–green (TDD where practical)** per plan row: failing test first, then implement until green (`quality-and-testing.mdc`). Mark the row `done` and name the test only after that unit's fast command is green, then run `sh .agents-v0/ci/check-build-plan.sh <feature>`: it fails when the named test does not exist or was never red (a red card names it; `(no-red: <reason>)` waives one row). Each loop run **must** use `Backend verify (fast, no OWASP)` from the profile (a real command, not a `<!--` placeholder). If that cell is empty or still a placeholder, stop and fill the profile rather than running the full Backend verify in the loop. Append a command-result card (Command, Exit, Attempt, Failing test, Location). The next attempt must not read `build-output.txt`. Before each new attempt run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md`; exit 1 means the phase attempt budget is spent (`workflow-orchestration.mdc`): record `blocked` and stop. The second red result for the same test writes `docs/agents-v0/build/<feature>/failure-brief.md` (`helper: debug-investigator`) and returns. Before attempt three run `sh .agents-v0/scripts/check-failure-brief.sh <feature>` (must exit 0). Attempt three applies that note. A third red result stops.
7. Implement layers: Controller (`@Valid`, DTOs) → Service (`@Transactional(readOnly=true)` default) → Repository → Domain.
8. Add `@PreAuthorize` on **every** admin/mutation controller method. A public route uses `@PreAuthorize("permitAll()")`. Do not use `org.springframework.security.access.prepost.PermitAll`; that type is not in Spring Security 6. Exclude `UserDetailsServiceAutoConfiguration` when the app has no user store, so Boot does not log a generated password. `sh .agents-v0/ci/check-endpoint-auth.sh <base>` fails a new mapping with no `@PreAuthorize`, `@Secured`, `@RolesAllowed`, or `@PermitAll`.
9. Auth/upload/RBAC changes ship with their VAPT-required tests in the same diff.
10. Add Flyway migrations for all schema changes, following `migration-safety`: additive first (expand/contract), a rollback note, and a Testcontainers test that applies the migration to the previous schema.
11. Wire correlation ID (`X-Correlation-ID` + MDC) and `traceparent` (W3C Trace Context).
12. Sanitize log values with `Encode.forJava`; no PII/secrets/tokens in logs.
13. For uploads: non-empty check, explicit size limit, magic-byte sniff + structure parse, extension allowlist supplemental, generated storage name, decompression limit, `@PreAuthorize`, production virus scan.
14. For logout: blacklist JWT + purge session state; blacklist fail-closed.
15. Validate JWTs with an algorithm allowlist, `iss`/`aud`/`exp`/`nbf`, and known `kid` values. Rotate refresh tokens.
16. Emit security audit events for auth, denial, revocation, admin mutation, and upload outcome (`security-baseline.mdc` §12).
17. Use parameterized queries/JPA named parameters only. Sort and filter fields come from an allowlist.
18. Run the full Backend verify command from `docs/agents-v0/project-profile.md` once for the Build gate (`./mvnw -B clean verify` when that row names it), with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. For a security-critical or complex unit, hand it to `solution-architect` for a design review instead of a further attempt. The fast loop does not replace this gate.
19. Persist evidence to `docs/agents-v0/build/<feature>/build-report.md` (command, result, attempt cards, per-criterion file:line evidence) and `docs/agents-v0/build/<feature>/build-output.txt` (raw output; no secrets). Do not read `build-output.txt` on the next attempt.

## Rule-compliance checklist
- [ ] `java-spring-backend.mdc`: constructor injection; `@Transactional(readOnly=true)`; `@Enumerated(STRING)`; no N+1; DTOs only; `Encode.forJava`; no empty catch; methods ≤ 30 lines.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; methods ≤ 30 lines; cognitive complexity ≤ 15; coverage targets on changed code.
- [ ] `docs/agents-v0/build/<feature>/plan.md` has one row per approved `AC-*`; done rows name a test.
- [ ] Baseline green before the first edit; red–green loop uses `Backend verify (fast, no OWASP)` when that cell is a real command; quality gate executed once in `./mvnw -B clean verify`.
- [ ] Attempt cards recorded; `build-output.txt` not read back. Second failure uses `failure-brief.md`; `check-failure-brief.sh` passes before attempt three.
- [ ] Approved feature draft merged into the org catalog, or N/A recorded.
- [ ] Contract conformance diff clean (or recorded N/A reason); ArchUnit layer rules where wired.
- [ ] `vapt-spring.mdc` F1: logout blacklists JWT + purges session; fail-closed.
- [ ] `vapt-spring.mdc` F3: uploads validated server-side (size, content, structure, generated name, decompression limit, authz, production virus scan).
- [ ] `vapt-spring.mdc` F4: `@PreAuthorize` on every admin/mutation method; `permit-all` local dev only; policy errors deny.
- [ ] `vapt-spring.mdc` F8: same-role peer `{id}` authorized in the owning service; write DTO rejects unknown properties.
- [ ] `vapt-spring.mdc` F9: JWT algorithm allowlist, `iss`/`aud`/`exp`/`nbf`, known `kid`, refresh rotation, blacklist fail-closed.
- [ ] `vapt-spring.mdc` F10: audit events for auth, denial, and admin/upload; no token in the log.
- [ ] `api-and-events.mdc`: `/api/v1/`; 201/204; idempotency keys; one error envelope per surface; sort/filter and URL allowlists.
- [ ] `security-baseline.mdc` §2: BOLA authorized lookup; §3: no secrets in code/logs; §12: audit events.
- [ ] Build evidence persisted under `docs/agents-v0/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
