# Gold standards

> Build, run, test, CI commands for this repo. (`project-delivery-core.mdc`)

## Build

```bash
mvn clean verify        # Java, from the backend root in docs/agents-v0/project-profile.md
npm run build           # frontend (React default; SvelteKit when existing), from the UI root
```

Profile `service` uses `cd app/backend && ./mvnw -B clean verify` (or `cd app/bff && ./mvnw -B clean verify` for a BFF-only repo). Profile `ui` uses `cd app/frontend && npm run verify`. Profile `app` runs both. A repo whose profile still names `backend/` or `frontend/` at the root uses those paths. The commands recorded in `docs/agents-v0/project-profile.md` are the ones CI and agents run (`ci/resolve-layout.sh`).

## Run

```bash
mvn spring-boot:run    # or per service
npm run dev            # frontend
```

### Local container (Dockerfile + Compose)

**Profile `app` after `--scaffold-app`:** root `docker-compose.yml` already builds
`app/backend` (API `:8080`) and `app/frontend` (UI `:8081`) with `postgres:15-alpine`.

```bash
docker compose up --build -d
```

**Single-service / external skeleton:** use a root **`Dockerfile`** (or **`Containerfile`**)
and the starter `docker-compose.yml`, via Podman or Docker and the kit script.

1. Copy a starter from `docker/` (see `docker/README.md`):
   - Spring Boot: `docker/Dockerfile.spring-boot` → `Dockerfile`
   - Node SSR: `docker/Dockerfile.node` → `Dockerfile` (set `APP_CONTAINER_PORT=3000` for compose)
   - Static SPA: `docker/Dockerfile.static-nginx` → `Dockerfile` + `docker/nginx-spa.conf`
2. Ensure `docker-compose.yml` exists (seeded on kit install when missing).

```bash
./scripts/run-local-container.sh              # compose up --build -d
./scripts/run-local-container.sh --skip-build # compose up -d
./scripts/run-local-container.sh --down       # compose down
./scripts/run-local-container.sh -p 9090      # sets APP_PORT for compose
```

Optional Postgres overlay (Spring Boot, `postgres:15-alpine`):  
`compose -f docker-compose.yml -f docker/docker-compose.postgres.yml up --build -d`

## Test

```bash
mvn clean test jacoco:report   # Java + coverage -> target/site/jacoco/index.html
npm test                      # frontend (Vitest)
```

## CI

- Build → test → JaCoCo → Sonar → OWASP Dependency-Check → (deploy).
- Coverage gate: 80% backend, 70% frontend (`quality-and-testing.mdc`).
- No new high/critical CVEs without documented exception.
