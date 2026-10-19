#!/bin/sh
# run-local-container.sh — local testing via Dockerfile + Compose (Podman or Docker).
#
# Prefers docker-compose.yml / compose.yml in the project root. Falls back to
# building and running ./Dockerfile (or Containerfile) when no compose file exists.
#
# Usage:
#   sh .agents-v0/scripts/run-local-container.sh [--build|--skip-build] [--down] [-p|--port <host_port>]
set -eu

PORT="${APP_PORT:-}"
DO_BUILD=1
DO_DOWN=0
DO_SMOKE=0
ROOT=""

usage() {
  cat <<'EOF' >&2
Usage: run-local-container.sh [--build|--skip-build] [--down] [--smoke] [-p|--port <host_port>]

Requires docker-compose.yml (recommended) or Dockerfile/Containerfile at the project root.
Copy starters from docker/ — see docker/README.md.
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build)
      DO_BUILD=0
      shift
      ;;
    --build)
      DO_BUILD=1
      shift
      ;;
    --down)
      DO_DOWN=1
      shift
      ;;
    --smoke)
      DO_SMOKE=1
      shift
      ;;
    -p|--port)
      [ $# -ge 2 ] || {
        printf 'error: %s requires a port\n' "$1" >&2
        exit 1
      }
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage
      ;;
  esac
done

wait_http_200() {
  url="$1"
  timeout_s="${SMOKE_TIMEOUT:-60}"
  elapsed=0
  while [ "$elapsed" -lt "$timeout_s" ]; do
    if command -v curl >/dev/null 2>&1; then
      code="$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
      if [ "$code" = "200" ]; then
        return 0
      fi
    elif command -v python3 >/dev/null 2>&1; then
      if python3 - "$url" <<'PY' >/dev/null 2>&1
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=2) as r:
    raise SystemExit(0 if r.status == 200 else 1)
PY
      then
        return 0
      fi
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  printf 'error: timed out waiting for HTTP 200 from %s after %ss\n' "$url" "$timeout_s" >&2
  return 1
}

