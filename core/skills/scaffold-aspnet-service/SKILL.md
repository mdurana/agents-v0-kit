---
name: scaffold-aspnet-service
description: Greenfield scaffold for the dotnet pack. Prove a health shell, EF Core baseline, coverlet, and a container. Do not extract the Java archive.
pack: dotnet
---

# scaffold-aspnet-service

P0 playbook for the `backend-engineer` when `Pack` is `dotnet`. Do not extract `templates/app/p0-platform-skeleton.tar.gz`. Do not add `pom.xml` or Flyway.

## Steps
1. Confirm `docs/agents-v0/milestones/p0-platform-skeleton.md`. Create the service under the backend root from the profile.
2. Copy `docker/Dockerfile.dotnet` to the backend root as `Dockerfile`. Wire Compose so the API listens on `:8080` and Postgres is `postgres:15-alpine` unless the ADR named SQL Server.
3. Add `/health`, `/ready`, and `/live`. A public health route uses `[AllowAnonymous]` and is the only anonymous route. Copy `dotnet/coverlet.props` so `dotnet test` writes `TestResults/*.trx` and `coverage.cobertura.xml`.
4. Add an EF Core baseline migration, or record N/A when the skeleton has no schema yet. Follow `migration-safety` once a table exists.
5. Wire correlation id and `traceparent`. No secrets in the image or the log.
6. Replace every `TEMPLATE:` line in `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md` with what this commit contains. A network row is `built` only when a file in the commit shows that port.
7. Run the profile Backend verify command once. Persist the P0 evidence under `docs/agents-v0/build/p0-a-platform-skeleton/`.

## Rule-compliance checklist
- [ ] `aspnet-backend.mdc` and `vapt-aspnet.mdc` F4: health is `[AllowAnonymous]`; every other route is `[Authorize]`.
- [ ] `quality-and-testing.mdc`: coverlet is on the test command.
- [ ] The Java archive was not extracted.
