# Gold standards

> Build, run, test, CI commands for this repo. (`project-delivery-core.mdc`)

## Build

```bash
mvn clean verify        # Java, from the backend root in docs/project-profile.md
npm run build           # frontend (SvelteKit/React), from the UI root
```

Profile `service` uses `cd backend && ./mvnw -B clean verify` (or `cd bff && ./mvnw -B clean verify` for a BFF-only repo). Profile `ui` uses `cd frontend && npm run verify`. Profile `app` runs both. The commands recorded in `docs/project-profile.md` are the ones CI and agents run (`ci/resolve-layout.sh`).

## Run

```bash
mvn spring-boot:run    # or per service
npm run dev            # frontend
```

### Local container (Dockerfile + Compose)

Local integration testing uses a root **`Dockerfile`** (or **`Containerfile`**) and
**`docker-compose.yml`**, run with Podman or Docker via the kit script.

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

Optional Postgres overlay (Spring Boot):  
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
