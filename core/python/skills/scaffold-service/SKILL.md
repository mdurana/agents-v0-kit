---
name: scaffold-service
description: Greenfield scaffold for the python pack. Prove a FastAPI health shell, pytest coverage, and a container. Do not extract the Java archive.
pack: python
---

# scaffold-service

P0 playbook for the `backend-engineer` when `Pack` is `python`. Do not extract `templates/app/p0-platform-skeleton.tar.gz`. Do not add `pom.xml`. Keep Django only when the repo already uses it.

## Steps
1. Confirm `docs/agents-v0/milestones/p0-platform-skeleton.md`. Create a FastAPI service under the backend root.
2. Copy `docker/Dockerfile.python` to the backend root as `Dockerfile`. Wire Compose so the API listens on `:8080` and Postgres is `postgres:15-alpine`.
3. Add `/health`, `/ready`, and `/live`. The health route names a public dependency. Every other route has a security `Depends()`. Copy `python/pytest.ini` so tests write `pytest-report.xml` and `coverage.xml`.
4. Add an Alembic baseline revision, or record N/A when the skeleton has no schema yet.
5. Wire correlation id and `traceparent`. No secrets in the image or the log.
6. Replace every `TEMPLATE:` line in `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md` with what this commit contains. A network row is `built` only when a file in the commit shows that port.
7. Run the profile Backend verify command once. Persist the P0 evidence under `docs/agents-v0/build/p0-a-platform-skeleton/`.

## Rule-compliance checklist
- [ ] `backend.mdc` and `vapt.mdc` F4.
- [ ] `quality-and-testing.mdc`: pytest writes `coverage.xml`.
- [ ] The Java archive was not extracted.
