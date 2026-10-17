# Gold standards

> Build, run, test, CI commands for this repo. (`project-delivery-core.mdc`)

## Host tools (Intel Mac)

On Intel macOS (`uname -m` is `x86_64`), missing host tools are installed with MacPorts when a port exists. The .NET SDK is not a MacPorts port. Apple Silicon, Linux, and CI images keep their existing toolchain.

The machine that runs the profile verify command needs the toolchain that command names, determined by the bound pack's `hostChecks`. Pack `java` needs JDK 21 and the wrapper `./mvnw`. Pack `node` needs Node 22 (22.12+; CI and Dockerfile starters use 22) and npm. Pack `python` needs Python 3.13. Pack `go` needs Go. Pack `dotnet` needs the .NET 10 SDK (installed from Microsoft or the pack CI image). The React example needs Node 22 and npm. PyYAML is `python3 -c 'import yaml'`. Docker and Podman are applications, not MacPorts ports.

```bash
sh .agents-v0/scripts/host-tools-macports.sh
sh .agents-v0/scripts/host-tools-macports.sh --install
```

`--install` needs approval. It runs `sudo port -N install` only for what is missing among the pack's host checks: `openjdk21`, `nodejs22`, `npm11`, `go`, `python313`, and PyYAML (`python3 -m pip install pyyaml`, or `pyXY-yaml` when Python itself is from MacPorts). Put `/opt/local/bin` before other package managers on `PATH`. For kit Java builds, set `JAVA_HOME` from `/usr/libexec/java_home -v 21`. A later performance story that needs k6 uses `sudo port install k6`.

## Build

The commands in `docs/agents-v0/project-profile.md` are the ones CI and agents run (`.agents-v0/ci/resolve-layout.sh`). They come from the bound pack's `pack.json`. Pack `java` is:

```bash
cd app/backend && ./mvnw -B clean verify
cd app/frontend && npm run build   # React example; SvelteKit when the repo already uses it
```

Profile `service` runs the Backend verify row from the backend or BFF root. Profile `ui` runs the Frontend verify row. Profile `app` runs both. Fast loops use `Backend verify (fast, no OWASP)` and `Frontend verify (fast)`. Pack `java` fills those with `./mvnw -B clean verify -P!ci-security` and `npm test`. Bootstrap `--scaffold-app` fills the Java example; the red–green loop must not use a placeholder cell. A repo whose profile still names `backend/` or `frontend/` at the root uses those paths. Set `CI_PACK_IMAGE` to that manifest's `ciImage`.

## Run

```bash
./mvnw spring-boot:run  # Pack java, from the backend root, or per service
dotnet run              # Pack dotnet
npm run start:dev       # Pack node (NestJS)
python -m uvicorn ...   # Pack python (FastAPI)
go run .                # Pack go
npm run dev             # React example
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
   - Spring Boot, pack `java`: `docker/Dockerfile.spring-boot` → `Dockerfile`
   - ASP.NET Core, pack `dotnet`: `docker/Dockerfile.dotnet` → `Dockerfile`
   - NestJS, pack `node`: `docker/Dockerfile.nestjs` → `Dockerfile`
   - FastAPI, pack `python`: `docker/Dockerfile.python` → `Dockerfile`
   - Gin, pack `go`: `docker/Dockerfile.go` → `Dockerfile`
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
./mvnw -B clean test jacoco:report   # Pack java; coverage -> target/site/jacoco/index.html
npm test                             # React example (Vitest)
```

## CI

- Build → the profile verify command → the pack coverage report → the pack CVE scan → (deploy). Pack `java` uses JaCoCo, Sonar, and OWASP Dependency-Check. Other packs use the report formats in `pack.json`.
- Coverage gate: changed-line coverage under 80% fails when `DIFF_BASE` is set; 80% backend and 70% frontend are the report check (`quality-and-testing.mdc`).
- No new high/critical CVEs without documented exception.
