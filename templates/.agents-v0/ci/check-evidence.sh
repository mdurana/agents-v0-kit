#!/bin/sh
# check-evidence.sh — verify that evidence paths recorded in a delivery artifact's
# "Delivery approvals" row exist on disk (workflow-orchestration.mdc Build/Verify
# evidence contract).
#
# Usage: sh check-evidence.sh <requirements-artifact> <phase> [<path>...]
#   <requirements-artifact>  e.g. docs/agents-v0/requirements/my-feature.md
#   <phase>                  intake | design | build | verify | release
#   <path>...                optional; when given, each path must be recorded in the
#                            phase row's Artifacts column and exist on disk. When
#                            omitted, every concrete docs/ path recorded in the row
#                            is checked.
#
# Exit codes: 0 = every checked path exists; 1 = missing artifact, section, row,
# unrecorded path, dynamic-only path, missing file, a report without commit:,
# or non-doc files changed since that commit (VERIFY_STALE=0 skips the stale check).
# Evidence quality (content) is owned by the phase reviews.

set -eu

art="${1:-}"
phase="${2:-}"
if [ -z "$art" ] || [ -z "$phase" ]; then
  printf 'usage: %s <requirements-artifact> <phase> [<path>...]\n' "$0" >&2
  exit 1
fi
case "$phase" in
  onboard|intake|design|build|verify|release) ;;
  *)
    printf 'FAIL: unknown phase "%s" (expected onboard|intake|design|build|verify|release)\n' "$phase" >&2
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

row="$(printf '%s' "$section" | grep -i "|[[:space:]]*${phase}[[:space:]]*|" | tail -n1 || true)"
is_p0_unapproved=0
if [ -z "$row" ]; then
  # For Story: P0-A in Milestone: P0, approval rows are only written at Release.
  # Before release, build and verify evidence on disk with commit: is valid.
  if grep -Eqi 'Story:[[:space:]]*P0-A\b' "$art" && grep -Eqi 'Milestone:[[:space:]]*P0\b' "$art"; then
    case "$phase" in
      build|verify)
        is_p0_unapproved=1
        ;;
      *)
        printf 'FAIL: no approval row for phase "%s" in %s\n' "$phase" "$art" >&2
        exit 1
        ;;
    esac
  else
    printf 'FAIL: no approval row for phase "%s" in %s\n' "$phase" "$art" >&2
    exit 1
  fi
fi

if [ "$is_p0_unapproved" = "1" ]; then
  case "$phase" in
    build) artifacts="docs/agents-v0/build/p0-a-platform-skeleton/build-report.md" ;;
    verify) artifacts="docs/agents-v0/verify/p0-a-platform-skeleton/test-report.md" ;;
  esac
else
  artifacts="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')"
fi

missing=0
checked=0

default_stale_base="${VERIFY_STALE_BASE:-HEAD}"
if [ -z "${VERIFY_STALE_BASE:-}" ] && [ "${VERIFY_STALE:-1}" != "0" ] && command -v git >/dev/null 2>&1 && git cat-file -e "HEAD^{commit}" 2>/dev/null; then
  rel_row="$(printf '%s' "$section" | grep -i "|[[:space:]]*release[[:space:]]*|" | tail -n1 || true)"
  rel_dec="$(printf '%s' "$rel_row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print tolower($5)}')"
  phase_dec="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print tolower($5)}')"
  if printf '%s' "$rel_dec" | grep -Eqi '^(approved|approve|yes|pass|local)([^a-z]|$)' && printf '%s' "$phase_dec" | grep -Eqi '^(approved|approve|yes|pass)([^a-z]|$)'; then
    if [ -z "$(git status --porcelain -- "$art" 2>/dev/null || true)" ]; then
      art_slug="$(basename "$art" .md)"
      art_commit="$(git log -1 --format=%H -- "$art" "${art%.md}.state.json" "docs/agents-v0/build/${art_slug}" "docs/agents-v0/verify/${art_slug}" 2>/dev/null || true)"
      if [ -n "$art_commit" ] && git merge-base --is-ancestor "$art_commit" HEAD 2>/dev/null; then
        other_req="$(git diff --name-only "$art_commit"..HEAD -- 'docs/agents-v0/requirements/*.md' 2>/dev/null | grep -Fxv "$art" | grep -Ev '(^|/)_template\.md$' || true)"
        if [ -n "$other_req" ]; then
          default_stale_base="$art_commit"
        fi
      fi
    fi
  fi
fi

