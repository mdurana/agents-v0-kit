#!/bin/sh
# check-layout-roots.sh — a green build must mean the checks ran.
#
# Usage: sh ci/check-layout-roots.sh [<profile-file>]
# Fails when a Maven or Gradle module exists (up to four levels deep) but
# ci/resolve-layout.sh resolved no JVM root (BACKEND_ROOT, BFF_ROOT, SERVICE_ROOTS).
# Without that, the build and gate-metrics loops run zero times and the job passes
# with nothing measured. Passes when there is no JVM module, or when a root resolved.

set -eu

here="$(cd "$(dirname "$0")" && pwd)"
profile_file="${1:-docs/project-profile.md}"

eval "$(sh "$here/resolve-layout.sh" "$profile_file")"
roots="$(printf '%s %s %s' "${BACKEND_ROOT:-}" "${BFF_ROOT:-}" "${SERVICE_ROOTS:-}" | tr -s ' ' | sed 's/^ //;s/ $//')"

found="$(find . -maxdepth 4 \( -name node_modules -o -name target -o -name .git \) -prune -o \
  \( -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null | head -n 1)"

if [ -n "$found" ] && [ -z "$roots" ]; then
  printf 'FAIL: found %s but ci/resolve-layout.sh resolved no JVM root. Set Profile / Backend root / Service roots in %s so CI builds and measures it.\n' "$found" "$profile_file" >&2
  exit 1
fi

if [ -n "$roots" ]; then
  printf 'OK: JVM roots resolved: %s\n' "$roots"
else
  printf 'OK: no JVM module in this repo\n'
fi