find_project_root() {
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/compose.yml" ] \
      || [ -f "$dir/docker-compose.yaml" ] || [ -f "$dir/compose.yaml" ] \
      || [ -f "$dir/docker-compose.local.yml" ] || [ -f "$dir/Dockerfile" ] \
      || [ -f "$dir/Containerfile" ]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

engine_active() {
  cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && "$cmd" info >/dev/null 2>&1
}

ENGINE=""
if engine_active podman; then
  ENGINE="podman"
elif engine_active docker; then
  ENGINE="docker"
elif command -v podman >/dev/null 2>&1; then
  printf 'error: podman found but not responding — try: podman machine start\n' >&2
  exit 1
elif command -v docker >/dev/null 2>&1; then
  printf 'error: docker found but daemon not running\n' >&2
  exit 1
else
  printf 'error: install Podman or Docker for local container runs\n' >&2
  exit 1
fi

configure_docker_host_for_podman() {
  [ "$ENGINE" = "podman" ] || return 0
  [ -n "${DOCKER_HOST:-}" ] && return 0

  if podman machine info >/dev/null 2>&1; then
    SOCK_PATH="$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)"
    if [ -n "$SOCK_PATH" ] && [ -S "$SOCK_PATH" ]; then
      export DOCKER_HOST="unix://${SOCK_PATH}"
      return 0
    fi
  fi

  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
    return 0
  fi

  if [ -S /run/podman/podman.sock ]; then
    export DOCKER_HOST="unix:///run/podman/podman.sock"
  fi
}

compose_cmd() {
  if [ "$ENGINE" = "podman" ] && podman compose version >/dev/null 2>&1; then
    COMPOSE_BIN="podman"
    COMPOSE_SUB="compose"
    COMPOSE_DISPLAY="podman compose"
    return 0
  fi
  if docker compose version >/dev/null 2>&1; then
    if [ "$ENGINE" = "podman" ]; then
      configure_docker_host_for_podman
    fi
    COMPOSE_BIN="docker"
    COMPOSE_SUB="compose"
    COMPOSE_DISPLAY="docker compose"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    if [ "$ENGINE" = "podman" ]; then
      configure_docker_host_for_podman
    fi
    COMPOSE_BIN="docker-compose"
    COMPOSE_SUB=""
    COMPOSE_DISPLAY="docker-compose"
    return 0
  fi
  return 1
}

find_compose_file() {
  for f in docker-compose.yml compose.yml docker-compose.yaml compose.yaml docker-compose.local.yml; do
    if [ -f "$ROOT/$f" ]; then
      COMPOSE_FILE="$f"
      return 0
    fi
  done
  return 1
}

find_dockerfile() {
  if [ -f "$ROOT/Dockerfile" ]; then
    DOCKERFILE_PATH="$ROOT/Dockerfile"
    return 0
  fi
  if [ -f "$ROOT/Containerfile" ]; then
    DOCKERFILE_PATH="$ROOT/Containerfile"
    return 0
  fi
  return 1
}

ROOT="$(find_project_root || true)"
if [ -z "$ROOT" ]; then
  printf 'error: no docker-compose.yml or Dockerfile found (see docker/README.md)\n' >&2
  exit 1
fi
cd "$ROOT"

printf 'Using container engine: %s (project root: %s)\n' "$ENGINE" "$ROOT"

if [ -n "$PORT" ]; then
  export APP_PORT="$PORT"
fi

IMAGE_NAME="${APP_IMAGE:-local-app:local}"
CONTAINER_NAME="${APP_CONTAINER_NAME:-local-app}"

if find_compose_file; then
  if ! compose_cmd; then
    printf 'error: %s found but podman compose / docker compose is not available\n' "$COMPOSE_FILE" >&2
    exit 1
  fi
  if [ -n "$COMPOSE_SUB" ]; then
    set -- "$COMPOSE_BIN" "$COMPOSE_SUB" -f "$COMPOSE_FILE"
  else
    set -- "$COMPOSE_BIN" -f "$COMPOSE_FILE"
  fi
  if [ "$DO_DOWN" -eq 1 ]; then
    printf 'Stopping compose stack (%s)...\n' "$COMPOSE_FILE"
    "$@" down
    exit 0
  fi
  set -- "$@" up -d
  if [ "$DO_BUILD" -eq 1 ]; then
    set -- "$@" --build
  fi
  printf 'Starting compose (%s)...\n' "$COMPOSE_FILE"
  "$@"
  host_port="${APP_PORT:-8080}"
  if [ "$DO_SMOKE" -eq 1 ]; then
    smoke_rc=0
    wait_http_200 "http://localhost:${host_port}/health" || smoke_rc=1
    if [ "$smoke_rc" -eq 0 ] && grep -Eq '^[[:space:]]*ui:' "$COMPOSE_FILE"; then
      ui_port="${UI_PORT:-8081}"
      wait_http_200 "http://localhost:${ui_port}/" || smoke_rc=1
    fi
    if [ -n "$COMPOSE_SUB" ]; then
      "$COMPOSE_BIN" "$COMPOSE_SUB" -f "$COMPOSE_FILE" down
    else
      "$COMPOSE_BIN" -f "$COMPOSE_FILE" down
    fi
    [ "$smoke_rc" -eq 0 ] || exit 1
    printf 'OK: local compose smoke passed (http://localhost:%s/health)\n' "$host_port"
    exit 0
  fi
  printf '\nStack running (compose).\n'
  printf '  Logs : %s -f %s logs -f\n' "$COMPOSE_DISPLAY" "$COMPOSE_FILE"
  printf '  Down : sh .agents-v0/scripts/run-local-container.sh --down\n'
  printf '  URL  : http://localhost:%s (set APP_PORT / APP_CONTAINER_PORT in compose if needed)\n' "$host_port"
  exit 0
fi

if [ "$DO_DOWN" -eq 1 ]; then
  if "$ENGINE" ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq "$CONTAINER_NAME"; then
    "$ENGINE" rm -f "$CONTAINER_NAME"
  fi
  exit 0
fi

if ! find_dockerfile; then
  printf 'error: add docker-compose.yml or Dockerfile (see docker/README.md)\n' >&2
  exit 1
fi

if [ "$DO_BUILD" -eq 1 ]; then
  printf 'Building image %s from %s...\n' "$IMAGE_NAME" "$DOCKERFILE_PATH"
  "$ENGINE" build -f "$DOCKERFILE_PATH" -t "$IMAGE_NAME" "$ROOT"
fi

if "$ENGINE" ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq "$CONTAINER_NAME"; then
  "$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null
fi

host_port="${PORT:-8080}"
container_port="${APP_CONTAINER_PORT:-8080}"
printf 'Starting container %s on http://localhost:%s\n' "$CONTAINER_NAME" "$host_port"
"$ENGINE" run -d --name "$CONTAINER_NAME" -p "${host_port}:${container_port}" "$IMAGE_NAME"

if [ "$DO_SMOKE" -eq 1 ]; then
  smoke_rc=0
  wait_http_200 "http://localhost:${host_port}/health" || smoke_rc=1
  "$ENGINE" rm -f "$CONTAINER_NAME" >/dev/null
  [ "$smoke_rc" -eq 0 ] || exit 1
  printf 'OK: local container smoke passed (http://localhost:%s/health)\n' "$host_port"
  exit 0
fi

printf '\nContainer running.\n'
printf '  Logs : %s logs -f %s\n' "$ENGINE" "$CONTAINER_NAME"
printf '  Stop : %s rm -f %s\n' "$ENGINE" "$CONTAINER_NAME"
