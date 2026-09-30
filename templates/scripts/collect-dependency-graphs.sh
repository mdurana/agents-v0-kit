#!/bin/sh
# collect-dependency-graphs.sh — snapshot dependency graphs for brownfield discovery.
# Usage: sh scripts/collect-dependency-graphs.sh [repo-root]
set -eu
root="${1:-.}"
cd "$root"
mkdir -p docs/discovery
status=0

if [ -f pom.xml ]; then
  if [ -x ./mvnw ]; then MVN=./mvnw; elif command -v mvn >/dev/null 2>&1; then MVN=mvn; else MVN=""; fi
  if [ -n "$MVN" ]; then
    graph="$(pwd)/docs/discovery/dependency-graph.txt"
    : >"$graph"
    if ! "$MVN" -q dependency:tree -DoutputFile="$graph" -DappendOutput=true 2>/dev/null; then
      printf 'WARN: Maven dependency:tree failed\n' >&2
      status=1
    fi
    [ -s docs/discovery/dependency-graph.txt ] && printf 'Maven dependency tree -> docs/discovery/dependency-graph.txt\n'
  fi
fi

if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  if [ -x ./gradlew ]; then GW=./gradlew; elif command -v gradle >/dev/null 2>&1; then GW=gradle; else GW=""; fi
  if [ -n "$GW" ]; then
    if "$GW" -q dependencies >docs/discovery/gradle-graph.txt 2>/dev/null; then
      printf 'Gradle dependencies -> docs/discovery/gradle-graph.txt\n'
    else
      printf 'WARN: Gradle dependencies task failed\n' >&2
      status=1
    fi
  fi
fi

if [ -f package.json ]; then
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    pnpm ls --depth 2 >docs/discovery/package-graph.txt 2>/dev/null || status=1
  elif command -v npm >/dev/null 2>&1; then
    npm ls --all --omit=dev >docs/discovery/package-graph.txt 2>/dev/null || npm ls >docs/discovery/package-graph.txt 2>/dev/null || status=1
  fi
  [ -s docs/discovery/package-graph.txt ] && printf 'Node dependency list -> docs/discovery/package-graph.txt\n'
fi

exit "$status"
