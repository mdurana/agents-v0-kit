#!/bin/sh
# check-installed-kit.sh — prove that a project's installed kit is this kit, byte for byte, with no
# AGENTS_V0_* override code (kitfix-20261031-installed-no-overrides).
#   sh scripts/check-installed-kit.sh [--expect-trace-mode warn|fail] <project checkout>
# For every file in templates/.agents-v0/scripts the installed copy must equal the kit file after
# strip-test-overrides.sh; every file in core/common/hooks must equal .agents/hooks/<file> (and
# .cursor/hooks/<file> when that adapter is installed). No installed script may still read an
# AGENTS_V0_* variable (comments and the kit-fetch switch AGENTS_V0_FETCH_KIT of resolve-kit-root.sh
# excepted). With --expect-trace-mode, check-traceability.sh --print-mode in the project must report
# that mode. Retired kit files (scripts/lib/retired-files.txt): RETIRED-LEFT <path> for an unedited one still
# in place (a failure), WARN RETIRED-EDITED <path> for an edited copy (not a failure). Prints one line per
# problem, then `HASH-OK files=<n> trace_mode=<m>` (exit 0) or
# `HASH-FAIL ...` (exit 1). Read-only: it changes nothing.
set -eu
KIT="$(cd "$(dirname "$0")/.." && pwd)"
want=""
if [ "${1:-}" = --expect-trace-mode ]; then want="${2:-}"; shift 2 || true; fi
P="${1:-}"
[ -n "$P" ] && [ -d "$P/.agents-v0/scripts" ] || { printf 'usage: %s [--expect-trace-mode warn|fail] <project checkout>\n' "$0" >&2; exit 2; }
case "$want" in ""|warn|fail) ;; *) printf 'error: --expect-trace-mode must be warn or fail\n' >&2; exit 2 ;; esac
bad=0; n=0
# Retired kit files (N12A, Sensei 00:52): an unedited one still in place fails; an edited copy only warns.
. "$KIT/scripts/lib/retired-files.sh"
RETIRED_LIST="$KIT/scripts/lib/retired-files.txt"
h() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
for f in "$KIT"/templates/.agents-v0/scripts/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"; i="$P/.agents-v0/scripts/$b"
  case "$b" in *.pyc|*.bak) continue ;; esac
  rf_listed ".agents-v0/scripts/$b" "$RETIRED_LIST" 2>/dev/null && continue
  if [ ! -e "$i" ]; then
    # not part of the default install (check-delivery-gate-local.sh is removed on --update; run-local-container.sh
    # comes with --with-starters only)
    case "$b" in check-delivery-gate-local.sh|run-local-container.sh) continue ;; esac
    printf 'MISSING .agents-v0/scripts/%s\n' "$b"; bad=1; continue
  fi
  n=$((n + 1))
  exp="$(sh "$KIT/scripts/strip-test-overrides.sh" "$f" | h)" || { printf 'BAD-MARKERS %s\n' "$b"; bad=1; continue; }
  got="$(h < "$i")"
  if [ "$exp" != "$got" ]; then
    if [ "$(h < "$f")" = "$got" ]; then printf 'TEST-OVERRIDES-INSTALLED .agents-v0/scripts/%s (reads AGENTS_V0_* overrides)\n' "$b"
    else printf 'DIFF .agents-v0/scripts/%s\n' "$b"; fi
    bad=1
  fi
done
for d in .agents/hooks .cursor/hooks; do
  [ -d "$P/$d" ] || continue
  for f in "$KIT"/core/common/hooks/*; do
    [ -f "$f" ] || continue
    b="${f##*/}"; n=$((n + 1))
    if [ ! -e "$P/$d/$b" ]; then printf 'MISSING %s/%s\n' "$d" "$b"; bad=1
    elif [ "$(h < "$f")" != "$(h < "$P/$d/$b")" ]; then printf 'DIFF %s/%s\n' "$d" "$b"; bad=1; fi
  done
done
rf_status "$P" "$RETIRED_LIST" || bad=1
# no installed script may read an AGENTS_V0_* variable (comments and AGENTS_V0_FETCH_KIT excepted)
for i in "$P"/.agents-v0/scripts/*; do
  [ -f "$i" ] || continue
  hits="$(grep -n 'AGENTS_V0_' "$i" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v 'AGENTS_V0_FETCH_KIT' || true)"
  if [ -n "$hits" ]; then printf '%s\n' "$hits" | sed "s|^|ENV-READ ${i#$P/}:|"; bad=1; fi
  if grep -q 'kit-test-override' "$i"; then printf 'MARKER-LEFT %s\n' "${i#$P/}"; bad=1; fi
done
mode="$(cd "$P" && sh .agents-v0/scripts/check-traceability.sh --print-mode 2>/dev/null | sed -n 's/^trace_mode=\([a-z]*\).*/\1/p')" || mode=""
if [ -n "$want" ] && [ "$mode" != "$want" ]; then printf 'TRACE-MODE %s (expected %s; set trace_mode=%s in .agents-v0/policy.conf)\n' "${mode:-unknown}" "$want" "$want"; bad=1; fi
if [ "$bad" = 0 ]; then printf 'HASH-OK files=%s trace_mode=%s kit=%s\n' "$n" "${mode:-unknown}" "$(git -C "$KIT" rev-parse --short=12 HEAD 2>/dev/null || echo '?')"; exit 0; fi
printf 'HASH-FAIL files=%s trace_mode=%s\n' "$n" "${mode:-unknown}"; exit 1
