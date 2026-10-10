#!/bin/sh
# check-delivery-gate-local.sh — run the pre-push delivery checks in one command.
#
# Usage: sh .agents-v0/scripts/check-delivery-gate-local.sh <feature> [--base <ref>]
# Default base is resolve-integration-branch.sh. Renders the merge-request body, then runs linkage
# (CHECK_MR_APPROVER=0), design contracts, the build plan, and endpoint authorization.
# Exit 1 when any check fails.
set -eu

feature=""
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] || { printf 'usage: %s <feature> [--base <ref>]\n' "$0" >&2; exit 1; }
      base="$2"
      shift 2
      ;;
    -h|--help)
      printf 'usage: %s <feature> [--base <ref>]\n' "$0" >&2
      exit 0
      ;;
    *)
      feature="$1"
      shift
      ;;
  esac
done
[ -n "$feature" ] || { printf 'usage: %s <feature> [--base <ref>]\n' "$0" >&2; exit 1; }

root="$(git rev-parse --show-toplevel)"
cd "$root"
if [ -z "$base" ]; then
  base="$(sh .agents-v0/scripts/resolve-integration-branch.sh)"
fi
body="$(mktemp)"
trap 'rm -f "$body"' EXIT

sh .agents-v0/scripts/render-mr-body.sh "$feature" --base "$base" >"$body"
CHECK_MR_APPROVER=0 sh .agents-v0/ci/check-delivery-linkage.sh "$base" HEAD "$body"
sh .agents-v0/ci/check-design-contracts.sh
sh .agents-v0/ci/check-build-plan.sh "$feature"
sh .agents-v0/ci/check-endpoint-auth.sh "$base" HEAD
printf 'OK: local delivery gate passed for %s\n' "$feature"
