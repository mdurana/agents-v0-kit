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

mkdir -p "$STAGE/app/backend" "$STAGE/app/frontend"
# Copy without build artifacts, the archive itself, or macOS metadata. kitfix-20261031-skeleton:
# the archive packed on macOS held 57 AppleDouble ._* files that broke Checkstyle and Vitest on Linux
# (P0-A). COPYFILE_DISABLE stops macOS tar from writing them; the excludes drop any on disk.
# tar is used instead of rsync so the script also runs where rsync is not installed.
COPYFILE_DISABLE=1; export COPYFILE_DISABLE
for part in backend frontend; do
  tar -C "$APP/$part" \
    --exclude 'node_modules' --exclude 'dist' --exclude 'target' \
    --exclude '.DS_Store' --exclude '._*' --exclude 'p0-platform-skeleton.tar.gz' \
    -cf - . | tar -C "$STAGE/app/$part" -xf -
done
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

if find "$STAGE" -name '._*' | grep -q .; then
  printf 'error: macOS ._* files in the staged template\n' >&2
  exit 1
fi
# No extended attributes or ACLs (GNU tar defaults; bsdtar needs --no-xattrs --no-acls).
if tar --version 2>/dev/null | grep -qi bsdtar; then
  tar --no-xattrs --no-acls -C "$STAGE" -czf "$OUT" app docker-compose.yml
else
  tar --sort=name --owner=0 --group=0 --numeric-owner -C "$STAGE" -czf "$OUT" app docker-compose.yml
fi
printf 'Wrote %s (%s bytes)\n' "$OUT" "$(wc -c <"$OUT" | tr -d ' ')"
