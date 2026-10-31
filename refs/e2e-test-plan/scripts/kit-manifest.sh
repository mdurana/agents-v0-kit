#!/usr/bin/env bash
# kit-manifest.sh — write the manifest of a verified installed kit, before the kit source is locked away from the
# agent user (kitfix-20261031-kit-source-lock, v3-rerun-procedure.md §4).
#   bash scripts/kit-manifest.sh <checkout> <manifest file> [<kit root>]
# <kit root> defaults to the kit checkout this harness sits in (../.. from refs/e2e-test-plan). The manifest is
# written only when `check-installed-kit.sh --expect-trace-mode fail` (or, if the checkout has no policy.conf yet,
# without --expect-trace-mode) says HASH-OK. It lists "<relpath>\t<sha256>" of the installed .agents-v0/scripts,
# .agents-v0/hooks and agent hooks (policy.conf excluded: the harness writes it), with a "# kit=<sha> ..." header.
# The harness (KIT_MANIFEST=<file>) then checks main and every worktree against it, with no kit source needed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="${1:?usage: kit-manifest.sh <checkout> <manifest file> [<kit root>]}"; OUT="${2:?manifest file}"
K="${3:-$(cd "$HERE/../.." && pwd)}"
sha256_cmd(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
# shellcheck disable=SC1091
. "$HERE/scripts/lib.sh" >/dev/null 2>&1 || true
type kit_manifest_lines >/dev/null 2>&1 || { echo "kit-manifest: cannot load kit_manifest_lines from lib.sh" >&2; exit 1; }
if [ -f "$W/.agents-v0/policy.conf" ]; then chk="$(sh "$K/scripts/check-installed-kit.sh" --expect-trace-mode fail "$W" 2>&1)" || { printf '%s\n' "$chk" >&2; echo "kit-manifest: not HASH-OK, no manifest written" >&2; exit 1; }
else chk="$(sh "$K/scripts/check-installed-kit.sh" "$W" 2>&1)" || { printf '%s\n' "$chk" >&2; echo "kit-manifest: not HASH-OK, no manifest written" >&2; exit 1; }; fi
[ ! -e "$OUT" ] || { mkdir -p "$(dirname "$OUT")/trash"; mv "$OUT" "$(dirname "$OUT")/trash/$(basename "$OUT").$(date +%Y%m%d%H%M%S)"; }
{ printf '# kit=%s written=%s from=%s\n' "$(git -C "$K" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" "$(TZ=Asia/Manila date '+%Y-%m-%d %H:%M') Asia/Manila" "$W"
  printf '# %s\n' "$(printf '%s\n' "$chk" | tail -1)"
  kit_manifest_lines "$W"; } > "$OUT"
echo "kit-manifest: $(grep -vc '^#' "$OUT") files -> $OUT ($(printf '%s\n' "$chk" | tail -1))"
