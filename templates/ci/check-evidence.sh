#!/bin/sh
# check-evidence.sh — verify that evidence paths recorded in a delivery artifact's
# "Delivery approvals" row exist on disk (workflow-orchestration.mdc Build/Verify
# evidence contract).
#
# Usage: sh check-evidence.sh <requirements-artifact> <phase> [<path>...]
#   <requirements-artifact>  e.g. docs/requirements/my-feature.md
#   <phase>                  intake | design | build | verify | release
#   <path>...                optional; when given, each path must be recorded in the
#                            phase row's Artifacts column and exist on disk. When
#                            omitted, every concrete docs/ path recorded in the row
#                            is checked.
#
# Exit codes: 0 = every checked path exists; 1 = missing artifact, section, row,
# unrecorded path, dynamic-only path, or missing file.
# Evidence quality (content) is owned by the phase reviews; this script checks
# recording and existence only.

set -eu

art="${1:-}"
phase="${2:-}"
if [ -z "$art" ] || [ -z "$phase" ]; then
  printf 'usage: %s <requirements-artifact> <phase> [<path>...]\n' "$0" >&2
  exit 1
fi
case "$phase" in
  intake|design|build|verify|release) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected intake|design|build|verify|release)\n' "$phase" >&2
    exit 1
    ;;
esac
[ -f "$art" ] || { printf 'FAIL: requirements artifact not found: %s\n' "$art" >&2; exit 1; }
shift 2

section="$(awk '
  /^#+[[:space:]]*[Dd]elivery [Aa]pprovals/ { in_section = 1; next }
  /^#+[[:space:]]/ { in_section = 0 }
  in_section
' "$art")"

[ -n "$section" ] || { printf 'FAIL: %s has no "Delivery approvals" section\n' "$art" >&2; exit 1; }

row="$(printf '%s' "$section" | grep -i "|[[:space:]]*${phase}[[:space:]]*|" | head -n1 || true)"
[ -n "$row" ] || { printf 'FAIL: no approval row for phase "%s" in %s\n' "$phase" "$art" >&2; exit 1; }

artifacts="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')"

missing=0
checked=0

check_path() {
  p="$1"
  if ! printf '%s' "$artifacts" | grep -Fq "$p"; then
    printf 'FAIL: path not recorded in the "%s" row: %s\n' "$phase" "$p" >&2
    missing=1
    return 0
  fi
  if [ -e "$p" ]; then
    case "$p" in
      */build-report.md|*/test-report.md|*/vapt-checklist.md|*/review-notes.md|*/ux-report.md)
        if ! grep -Eqi '^commit:[[:space:]]*[0-9a-f]{7,40}' "$p" 2>/dev/null; then
          printf 'FAIL: report missing commit: line (workflow-orchestration.mdc): %s\n' "$p" >&2
          missing=1
        fi
        if [ "${VERIFY_STALE:-1}" != "0" ] && command -v git >/dev/null 2>&1; then
          rep_commit="$(grep -Ei '^commit:' "$p" 2>/dev/null | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/[[:space:]].*//')"
          stale_base="${VERIFY_STALE_BASE:-HEAD}"
          if [ -n "$rep_commit" ] && git cat-file -e "${rep_commit}^{commit}" 2>/dev/null; then
            stale="$(git diff --name-only "$rep_commit".."$stale_base" 2>/dev/null | grep -Ev '^(docs/|.*\.(md|mdc|txt|adoc)$)' || true)"
            if [ -n "$stale" ]; then
              printf 'FAIL: non-doc files changed since evidence commit %s — re-run phase and refresh %s\n' "$rep_commit" "$p" >&2
              missing=1
            fi
          fi
        fi
        ;;
    esac
    checked=$((checked + 1))
  else
    printf 'FAIL: recorded evidence missing on disk: %s\n' "$p" >&2
    missing=1
  fi
}

if [ "$#" -gt 0 ]; then
  for p in "$@"; do
    check_path "$p"
  done
else
  for p in $(printf '%s' "$artifacts" | tr -d '`' | tr ',;:' '\n\n\n'); do
    case "$p" in
      docs/*) ;;
      *) continue ;;
    esac
    case "$p" in
      *'<'*|*'>'*) continue ;;
    esac
    check_path "$p"
  done
  if [ "$checked" -eq 0 ] && [ "$missing" -eq 0 ]; then
    printf 'FAIL: no concrete docs/ evidence path recorded in the "%s" row of %s\n' "$phase" "$art" >&2
    exit 1
  fi
fi

if [ "$missing" -eq 1 ]; then
  exit 1
fi
printf 'OK: %s evidence path(s) for phase "%s" exist in the repo\n' "$checked" "$phase"
