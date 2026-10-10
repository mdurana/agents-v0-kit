---
name: scaffold-service
description: Greenfield scaffold playbook. Prove the bundled P0 app template (or an external skeleton) — health, security, quality gates, containers.
---

# scaffold-service

Greenfield playbook after `bootstrap-greenfield.sh --scaffold-app` (preferred) or an external generator plus kit install.

## Steps
1. Confirm P0 milestone manifest (`docs/agents-v0/milestones/p0-platform-skeleton.md`). Prefer the bundled template: archive `templates/app/p0-platform-skeleton.tar.gz` extracted by `scripts/scaffold-app-template.sh` / bootstrap `--scaffold-app` into `app/backend` and/or `app/frontend`.
2. When the template is already present, do **not** reinvent health, security, Flyway, ArchUnit, or the Vite shell. Confirm kit starters are installed (`maven/`, `docker/`, `openapi/api-v1.yaml`, CI). Only create missing pieces when the repo was scaffolded outside the kit.
3. Prove wiring: `/health` (+ `/ready` / `/live`), correlation ID filter, W3C `traceparent`, structured logging. Global error envelope per `api-and-events.mdc` when an API surface exists (P0-A has health only).
4. Security: no `permit-all` outside a public route marked on purpose. A public route uses `@PreAuthorize("permitAll()")`. Do not use `org.springframework.security.access.prepost.PermitAll`. Exclude `UserDetailsServiceAutoConfiguration` so the starter does not log a generated password. Secrets via env only. `check-endpoint-auth.sh` accepts `@PreAuthorize`.
5. Flyway `V1__baseline.sql` under the backend root `src/main/resources/db/migration`, or document N/A for frontend-only.
6. Keep code under the Layout roots in `docs/agents-v0/project-profile.md` (`project-delivery-core.mdc` profiles `service`, `ui`, `app`). Run the verify command from that profile; persist P0 story evidence through the one skeleton story.
6a. Replace every `TEMPLATE:` line in `docs/agents-v0/architecture.md` with what this commit contains (the module, the entrypoint, health if present). Cite `path:line` or write `UNVERIFIED`. In `docs/agents-v0/network.md`, set Status to `built` and Citation to a file only for a port or dependency this commit runs. Leave every other row `planned` with an empty citation. Do not copy a `planned` row into `architecture.md` as if it were running.
7. Do not skip `/v0-verify` for scaffold stories touching auth or public routes.

## Rule-compliance checklist
- [ ] `project-delivery-core.mdc`, `java-spring-backend.mdc` / `frontend-web.mdc`.
- [ ] `security-baseline.mdc`: authn/authz, no secrets in repo.
- [ ] `quality-and-testing.mdc`: quality plugins on `verify` (OWASP in CI profile).
- [ ] Bundled template used when present; no duplicate invent of health/shell.
