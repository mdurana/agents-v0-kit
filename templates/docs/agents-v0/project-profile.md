# Project profile

> Machine- and human-readable commands for agents (`workflow-orchestration.mdc`). Update when build tooling or topology changes.

## Stack

| Layer | Value |
|-------|--------|
| Pack | <!-- pack id; any name with a complete .agents-v0/packs/<id>/pack.json --> |
| Backend | <!-- Java 21, Spring Boot 4.1.1, Maven wrapper --> |
| HTTP | <!-- Spring MVC, embedded Tomcat 11.0.26 --> |
| Security | <!-- Spring Security --> |
| Frontend | <!-- the pack ui id, for example React 19, TypeScript 5.9, Vite 7 --> |
| Database | <!-- PostgreSQL 15, Flyway --> |
| Tests | <!-- JUnit (spring-boot-starter-test), ArchUnit 1.4.2, H2 test profile, Vitest 3 --> |
| Local run | <!-- Compose API :8080, UI :8081, postgres:15-alpine --> |

## Commands

| Purpose | Command |
|---------|---------|
| Backend verify | <!-- e.g. ./mvnw -B clean verify --> |
| Backend verify (fast, no OWASP) | <!-- e.g. ./mvnw -B clean verify -P!ci-security --> |
| Service verify | <!-- multi-service repos only; {root} = the story's Service root, e.g. ./mvnw -B -f {root}/pom.xml clean verify --> |
| Service verify (fast, no OWASP) | <!-- e.g. ./mvnw -B -f {root}/pom.xml clean verify -P!ci-security --> |
| Frontend verify | <!-- e.g. npm run verify --> |
| Frontend verify (fast) | <!-- e.g. cd app/frontend && npm test — required for the red–green loop; gate still uses Frontend verify --> |
| Lint | <!-- optional --> |
| Local run | <!-- e.g. sh .agents-v0/scripts/run-local-container.sh --> |

## Layout

Directory profiles (`project-delivery-core.mdc`): `service` (`app/backend/`, or `app/bff/` when that is the only Spring module), `ui` (`app/frontend/`), `app` (`app/backend/` + `app/frontend/`, optional `app/bff/`). The repo root has no application `src/`. A repo that still uses `backend/` or `frontend/` at the root keeps those paths in the rows below. **This repo** wins when Profile is `service`, `ui`, or `app`. `/v0-onboard` records a legacy tree (including `.`) and does not move it. `ci/resolve-layout.sh` reads the two-column rows below.

| Profile | When | Code roots |
|---------|------|------------|
| service | Spring Boot only | `app/backend/`: `src/main/java`, `src/main/resources/db/migration`, `src/test/java`. Packages: `api`, `service`, `repository`, `domain`. BFF-only: `app/bff/` instead |
| ui | The pack's `ui` id. The React example uses `src/pages/`, `src/features/`, `src/components/`, `src/services/api`, `src/store/` | `app/frontend/` |
| app | Service and UI in one repo | `app/backend/` and `app/frontend/`. `app/bff/` only when a BFF is in scope. `docs/`, `openapi/` at the repo root |

| This repo | Value |
|-----------|--------|
| Profile | <!-- service, ui, or app --> |
| Backend root | <!-- `app/backend/` or n/a --> |
| Frontend root | <!-- `app/frontend/` or n/a --> |
| BFF root | <!-- `app/bff/` or n/a --> |
| Service roots | <!-- comma-separated roots for a multi-service repo, e.g. `app/services/order, app/services/inventory`, or n/a --> |
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

## Release (optional; read by `/v0-release`)

| Release | Value |
|---------|-------|
| Release owner | <!-- GitLab username allowed to tag and publish --> |
| Version file | <!-- e.g. pom.xml (project.version) or package.json; blank when the tag is the version --> |
| Tag format | <!-- e.g. v{version} --> |
| Changelog | <!-- e.g. CHANGELOG.md; blank when none --> |
| Integration branch | <!-- local branch the next story builds on after /v0-local-release, e.g. main; blank uses origin's local branch, else main --> |

## Brownfield exceptions

### known_failures (optional budget for ci/check-known-failures.sh)

A person approves each row, and CODEOWNERS makes this file a code-owner change, so a merge request cannot approve its own exception. CI excuses test failures up to the first Allowed failure count (the build job after a failed verify, and `check-gate-metrics.sh`). A compile or plugin error is never excused. Leave `0` for no allowance.

| Allowed failure count | Scope / test IDs | Owner | Remove by |
|----------------------|------------------|-------|-----------|
| 0 | | | |

### coverage_ratchet (optional; read by quality-and-testing.mdc)

| Scope | Interim minimum | Approver (Security + architecture) | Remove by |
|-------|-----------------|------------------------------------|-----------|
| | | | |

## Endpoint authorization

The Pack row selects the scanners in that pack's `pack.json`. An empty Pack does not scan a default language. Add a row only for a file type that scanner does not already cover. Columns: Stack, Suffix (`.py`), Marker (file must match this regex, or `(any)`), Mapping (regex; group 1 is the verb, group 2 the path), Security (regex near the mapping). Separate columns with ` | `. A pipe inside a regex has no spaces around it.

| Stack | Suffix | Marker | Mapping | Security |
|-------|--------|--------|---------|----------|
| | | | | |

## Delivery

- Default change tier: Standard
- Feature artifact pattern: `docs/agents-v0/requirements/<feature>.md`
