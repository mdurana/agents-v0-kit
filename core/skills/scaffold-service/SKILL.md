---
name: scaffold-service
description: Greenfield scaffold playbook. Secure Spring Boot / BFF / frontend skeleton with CI, health, tracing, and quality gate wiring.
---

# scaffold-service

Greenfield playbook after external generators (Spring Initializr, `npx sv create`, etc.) and `bootstrap-greenfield.sh`.

## Steps
1. Confirm P0 milestone manifest and green baseline (`docs/agents-v0/milestones/p0-platform-skeleton.md`).
2. Copy kit starters with `--with-starters` install: `maven/quality-plugins.xml`, `docker/`, `openapi/api-v1.yaml`, CI workflows.
3. Wire: `/health`, correlation ID filter, W3C `traceparent`, structured logging, global error envelope per `api-and-events.mdc`.
4. Security: no `permit-all` outside a public route marked on purpose. A public route uses `@PreAuthorize("permitAll()")`. Do not use `org.springframework.security.access.prepost.PermitAll`; that type is not in Spring Security 6. Exclude `UserDetailsServiceAutoConfiguration` so the starter does not log a generated password. `@PreAuthorize` on a sample admin endpoint; secrets via env only. `check-endpoint-auth.sh` accepts `@PreAuthorize`.
5. Add Flyway `V1__baseline.sql` under the backend root `src/main/resources/db/migration`, or document N/A for frontend-only.
6. Keep new code under the Layout roots in `docs/agents-v0/project-profile.md` (`project-delivery-core.mdc` profiles `service`, `ui`, `app`). Run the verify command from that profile; persist P0 story evidence through the one skeleton story.
6a. Replace every `TEMPLATE:` line in `docs/agents-v0/architecture.md` with what this commit contains (the module, the entrypoint, health if present). Cite `path:line` or write `UNVERIFIED`. In `docs/agents-v0/network.md`, set Status to `built` and Citation to a file only for a port or dependency this commit runs. Leave every other row `planned` with an empty citation. Do not copy a `planned` row into `architecture.md` as if it were running.
7. Do not skip `/v0-verify` for scaffold stories touching auth or public routes.

## Rule-compliance checklist
- [ ] `project-delivery-core.mdc`, `java-spring-backend.mdc` / `frontend-web.mdc`.
- [ ] `security-baseline.mdc`: authn/authz, no secrets in repo.
- [ ] `quality-and-testing.mdc`: quality plugins on `verify` (OWASP in CI profile).
