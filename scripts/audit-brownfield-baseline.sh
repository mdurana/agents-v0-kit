#!/bin/sh
# audit-brownfield-baseline.sh — run the target repo baseline build/test and report status.
#
# Usage: audit-brownfield-baseline.sh <target-repo>
#
# Use before /build or /maintain on brownfield repos. See docs/brownfield-onboarding.md.
set -eu

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  printf 'usage: %s <target-repo>\n' "$(basename "$0")" >&2
  exit 1
fi
[ -d "$TARGET" ] || {
  printf 'FAIL: target not found: %s\n' "$TARGET" >&2
  exit 1
}

cd "$TARGET"
TARGET_ABS="$(pwd)"
printf 'Brownfield baseline audit: %s\n' "$TARGET_ABS"

ran=0
status=0

run_maven() {
  MVN=""
  if [ -x ./mvnw ]; then
    MVN=./mvnw
  elif command -v mvn >/dev/null 2>&1; then
    MVN=mvn
  else
    printf 'SKIP: pom.xml present but neither ./mvnw nor mvn on PATH\n'
    return 0
  fi
  ran=1
  printf '--- %s -B clean verify ---\n' "$MVN"
  if "$MVN" -B clean verify; then
    printf 'OK: Maven verify passed\n'
  else
    printf 'FAIL: Maven verify failed — fix baseline before /build or /maintain\n'
    status=1
  fi
}

run_gradle() {
  GW=""
  if [ -x ./gradlew ]; then
    GW=./gradlew
  elif command -v gradle >/dev/null 2>&1; then
    GW=gradle
  else
    printf 'SKIP: build.gradle(.kts) present but neither ./gradlew nor gradle on PATH\n'
    return 0
  fi
  ran=1
  printf '--- %s clean check ---\n' "$GW"
  if "$GW" clean check; then
    printf 'OK: Gradle check passed\n'
  else
    printf 'FAIL: Gradle check failed\n'
    status=1
  fi
}

run_npm() {
  if ! command -v npm >/dev/null 2>&1; then
    printf 'SKIP: package.json present but npm not on PATH\n'
    return 0
  fi
  ran=1
  if grep -q '"verify"' package.json 2>/dev/null; then
    printf '--- npm run verify ---\n'
    if npm run verify; then
      printf 'OK: npm run verify passed\n'
    else
      printf 'FAIL: npm run verify failed\n'
      status=1
    fi
    return 0
  fi
  if grep -q '"test"' package.json 2>/dev/null; then
    printf '--- npm test ---\n'
    if npm test; then
      printf 'OK: npm test passed\n'
    else
      printf 'FAIL: npm test failed\n'
      status=1
    fi
    return 0
  fi
  if grep -q '"build"' package.json 2>/dev/null; then
    printf '--- npm run build ---\n'
    if npm run build; then
      printf 'OK: npm run build passed\n'
    else
      printf 'FAIL: npm run build failed\n'
      status=1
    fi
    return 0
  fi
  printf 'SKIP: package.json has no verify, test, or build script\n'
}

run_node() {
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    ran=1
    if grep -q '"verify"' package.json 2>/dev/null; then
      printf '--- pnpm run verify ---\n'
      pnpm run verify || status=1
    elif grep -q '"test"' package.json 2>/dev/null; then
      printf '--- pnpm test ---\n'
      pnpm test || status=1
    elif grep -q '"build"' package.json 2>/dev/null; then
      printf '--- pnpm run build ---\n'
      pnpm run build || status=1
    else
      run_npm
    fi
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    ran=1
    if grep -q '"verify"' package.json 2>/dev/null; then
      printf '--- yarn verify ---\n'
      yarn verify || status=1
    elif grep -q '"test"' package.json 2>/dev/null; then
      printf '--- yarn test ---\n'
      yarn test || status=1
    elif grep -q '"build"' package.json 2>/dev/null; then
      printf '--- yarn build ---\n'
      yarn build || status=1
    else
      run_npm
    fi
  else
    run_npm
  fi
}

seen_roots=" "
audit_root() {
  root="$1"
  [ -n "$root" ] || return 0
  case "$seen_roots" in
    *" $root "*) return 0 ;;
  esac
  seen_roots="$seen_roots$root "
  if [ ! -d "$TARGET_ABS/$root" ]; then
    printf 'SKIP: layout root not found: %s\n' "$root"
    return 0
  fi
  cd "$TARGET_ABS/$root"
  printf '--- layout root %s ---\n' "$root"
  if [ -f pom.xml ]; then
    run_maven
  fi
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    run_gradle
  fi
  if [ -f package.json ]; then
    run_node
  fi
  cd "$TARGET_ABS"
}

if [ -f ci/resolve-layout.sh ]; then
  eval "$(sh ci/resolve-layout.sh)"
  printf 'Layout profile: %s\n' "${LAYOUT_PROFILE:-unset}"
  audit_root "${BACKEND_ROOT:-}"
  audit_root "${BFF_ROOT:-}"
  audit_root "${FRONTEND_ROOT:-}"
else
  audit_root "."
fi

if [ "$ran" = 0 ]; then
  printf 'WARN: no pom.xml, Gradle build, or package.json — run your project verify command manually\n'
  printf 'See docs/brownfield-onboarding.md\n'
  exit 2
fi

printf '\n'
if [ "$status" -eq 0 ]; then
  printf 'Baseline audit: PASSED. Safe to proceed with gated delivery.\n'
else
  printf 'Baseline audit: FAILED. See docs/brownfield-onboarding.md (stabilization, local quality override, CVE suppressions).\n'
fi
exit "$status"
