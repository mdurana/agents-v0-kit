#!/bin/sh
# check-design-contracts.sh — run the design checks over every feature under docs/agents-v0/design/.
#
# Usage: sh .agents-v0/ci/check-design-contracts.sh
# For each docs/agents-v0/design/<feature>/:
#   openapi.yaml  -> check-openapi.sh lint, and compat against the catalog it merges into
#                    (the service's openapi/<service>-v1.yaml when the requirements artifact has a
#                    "Service root:" line, else openapi/api-v1.yaml; skipped when neither exists)
#   design.lock   -> check-design.sh <feature> --verify-lock
#   ux-spec.md    -> check-ux-spec.sh <feature>
# A requirements file that already has an Approved Intake row is re-checked with check-intake.sh.
# docs/agents-v0/adr/ is checked with check-adr.sh (accepted records are superseded, not rewritten).
# Needs python3 and PyYAML. Exit 1 when any check fails; every feature is checked either way.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
failed=0

sh "$here/check-adr.sh" || failed=1

for cat_file in openapi/*.yaml openapi/*.yml; do
  [ -f "$cat_file" ] || continue
  sh "$here/check-openapi.sh" lint "$cat_file" || failed=1
done

for f in docs/agents-v0/design/*/openapi.yaml; do
  [ -f "$f" ] || continue
  feature="$(basename "$(dirname "$f")")"
  sh "$here/check-openapi.sh" lint "$f" || failed=1
  svc="$(sed -n 's/^[[:space:]]*Service root:[[:space:]]*//p' "docs/agents-v0/requirements/$feature.md" 2>/dev/null | head -n 1 | sed 's:/*$::; s:.*/::')"
  catalog=""
  if [ -n "$svc" ] && [ -f "openapi/$svc-v1.yaml" ]; then
    catalog="openapi/$svc-v1.yaml"
  elif [ -f openapi/api-v1.yaml ]; then
    catalog="openapi/api-v1.yaml"
  fi
  if [ -n "$catalog" ]; then
    sh "$here/check-openapi.sh" compat "$f" "$catalog" || failed=1
    if [ -f "docs/agents-v0/build/$feature/build-report.md" ] || sh "$here/check-approvals.sh" "docs/agents-v0/requirements/$feature.md" build >/dev/null 2>&1; then
      sh "$here/check-openapi.sh" merged "$f" "$catalog" || failed=1
    fi
  fi
done

for lock in docs/agents-v0/design/*/design.lock; do
  [ -f "$lock" ] || continue
  sh "$here/check-design.sh" "$(basename "$(dirname "$lock")")" --verify-lock || failed=1
done

for spec in docs/agents-v0/design/*/ux-spec.md; do
  [ -f "$spec" ] || continue
  sh "$here/check-ux-spec.sh" "$(basename "$(dirname "$spec")")" || failed=1
done

for req in docs/agents-v0/requirements/*.md; do
  [ -f "$req" ] || continue
  case "$req" in
    *.phase-result.md|*.helper-brief.md) continue ;;
  esac
  if grep -Eq '^[[:space:]]*Material:[[:space:]]*yes[[:space:]]*$' "$req"; then
    sh "$here/check-arc.sh" "$req" || failed=1
  fi
  if sh "$here/check-approvals.sh" "$req" intake >/dev/null 2>&1; then
    sh "$here/check-intake.sh" "$req" || failed=1
  fi
done

for async in docs/agents-v0/design/*/asyncapi.yaml docs/agents-v0/design/*/asyncapi.yml docs/agents-v0/design/*/asyncapi.json; do
  [ -f "$async" ] || continue
  sh "$here/check-asyncapi.sh" lint "$async" || failed=1
done

if [ "$failed" -ne 0 ]; then
  printf 'FAIL: design checks failed\n' >&2
  exit 1
fi
printf 'OK: design checks passed\n'
