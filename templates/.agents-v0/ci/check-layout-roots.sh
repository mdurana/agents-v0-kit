#!/bin/sh
# check-layout-roots.sh — a green build must mean the checks ran.
#
# Usage: sh .agents-v0/ci/check-layout-roots.sh [<profile-file>]
# Fails when a pack detect marker exists (up to four levels deep) but
# resolve-layout.sh resolved no backend root (BACKEND_ROOT, BFF_ROOT, SERVICE_ROOTS).
# Without that, the build and gate-metrics loops run zero times and the job passes
# with nothing measured. Passes when there is no backend marker, or when a root resolved.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
profile_file="${1:-docs/agents-v0/project-profile.md}"

eval "$(sh "$here/resolve-layout.sh" "$profile_file")"
roots="$(printf '%s %s %s' "${BACKEND_ROOT:-}" "${BFF_ROOT:-}" "${SERVICE_ROOTS:-}" | tr -s ' ' | sed 's/^ //;s/ $//')"

found="$(PACKLIB_DIR="$here" python3 - <<'PY'
import os
import sys
sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib
markers = packlib.marker_roots(".", 4)
print(markers[0] if markers else "")
PY
)"

if [ -n "$found" ] && [ -z "$roots" ]; then
  printf 'FAIL: found a pack marker at %s but resolve-layout.sh resolved no backend root. Set Profile / Backend root / Service roots in %s so CI builds and measures it.\n' "$found" "$profile_file" >&2
  exit 1
fi

if [ -n "$roots" ]; then
  printf 'OK: backend roots resolved: %s\n' "$roots"
else
  printf 'OK: no backend module in this repo\n'
fi
