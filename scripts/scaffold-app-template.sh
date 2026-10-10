#!/bin/sh
# scaffold-app-template.sh — extract the bundled P0 app template into a target repo.
#
# Usage:
#   scaffold-app-template.sh [--profile service|ui|app] <target-repo>
#
# Does not overwrite existing app/backend, app/frontend, or docker-compose.yml.
# Default profile is app (backend + frontend + compose).
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$KIT/templates/app/p0-platform-skeleton.tar.gz"
PROFILE="app"
TARGET=""

usage() {
  printf 'usage: %s [--profile service|ui|app] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      [ $# -ge 2 ] || usage
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

case "$PROFILE" in
  service|ui|app) ;;
  *)
    printf 'error: unknown profile: %s\n' "$PROFILE" >&2
    usage
    ;;
esac

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || {
  printf 'error: target not found: %s\n' "$TARGET" >&2
  exit 1
}
[ -f "$ARCHIVE" ] || {
  printf 'error: missing %s — run scripts/pack-app-template.sh\n' "$ARCHIVE" >&2
  exit 1
}

TARGET_ABS="$(cd "$TARGET" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

tar -C "$STAGE" -xzf "$ARCHIVE"

copy_tree() {
  src="$1"
  dest="$2"
  if [ -e "$dest" ]; then
    printf 'skip (exists): %s\n' "$dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
  printf 'seeded %s\n' "$dest"
}

case "$PROFILE" in
  service)
    copy_tree "$STAGE/app/backend" "$TARGET_ABS/app/backend"
    ;;
  ui)
    copy_tree "$STAGE/app/frontend" "$TARGET_ABS/app/frontend"
    ;;
  app)
    copy_tree "$STAGE/app/backend" "$TARGET_ABS/app/backend"
    copy_tree "$STAGE/app/frontend" "$TARGET_ABS/app/frontend"
    # Replace the single-service starter compose from --with-starters when it is not
    # already the app-profile stack (API + UI under app/).
    if [ -f "$TARGET_ABS/docker-compose.yml" ] && grep -Fq 'context: ./app/backend' "$TARGET_ABS/docker-compose.yml"; then
      printf 'skip (exists): %s\n' "$TARGET_ABS/docker-compose.yml"
    else
      cp "$STAGE/docker-compose.yml" "$TARGET_ABS/docker-compose.yml"
      printf 'seeded %s\n' "$TARGET_ABS/docker-compose.yml"
    fi
    ;;
esac

chmod +x "$TARGET_ABS/app/backend/mvnw" 2>/dev/null || true
