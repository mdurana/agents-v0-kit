---
name: scaffold-service
description: Greenfield scaffold for the node pack. Prove a NestJS health shell, Jest coverage, and a container. Do not extract the Java archive.
pack: node
---

# scaffold-service

P0 playbook for the `backend-engineer` when `Pack` is `node`. Do not extract `templates/app/p0-platform-skeleton.tar.gz`. Do not add `pom.xml`. Keep Express only when the repo already uses it.

## Steps
1. Confirm `docs/agents-v0/milestones/p0-platform-skeleton.md`. Create a NestJS service under the backend root.
2. Copy `docker/Dockerfile.nestjs` to the backend root as `Dockerfile`. Wire Compose so the API listens on `:8080` and Postgres is `postgres:15-alpine`.
3. Add `/health`, `/ready`, and `/live`. The health route is `@Public`. Every other route has `@UseGuards`. Copy `node/jest.quality.cjs` so tests write `junit.xml` and `coverage/coverage-summary.json`.
4. Add a TypeORM baseline migration, or record N/A when the skeleton has no schema yet.
5. Wire correlation id and `traceparent`. No secrets in the image or the log.
6. Replace every `TEMPLATE:` line in `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md` with what this commit contains. A network row is `built` only when a file in the commit shows that port.
7. Run the profile Backend verify command once. Persist the P0 evidence under `docs/agents-v0/build/p0-a-platform-skeleton/`.

## Rule-compliance checklist
- [ ] `backend.mdc` and `vapt.mdc` F4.
- [ ] `quality-and-testing.mdc`: Jest writes the coverage summary.
- [ ] The Java archive was not extracted.
