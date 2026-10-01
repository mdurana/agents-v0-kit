#!/bin/sh
# check-design-contracts.sh — run the design checks over every feature under docs/design/.
#
# Usage: sh ci/check-design-contracts.sh
# For each docs/design/<feature>/:
#   openapi.yaml  -> check-openapi.sh lint, and compat against the catalog it merges into
#                    (the service's openapi/<service>-v1.yaml when the requirements artifact has a
#                    "Service root:" line, else openapi/api-v1.yaml; skipped when neither exists)
#   design.lock   -> check-design.sh <feature> --verify-lock
#   ux-spec.md    -> check-ux-spec.sh <feature>
# Needs python3 and PyYAML. Exit 1 when any check fails; every feature is checked either way.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
failed=0

for f in docs/design/*/openapi.yaml; do
  [ -f "$f" ] || continue
  feature="$(basename "$(dirname "$f")")"
  sh "$here/check-openapi.sh" lint "$f" || failed=1
  svc="$(sed -n 's/^[[:space:]]*Service root:[[:space:]]*//p' "docs/requirements/$feature.md" 2>/dev/null | head -n 1 | sed 's:/*$::; s:.*/::')"
  catalog=""
  if [ -n "$svc" ] && [ -f "openapi/$svc-v1.yaml" ]; then
    catalog="openapi/$svc-v1.yaml"
  elif [ -f openapi/api-v1.yaml ]; then
    catalog="openapi/api-v1.yaml"
  fi
  if [ -n "$catalog" ]; then
    sh "$here/check-openapi.sh" compat "$f" "$catalog" || failed=1
  fi
done

for lock in docs/design/*/design.lock; do
  [ -f "$lock" ] || continue
  sh "$here/check-design.sh" "$(basename "$(dirname "$lock")")" --verify-lock || failed=1
done

for spec in docs/design/*/ux-spec.md; do
  [ -f "$spec" ] || continue
  sh "$here/check-ux-spec.sh" "$(basename "$(dirname "$spec")")" || failed=1
done

for async in docs/design/*/asyncapi.yaml; do
  [ -f "$async" ] || continue
  sh "$here/check-asyncapi.sh" lint "$async" || failed=1
done

if [ "$failed" -ne 0 ]; then
  printf 'FAIL: design checks failed\n' >&2
  exit 1
fi
printf 'OK: design checks passed\n'