check_path() {
  p="$1"
  if [ "$is_p0_unapproved" = "1" ]; then
    case "$phase" in
      build)
        case "$p" in
          docs/agents-v0/build/p0-a-platform-skeleton/*) ;;
          *)
            printf 'FAIL: path not recorded in the "%s" row: %s\n' "$phase" "$p" >&2
            missing=1
            return 0
            ;;
        esac
        ;;
      verify)
        case "$p" in
          docs/agents-v0/verify/p0-a-platform-skeleton/*) ;;
          *)
            printf 'FAIL: path not recorded in the "%s" row: %s\n' "$phase" "$p" >&2
            missing=1
            return 0
            ;;
        esac
        ;;
    esac
  elif ! printf '%s' "$artifacts" | grep -Fq "$p"; then
    printf 'FAIL: path not recorded in the "%s" row: %s\n' "$phase" "$p" >&2
    missing=1
    return 0
  fi
  if [ -e "$p" ]; then
    stale_base="$default_stale_base"
    has_git_head=0
    if [ "${VERIFY_STALE:-1}" != "0" ] && command -v git >/dev/null 2>&1 && git cat-file -e "${stale_base}^{commit}" 2>/dev/null; then
      has_git_head=1
    fi
    if [ "$has_git_head" = "1" ]; then
      if ! git cat-file -e "${stale_base}:${p}" 2>/dev/null; then
        printf 'FAIL: recorded evidence %s is not committed in %s (untracked on disk) — commit the report without changing its commit: line\n' "$p" "$stale_base" >&2
        missing=1
      elif ! git diff --quiet "${stale_base}" -- "$p" 2>/dev/null; then
        printf 'FAIL: recorded evidence %s has uncommitted changes on disk — commit it before running the gate\n' "$p" >&2
        missing=1
      fi
    fi
    case "$p" in
      */build-report.md|*/test-report.md|*/vapt-checklist.md|*/review-notes.md|*/ux-report.md|*/e2e-report.md|docs/agents-v0/onboarding/report.md)
        if ! grep -Eqi '^commit:[[:space:]]*[0-9a-f]{7,40}' "$p" 2>/dev/null; then
          printf 'FAIL: report missing commit: line (workflow-orchestration.mdc): %s\n' "$p" >&2
          missing=1
        fi
        if [ "$has_git_head" = "1" ]; then
          rep_commit="$(grep -Ei '^commit:' "$p" 2>/dev/null | head -n1 | sed 's/^[^:]*:[[:space:]]*//;s/[[:space:]].*//')"
          if [ -n "$rep_commit" ]; then
            if ! git cat-file -e "${rep_commit}^{commit}" 2>/dev/null; then
              printf 'FAIL: commit: %s in %s is not a commit in git\n' "$rep_commit" "$p" >&2
              missing=1
            elif ! git merge-base --is-ancestor "$rep_commit" "$stale_base" 2>/dev/null; then
              printf 'FAIL: commit: %s in %s is not an ancestor of %s\n' "$rep_commit" "$p" "$stale_base" >&2
              missing=1
            else
              stale="$(git diff --name-only "$rep_commit".."$stale_base" 2>/dev/null | grep -Ev '^(docs/|\.(agents-v0|cursor|gitlab|github)/|\.(gitlab-ci\.yml|agents-kit-version)$|.*\.(md|mdc|txt|adoc)$)' || true)"
              if [ -n "$stale" ]; then
                case "$phase" in
                  verify)
                    printf 'FAIL: non-doc files changed since evidence commit %s — re-run /v0-verify; set an Approved Verify row to Re-opened, then stamp %s on the new SHA\n' "$rep_commit" "$p" >&2
                    ;;
                  build)
                    printf 'FAIL: non-doc files changed since evidence commit %s — re-run /v0-build before using %s\n' "$rep_commit" "$p" >&2
                    ;;
                  *)
                    printf 'FAIL: non-doc files changed since evidence commit %s — re-run that phase before using %s\n' "$rep_commit" "$p" >&2
                    ;;
                esac
                missing=1
              fi
              art_state="${art%.md}.state.json"
              case "$art" in
                docs/agents-v0/onboarding/* | */docs/agents-v0/onboarding/*) art_state="docs/agents-v0/onboarding/state.json" ;;
                docs/agents-v0/maintain/* | */docs/agents-v0/maintain/*) art_state="$(dirname "$art")/state.json" ;;
              esac
              if git cat-file -e "${rep_commit}:${art_state}" 2>/dev/null; then
                rep_state="$(git show "${rep_commit}:${art_state}" 2>/dev/null || true)"
                if printf '%s' "$rep_state" | tr '\n' ' ' | grep -Eqi '"activePhase"[[:space:]]*:[[:space:]]*"'"$phase"'"' \
                  && printf '%s' "$rep_state" | tr '\n' ' ' | grep -Eqi '"activeStatus"[[:space:]]*:[[:space:]]*"(in_progress|awaiting_approval)"'; then
                  printf 'FAIL: commit: %s in %s records %s with activePhase=%s still in progress — record approval and sync state before committing the stamped tree\n' "$rep_commit" "$p" "$art_state" "$phase" >&2
                  missing=1
                fi
                if [ "$phase" = "build" ] && [ "$is_p0_unapproved" = "0" ] && [ -z "$(printf '%s' "$section" | grep -i '|[[:space:]]*release[[:space:]]*|' || true)" ]; then
                  rep_art="$(git show "${rep_commit}:${art}" 2>/dev/null || true)"
                  if ! printf '%s\n' "$rep_art" | grep -Eqi '\|[[:space:]]*build[[:space:]]*\|.*\|[[:space:]]*(approved|approve|yes|pass)([^a-z]|$)'; then
                    printf 'FAIL: commit: %s in %s does not contain the Approved build row in %s — record the Build approval before committing the stamped tree\n' "$rep_commit" "$p" "$art" >&2
                    missing=1
                  fi
                fi
              fi
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
    if [ "$is_p0_unapproved" = "1" ]; then
      printf 'FAIL: no concrete docs/ evidence path found for phase "%s" of %s\n' "$phase" "$art" >&2
    else
      printf 'FAIL: no concrete docs/ evidence path recorded in the "%s" row of %s\n' "$phase" "$art" >&2
    fi
    exit 1
  fi
fi

if [ "$missing" -eq 1 ]; then
  exit 1
fi
printf 'OK: %s evidence path(s) for phase "%s" exist in the repo\n' "$checked" "$phase"
