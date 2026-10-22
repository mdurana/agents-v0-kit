#!/bin/sh
# check-database-runtime.sh — find a database runtime for DB-backed tests WITHOUT root.
# Order: (1) a working container runtime (docker, then podman) for Testcontainers;
#        (2) embedded PostgreSQL declared by the build (e.g. io.zonky.test:embedded-postgres);
#        (3) a portable PostgreSQL on PATH or under $PG_HOME / $POSTGRES_HOME (initdb + pg_ctl);
#        (4) none: record the phase as blocked and report. Never install anything.
# Never run sudo/doas, a system package manager (apt, apt-get, dnf, yum, apk, zypper, pacman,
# brew, port), or point DOCKER_HOST at a TCP socket (127.0.0.1:2375/2376) to get a database.
#
# Usage:
#   sh .agents-v0/scripts/check-database-runtime.sh [--phase build|verify] [<requirements.md>]
#
# Prints one line `runtime=<container:docker|container:podman|embedded|portable:<bin-dir>|none>`.
# Exit 0 when a runtime is available; exit 3 when none is (the `Next:` line is the blocked command).
set -eu

phase=build
art=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) [ $# -ge 2 ] || { echo "usage: $0 [--phase build|verify] [<requirements.md>]" >&2; exit 2; }; phase="$2"; shift 2 ;;
    -h|--help) echo "usage: $0 [--phase build|verify] [<requirements.md>]"; exit 0 ;;
    *) art="$1"; shift ;;
  esac
done
case "$phase" in build|verify) ;; *) echo "--phase must be build or verify" >&2; exit 2 ;; esac

for rt in docker podman; do
  if command -v "$rt" >/dev/null 2>&1 && "$rt" info >/dev/null 2>&1; then
    echo "runtime=container:$rt"
    exit 0
  fi
done

for f in app/backend/pom.xml pom.xml app/backend/build.gradle build.gradle app/backend/build.gradle.kts build.gradle.kts; do
  if [ -f "$f" ] && grep -Eq 'embedded-postgres|zonky' "$f"; then
    echo "runtime=embedded"
    exit 0
  fi
done

for d in ${PG_HOME:+"$PG_HOME/bin"} ${POSTGRES_HOME:+"$POSTGRES_HOME/bin"}; do
  if [ -x "$d/initdb" ] && [ -x "$d/pg_ctl" ]; then
    echo "runtime=portable:$d"
    exit 0
  fi
done
if command -v initdb >/dev/null 2>&1 && command -v pg_ctl >/dev/null 2>&1; then
  echo "runtime=portable:$(dirname "$(command -v initdb)")"
  exit 0
fi

echo "runtime=none"
echo "FAIL: no container runtime, no embedded PostgreSQL in the build, and no portable PostgreSQL (initdb + pg_ctl). Do not install one and do not use sudo." >&2
if [ -n "$art" ]; then
  echo "Next: sh .agents-v0/scripts/sync-feature-state.sh --active-phase $phase --status blocked --reason \"Database runtime unavailable\" $art" >&2
else
  echo "Next: record --active-phase $phase --status blocked --reason \"Database runtime unavailable\" on the story, then report it to the user." >&2
fi
exit 3
