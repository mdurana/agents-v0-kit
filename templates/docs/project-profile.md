# Project profile

> Machine- and human-readable commands for agents (`workflow-orchestration.mdc`). Update when build tooling or topology changes.

## Stack

| Layer | Value |
|-------|--------|
| Backend | <!-- e.g. Java 21, Spring Boot 3.4, Maven wrapper --> |
| Frontend | <!-- e.g. SvelteKit / React, package manager --> |
| Database | <!-- e.g. PostgreSQL 15, Flyway --> |

## Commands

| Purpose | Command |
|---------|---------|
| Backend verify | <!-- e.g. ./mvnw -B clean verify --> |
| Backend verify (fast, no OWASP) | <!-- e.g. ./mvnw -B clean verify -P!ci-security --> |
| Service verify | <!-- multi-service repos only; {root} = the story's Service root, e.g. ./mvnw -B -f {root}/pom.xml clean verify --> |
| Service verify (fast, no OWASP) | <!-- e.g. ./mvnw -B -f {root}/pom.xml clean verify -P!ci-security --> |
| Frontend verify | <!-- e.g. npm run verify --> |
| Frontend verify (fast) | <!-- e.g. npm test — red–green loop; the gate still uses Frontend verify --> |
| Lint | <!-- optional --> |
| Local run | <!-- e.g. ./scripts/run-local-container.sh --> |

## Layout

Directory profiles (`project-delivery-core.mdc`): `service` (`backend/`, or `bff/` when that is the only Spring module), `ui` (`frontend/`), `app` (`backend/` + `frontend/`, optional `bff/`). The repo root has no application `src/`. **This repo** wins when Profile is `service`, `ui`, or `app`. `/onboard` records a legacy tree (including `.`) and does not move it. `ci/resolve-layout.sh` reads the two-column rows below.

| Profile | When | Code roots |
|---------|------|------------|
| service | Spring Boot only | `backend/`: `src/main/java`, `src/main/resources/db/migration`, `src/test/java`. Packages: `api`, `service`, `repository`, `domain`. BFF-only: `bff/` instead |
| ui | SvelteKit or React only | `frontend/`. SvelteKit: `src/routes/`, `src/lib/`. React: `src/pages/`, `src/features/`, `src/components/`, `src/services/api`, `src/store/` |
| app | Service and UI in one repo | `backend/` and `frontend/`. `bff/` only when a BFF is in scope. `docs/`, `ci/`, `openapi/` at the repo root |

| This repo | Value |
|-----------|--------|
| Profile | <!-- service, ui, or app --> |
| Backend root | <!-- `backend/` or n/a --> |
| Frontend root | <!-- `frontend/` or n/a --> |
| BFF root | <!-- `bff/` or n/a --> |
| Service roots | <!-- comma-separated roots for a multi-service repo, e.g. `services/order, services/inventory`, or n/a --> |
| OpenAPI | <!-- `openapi/api-v1.yaml`; multi-service repos use `openapi/<service>-v1.yaml` per service, or n/a --> |
| CI image prefix | <!-- optional; mirror prefix for `.gitlab-ci.yml` (`CI_IMAGE_PREFIX`, e.g. `registry.example.com/`) --> |
| Phase attempt budget | <!-- total failed verify attempts per phase before blocked; default 8 --> |

## Contracts

- Approved OpenAPI: <!-- path -->
- Event schemas: <!-- path -->

## Deploy (optional; read by the `release-deploy` skill)

One row per environment, in promotion order. Leave empty when the merge is the end of delivery.

| Environment | Deploy command | Smoke check | Rollback command |
|-------------|----------------|-------------|------------------|
| | | | |

## Release (optional; read by `/release`)

| Release | Value |
|---------|-------|
| Release owner | <!-- GitLab username allowed to tag and publish --> |
| Version file | <!-- e.g. pom.xml (project.version) or package.json; blank when the tag is the version --> |
| Tag format | <!-- e.g. v{version} --> |
| Changelog | <!-- e.g. CHANGELOG.md; blank when none --> |

## Brownfield exceptions

### known_failures (optional budget for ci/check-known-failures.sh)

| Allowed failure count | Scope / test IDs | Owner | Remove by |
|----------------------|------------------|-------|-----------|
| 0 | | | |

### coverage_ratchet (optional; read by quality-and-testing.mdc)

| Scope | Interim minimum | Approver (Security + architecture) | Remove by |
|-------|-----------------|------------------------------------|-----------|
| | | | |

## Endpoint authorization

Spring (`*.java`, `@*Mapping`, `@PreAuthorize` / `@PermitAll`) is built in. Add a row to scan another stack. Columns: Stack, Suffix (`.py`), Marker (file must match this regex, or `(any)`), Mapping (regex; group 1 is the verb, group 2 the path), Security (regex near the mapping). Separate columns with ` | `. A pipe inside a regex has no spaces around it.

| Stack | Suffix | Marker | Mapping | Security |
|-------|--------|--------|---------|----------|
| | | | | |

## Delivery

- Default change tier: Standard
- Feature artifact pattern: `docs/requirements/<feature>.md`
