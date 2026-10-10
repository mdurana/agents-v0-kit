#!/bin/sh
# test-app-template.sh — smoke the bundled P0 app archive (extract + backend unit tests).
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$KIT/templates/app/p0-platform-skeleton.tar.gz"
[ -f "$ARCHIVE" ] || {
  printf 'error: missing %s — run scripts/pack-app-template.sh\n' "$ARCHIVE" >&2
  exit 1
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

tar -C "$STAGE" -xzf "$ARCHIVE"
# KitPresenceTest walks up for .agents-v0 and the P0 milestone.
mkdir -p "$STAGE/.agents-v0" "$STAGE/.cursor" "$STAGE/docs/agents-v0/milestones"
touch "$STAGE/docs/agents-v0/milestones/p0-platform-skeleton.md"

# Prefer the Maven wrapper when present; fall back to mvn on PATH.
if [ -x "$STAGE/app/backend/mvnw" ]; then
  (cd "$STAGE/app/backend" && ./mvnw -B -q test \
    -Dtest=HealthControllerTest,QualityPluginsTest,LayerRulesTest,ComposeStackTest,KitPresenceTest)
else
  (cd "$STAGE/app/backend" && mvn -B -q test \
    -Dtest=HealthControllerTest,QualityPluginsTest,LayerRulesTest,ComposeStackTest,KitPresenceTest)
fi

printf 'test-app-template: OK\n'
