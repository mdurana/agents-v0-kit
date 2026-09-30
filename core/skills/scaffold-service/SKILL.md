---
name: scaffold-service
description: Greenfield scaffold playbook. Secure Spring Boot / BFF / frontend skeleton with CI, health, tracing, and quality gate wiring.
---

# scaffold-service

Greenfield playbook after external generators (Spring Initializr, `npx sv create`, etc.) and `bootstrap-greenfield.sh`.

## Steps
1. Confirm P0 milestone manifest and green baseline (`docs/milestones/p0-platform-skeleton.md`).
2. Copy kit starters with `--with-starters` install: `maven/quality-plugins.xml`, `docker/`, `openapi/api-v1.yaml`, CI workflows.
3. Wire: `/health`, correlation ID filter, W3C `traceparent`, structured logging, global error envelope per `api-and-events.mdc`.
4. Security: no `permit-all` outside local profile; `@PreAuthorize` pattern on sample admin endpoint; secrets via env only.
5. Add Flyway `V1__baseline.sql` under the backend root `src/main/resources/db/migration`, or document N/A for frontend-only.
6. Keep new code under the Layout roots in `docs/project-profile.md` (`project-delivery-core.mdc` profiles `service`, `ui`, `app`). Run the verify command from that profile; persist P0 story evidence through normal gated chain.
7. Do not skip `/verify` for scaffold stories touching auth or public routes.

## Rule-compliance checklist
- [ ] `project-delivery-core.mdc`, `java-spring-backend.mdc` / `frontend-web.mdc`.
- [ ] `security-baseline.mdc`: authn/authz, no secrets in repo.
- [ ] `quality-and-testing.mdc`: quality plugins on `verify` (OWASP in CI profile).
