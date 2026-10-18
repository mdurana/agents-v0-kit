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
mb_sha="$(git merge-base "$base" HEAD 2>/dev/null || true)"
head_sha="$(git rev-parse --verify -q "HEAD^{commit}" 2>/dev/null || true)"
if [ -n "$head_sha" ] && [ "$mb_sha" = "$head_sha" ]; then
  rep_sha=""
  for rp in "docs/agents-v0/build/${feature}/build-report.md" "docs/agents-v0/verify/${feature}/test-report.md"; do
    if [ -f "$rp" ]; then
      raw_rep="$(grep -Ei '^commit:[[:space:]]*[0-9a-f]{7,40}' "$rp" 2>/dev/null | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/[[:space:]].*//' || true)"
      if [ -n "$raw_rep" ]; then
        rep_sha="$(git rev-parse --verify -q "${raw_rep}^{commit}" 2>/dev/null || true)"
        [ -n "$rep_sha" ] && break
      fi
    fi
  done
  bc_sha=""
  state_file="docs/agents-v0/requirements/${feature}.state.json"
  if [ -f "$state_file" ]; then
    raw_bc="$(grep -Eo '"baseCommit"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{7,40}"' "$state_file" 2>/dev/null | head -n1 | sed 's/.*"baseCommit"[[:space:]]*:[[:space:]]*"//;s/"//' || true)"
    if [ -n "$raw_bc" ]; then
      bc_sha="$(git rev-parse --verify -q "${raw_bc}^{commit}" 2>/dev/null || true)"
    fi
  fi
  if [ -n "$bc_sha" ]; then
    if [ "$bc_sha" = "$head_sha" ] || ! git merge-base --is-ancestor "$bc_sha" "$head_sha" 2>/dev/null; then
      bc_sha=""
    elif [ -n "$rep_sha" ] && { [ "$bc_sha" = "$rep_sha" ] || ! git merge-base --is-ancestor "$bc_sha" "$rep_sha" 2>/dev/null; }; then
      bc_sha=""
    fi
  fi
  first_c="$(git log --reverse --format=%H HEAD -- \
    "docs/agents-v0/requirements/${feature}.md" "docs/agents-v0/design/${feature}" \
    "docs/agents-v0/build/${feature}" "docs/agents-v0/verify/${feature}" 2>/dev/null | head -n1 || true)"
  first_parent=""
  if [ -n "$first_c" ]; then
    first_parent="$(git rev-parse --verify -q "${first_c}^" 2>/dev/null || true)"
  fi
  if [ -n "$first_parent" ]; then
    if [ "$first_parent" = "$head_sha" ] || ! git merge-base --is-ancestor "$first_parent" "$head_sha" 2>/dev/null; then
      first_parent=""
    elif [ -n "$rep_sha" ] && { [ "$first_parent" = "$rep_sha" ] || ! git merge-base --is-ancestor "$first_parent" "$rep_sha" 2>/dev/null; }; then
      first_parent=""
    fi
  fi
  rep_parent=""
  if [ -n "$rep_sha" ]; then
    rep_parent="$(git rev-parse --verify -q "${rep_sha}^" 2>/dev/null || true)"
  fi
  if [ -n "$first_parent" ] && [ -n "$bc_sha" ]; then
    if git merge-base --is-ancestor "$first_parent" "$bc_sha" 2>/dev/null; then
      base="$first_parent"
    else
      base="$bc_sha"
    fi
  elif [ -n "$first_parent" ]; then
    base="$first_parent"
  elif [ -n "$bc_sha" ]; then
    base="$bc_sha"
  elif [ -n "$rep_parent" ]; then
    base="$rep_parent"
  fi
fi
body="$(mktemp)"
trap 'rm -f "$body"' EXIT

sh .agents-v0/scripts/render-mr-body.sh "$feature" --base "$base" >"$body"
REQUIRE_VERIFY=1 CHECK_MR_APPROVER=0 sh .agents-v0/ci/check-delivery-linkage.sh "$base" HEAD "$body"
sh .agents-v0/ci/check-design-contracts.sh
sh .agents-v0/ci/check-build-plan.sh "$feature"
sh .agents-v0/ci/check-endpoint-auth.sh "$base" HEAD
printf 'OK: local delivery gate passed for %s\n' "$feature"
