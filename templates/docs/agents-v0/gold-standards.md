# Gold standards

> Build, run, test, CI commands for this repo. (`project-delivery-core.mdc`)

## Host tools (Intel Mac)

On Intel macOS (`uname -m` is `x86_64`), missing host tools are installed with MacPorts. Apple Silicon, Linux, and CI images keep their existing toolchain.

The machine that runs `./mvnw` and `npm` needs JDK 21, Node 22 (22.12+; CI and the Dockerfile starters use 22, and 20.19+ still builds Vite 7 but is end-of-life), npm, and PyYAML (`python3 -c 'import yaml'`). Maven is the wrapper `./mvnw`. Docker and Podman are applications, not MacPorts ports.

```bash
sh .agents-v0/scripts/host-tools-macports.sh
sh .agents-v0/scripts/host-tools-macports.sh --install
```

`--install` needs approval. It runs `sudo port -N install` only for what is missing: `openjdk21`, `nodejs22`, `npm11`, and PyYAML (`python3 -m pip install pyyaml`, or `pyXY-yaml` when Python itself is from MacPorts). Put `/opt/local/bin` before other package managers on `PATH`. For kit builds, set `JAVA_HOME` from `/usr/libexec/java_home -v 21`. A later performance story that needs k6 uses `sudo port install k6`.

## Build

```bash
./mvnw -B clean verify  # from the backend root in docs/agents-v0/project-profile.md
npm run build           # frontend (React default; SvelteKit when existing), from the UI root
```

Profile `service` uses `cd app/backend && ./mvnw -B clean verify` (or `cd app/bff && ./mvnw -B clean verify` for a BFF-only repo). Profile `ui` uses `cd app/frontend && npm run verify`. Profile `app` runs both. Fast loops: `Backend verify (fast, no OWASP)` (`./mvnw -B clean verify -P!ci-security`) and `Frontend verify (fast)` (`npm test`) — bootstrap `--scaffold-app` fills these; the red–green loop must not use a placeholder cell. A repo whose profile still names `backend/` or `frontend/` at the root uses those paths. The commands recorded in `docs/agents-v0/project-profile.md` are the ones CI and agents run (`ci/resolve-layout.sh`).

## Run

```bash
./mvnw spring-boot:run  # from the backend root, or per service
npm run dev             # frontend
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
sh .agents-v0/scripts/run-local-container.sh              # compose up --build -d
sh .agents-v0/scripts/run-local-container.sh --skip-build # compose up -d
sh .agents-v0/scripts/run-local-container.sh --down       # compose down
sh .agents-v0/scripts/run-local-container.sh -p 9090      # sets APP_PORT for compose
```

Optional Postgres overlay (Spring Boot, `postgres:15-alpine`):  
`compose -f docker-compose.yml -f docker/docker-compose.postgres.yml up --build -d`

## Test

```bash
./mvnw -B clean test jacoco:report   # from the backend root; coverage -> target/site/jacoco/index.html
npm test                             # frontend (Vitest)
```

## CI

- Build → test → JaCoCo → Sonar → OWASP Dependency-Check → (deploy).
- Coverage gate: 80% backend, 70% frontend (`quality-and-testing.mdc`).
- No new high/critical CVEs without documented exception.
