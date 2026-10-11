# Local container templates (Dockerfile + Compose)

Standard local testing uses a **Dockerfile** (or **Containerfile**) at the service root
and **`docker-compose.yml`**, run via `sh .agents-v0/scripts/run-local-container.sh` (Podman or Docker).

## Pick a Dockerfile starter

| Stack | Copy to repo root |
|-------|-------------------|
| Spring Boot (Maven) | `docker/Dockerfile.spring-boot` → `Dockerfile` |
| Static SPA (Vite/React default) | `docker/Dockerfile.static-nginx` → `Dockerfile` and keep `docker/nginx-spa.conf` |
| Node SSR / existing SvelteKit node adapter | `docker/Dockerfile.node` → `Dockerfile` (adjust `CMD` if needed) |

```bash
cp docker/Dockerfile.spring-boot Dockerfile
cp docker-compose.yml docker-compose.yml   # seeded on kit install when missing
```

For static nginx builds, ensure `docker/nginx-spa.conf` exists (copy from this folder).

## Compose

Single-service starter: `docker-compose.yml` builds `Dockerfile` in the project root and
publishes `${APP_PORT:-8080}` (override with `APP_PORT` or `-p` on the script).

Profile `app` from `--scaffold-app` replaces that with API `:8080`, UI `:8081`, and
`postgres:15-alpine` (see `templates/app/docker-compose.yml`).

Optional Postgres overlay for a single Spring Boot service:

```bash
docker compose -f docker-compose.yml -f docker/docker-compose.postgres.yml up --build -d
```

## Commands

```bash
sh .agents-v0/scripts/run-local-container.sh           # compose up --build -d
sh .agents-v0/scripts/run-local-container.sh --down    # compose down
sh .agents-v0/scripts/run-local-container.sh --skip-build
```

Podman: `podman compose` when available; otherwise `docker compose` with `DOCKER_HOST`
pointing at the Podman socket.
