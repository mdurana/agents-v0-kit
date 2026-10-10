#!/bin/sh
# pack-app-template.sh — build templates/app/p0-platform-skeleton.tar.gz from the
# editable source tree under templates/app/{backend,frontend,docker-compose.yml}.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$KIT/templates/app"
OUT="$APP/p0-platform-skeleton.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[ -d "$APP/backend" ] && [ -d "$APP/frontend" ] && [ -f "$APP/docker-compose.yml" ] || {
  printf 'error: missing templates/app/{backend,frontend,docker-compose.yml}\n' >&2
  exit 1
}

mkdir -p "$STAGE/app"
# Copy without build artifacts or the archive itself
rsync -a \
  --exclude 'node_modules/' --exclude 'dist/' --exclude 'target/' \
  --exclude '.DS_Store' --exclude 'p0-platform-skeleton.tar.gz' \
  "$APP/backend/" "$STAGE/app/backend/"
rsync -a \
  --exclude 'node_modules/' --exclude 'dist/' --exclude 'target/' \
  --exclude '.DS_Store' --exclude 'p0-platform-skeleton.tar.gz' \
  "$APP/frontend/" "$STAGE/app/frontend/"
cp "$APP/docker-compose.yml" "$STAGE/docker-compose.yml"

# Guard against product-specific leftovers
if rg -n --hidden -g '!package-lock.json' -g '!mvnw*' \
  -e 'CAS-EIS|com\.eis\.|eis-consoles|eis-middleware|eis_schema|jdbc:postgresql://localhost:5432/eis' \
  "$STAGE" >/dev/null 2>&1; then
  printf 'error: product-specific strings found in staged template:\n' >&2
  rg -n --hidden -g '!package-lock.json' -g '!mvnw*' \
    -e 'CAS-EIS|com\.eis\.|eis-consoles|eis-middleware|eis_schema|jdbc:postgresql://localhost:5432/eis' \
    "$STAGE" >&2 || true
  exit 1
fi

tar -C "$STAGE" -czf "$OUT" app docker-compose.yml
printf 'Wrote %s (%s bytes)\n' "$OUT" "$(wc -c <"$OUT" | tr -d ' ')"
