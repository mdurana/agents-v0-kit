#!/bin/sh
# collect-dependency-graphs.sh — snapshot dependency graphs for brownfield discovery.
# Usage: sh scripts/collect-dependency-graphs.sh [repo-root]
# Layout-aware: runs under every root that ci/resolve-layout.sh resolves (the repo root when
# none resolve). Output per root in docs/discovery/:
#   dependency-graph.txt                  (root ".") or dependency-graph.<root>.txt   Maven tree
#   gradle-graph.txt / gradle-graph.<root>.txt
#   package-graph.txt / package-graph.<root>.txt
# A build file with no usable tool, or a tool that fails, is an error: the script says which
# root and exits 1 instead of leaving a silently empty graph.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="${1:-.}"
cd "$root"
mkdir -p docs/discovery
repo="$(pwd)"
status=0

ROOTS=""
if [ -f "$here/../ci/resolve-layout.sh" ]; then
  eval "$(sh "$here/../ci/resolve-layout.sh")"
  ROOTS="${BACKEND_ROOT:-} ${BFF_ROOT:-} ${SERVICE_ROOTS:-} ${FRONTEND_ROOT:-}"
fi
ROOTS="$(printf '%s' "$ROOTS" | tr -s ' ' | sed 's/^ //;s/ $//')"
[ -n "$ROOTS" ] || ROOTS="."

# suffix <root>: "" for the repo root, ".<root with / as ->" otherwise.
suffix() {
  if [ "$1" = "." ]; then printf ''; else printf '.%s' "$(printf '%s' "$1" | tr '/' '-')"; fi
}

for r in $ROOTS; do
  sfx="$(suffix "$r")"

  if [ -f "$r/pom.xml" ]; then
    if [ -x "$r/mvnw" ]; then MVN="$(cd "$r" && pwd)/mvnw"; elif [ -x ./mvnw ]; then MVN="$repo/mvnw"; elif command -v mvn >/dev/null 2>&1; then MVN=mvn; else MVN=""; fi
    graph="$repo/docs/discovery/dependency-graph$sfx.txt"
    if [ -z "$MVN" ]; then
      printf 'FAIL: %s has a pom.xml but neither mvnw nor mvn is available\n' "$r" >&2
      status=1
    else
      : >"$graph"
      if ! (cd "$r" && "$MVN" -q dependency:tree -DoutputFile="$graph" -DappendOutput=true >/dev/null 2>&1); then
        printf 'FAIL: dependency:tree failed under %s\n' "$r" >&2
        status=1
      elif [ -s "$graph" ]; then
        printf 'Maven dependency tree (%s) -> docs/discovery/dependency-graph%s.txt\n' "$r" "$sfx"
      else
        printf 'FAIL: dependency:tree under %s produced an empty graph\n' "$r" >&2
        status=1
      fi
    fi
  fi

  if [ -f "$r/build.gradle" ] || [ -f "$r/build.gradle.kts" ]; then
    if [ -x "$r/gradlew" ]; then GW="$(cd "$r" && pwd)/gradlew"; elif command -v gradle >/dev/null 2>&1; then GW=gradle; else GW=""; fi
    if [ -z "$GW" ]; then
      printf 'FAIL: %s has a Gradle build but neither gradlew nor gradle is available\n' "$r" >&2
      status=1
    elif (cd "$r" && "$GW" -q dependencies) >"docs/discovery/gradle-graph$sfx.txt" 2>/dev/null && [ -s "docs/discovery/gradle-graph$sfx.txt" ]; then
      printf 'Gradle dependencies (%s) -> docs/discovery/gradle-graph%s.txt\n' "$r" "$sfx"
    else
      printf 'FAIL: Gradle dependencies task failed or was empty under %s\n' "$r" >&2
      status=1
    fi
  fi

  if [ -f "$r/package.json" ]; then
    out="docs/discovery/package-graph$sfx.txt"
    if [ -f "$r/pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
      (cd "$r" && pnpm ls --depth 2) >"$out" 2>/dev/null || true
    elif command -v npm >/dev/null 2>&1; then
      (cd "$r" && npm ls --all --omit=dev) >"$out" 2>/dev/null || (cd "$r" && npm ls) >"$out" 2>/dev/null || true
    fi
    if [ -s "$out" ]; then
      printf 'Node dependency list (%s) -> %s\n' "$r" "$out"
    else
      printf 'FAIL: no usable npm/pnpm result under %s (run npm ci first)\n' "$r" >&2
      status=1
    fi
  fi
done

exit "$status"
