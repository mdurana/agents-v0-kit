#!/bin/sh
# audit-brownfield-baseline.sh — run the target repo baseline build/test and report status.
#
# Usage: audit-brownfield-baseline.sh [<target-repo>]
#
# Use before /v0-build or /v0-maintain on brownfield repos. See docs/agents-v0/brownfield-onboarding.md.
set -eu

TARGET="${1:-.}"
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
  printf -- '--- %s -B clean verify ---\n' "$MVN"
  if "$MVN" -B clean verify; then
    printf 'OK: Maven verify passed\n'
  else
    printf 'FAIL: Maven verify failed — fix baseline before /v0-build or /v0-maintain\n'
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
  printf -- '--- %s clean check ---\n' "$GW"
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
    printf -- '--- npm run verify ---\n'
    if npm run verify; then
      printf 'OK: npm run verify passed\n'
    else
      printf 'FAIL: npm run verify failed\n'
      status=1
    fi
    return 0
  fi
  if grep -q '"test"' package.json 2>/dev/null; then
    printf -- '--- npm test ---\n'
    if npm test; then
      printf 'OK: npm test passed\n'
    else
      printf 'FAIL: npm test failed\n'
      status=1
    fi
    return 0
  fi
  if grep -q '"build"' package.json 2>/dev/null; then
    printf -- '--- npm run build ---\n'
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
      printf -- '--- pnpm run verify ---\n'
      pnpm run verify || status=1
    elif grep -q '"test"' package.json 2>/dev/null; then
      printf -- '--- pnpm test ---\n'
      pnpm test || status=1
    elif grep -q '"build"' package.json 2>/dev/null; then
      printf -- '--- pnpm run build ---\n'
      pnpm run build || status=1
    else
      run_npm
    fi
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    ran=1
    if grep -q '"verify"' package.json 2>/dev/null; then
      printf -- '--- yarn verify ---\n'
      yarn verify || status=1
    elif grep -q '"test"' package.json 2>/dev/null; then
      printf -- '--- yarn test ---\n'
      yarn test || status=1
    elif grep -q '"build"' package.json 2>/dev/null; then
      printf -- '--- yarn build ---\n'
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
  printf -- '--- layout root %s ---\n' "$root"
  if [ -f pom.xml ]; then
    run_maven
  fi
  if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    run_gradle
  fi
  if [ -f package.json ]; then
    run_node
  fi
  if [ -f go.mod ]; then
    if command -v go >/dev/null 2>&1; then
      ran=1
      printf -- '--- go test ./... ---\n'
      go test ./... || status=1
    else
      printf 'SKIP: go.mod present but go not on PATH\n'
    fi
  fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ]; then
    if command -v python3 >/dev/null 2>&1 && python3 -m pytest --version >/dev/null 2>&1; then
      ran=1
      printf -- '--- python3 -m pytest ---\n'
      python3 -m pytest || status=1
    else
      printf 'SKIP: pyproject.toml present but pytest not available\n'
    fi
  fi
  if find . -maxdepth 1 \( -name '*.csproj' -o -name '*.sln' \) -print 2>/dev/null | head -n 1 | grep -q .; then
    if command -v dotnet >/dev/null 2>&1; then
      ran=1
      printf -- '--- dotnet test ---\n'
      dt_out="$(mktemp)"
      if dotnet test >"$dt_out" 2>&1; then
        cat "$dt_out"
        if ! grep -Eqi 'Total tests:[[:space:]]*[1-9]|Passed![[:space:]]*-[[:space:]]*Failed:[[:space:]]*[0-9]+,[[:space:]]*Passed:[[:space:]]*[1-9]' "$dt_out"; then
          printf 'FAIL: dotnet test executed 0 tests — add a test project before /v0-build or /v0-maintain\n'
          status=1
        fi
      else
        cat "$dt_out"
        status=1
      fi
      rm -f "$dt_out"
    else
      printf 'SKIP: .NET project present but dotnet not on PATH\n'
    fi
  fi
  cd "$TARGET_ABS"
}

have_layout=0
if [ -f .agents-v0/ci/resolve-layout.sh ]; then
  eval "$(sh .agents-v0/ci/resolve-layout.sh)"
  have_layout=1
fi

if [ -f .agents-v0/ci/run-backend-verify.sh ]; then
  be_cmd="$(sh .agents-v0/ci/run-backend-verify.sh "Backend verify" || true)"
  svc_cmd="$(sh .agents-v0/ci/run-backend-verify.sh "Service verify" || true)"
  fe_cmd="$(sh .agents-v0/ci/run-backend-verify.sh "Frontend verify" || true)"
  if [ -n "$be_cmd" ] && { [ "$have_layout" = 0 ] || [ -n "${BACKEND_ROOT:-}" ] || { [ -z "${BFF_ROOT:-}" ] && [ -z "${SERVICE_ROOTS:-}" ]; }; }; then
    ran=1
    printf -- '--- Backend verify: %s ---\n' "$be_cmd"
    be_out="$(mktemp)"
    if sh -c "$be_cmd" >"$be_out" 2>&1; then
      cat "$be_out"
      case "$be_cmd" in
        *dotnet\ test*)
          if ! grep -Eqi 'Total tests:[[:space:]]*[1-9]|Passed![[:space:]]*-[[:space:]]*Failed:[[:space:]]*[0-9]+,[[:space:]]*Passed:[[:space:]]*[1-9]' "$be_out"; then
            printf 'FAIL: dotnet test executed 0 tests — add a test project before /v0-build or /v0-maintain\n'
            status=1
          fi
          ;;
      esac
    else
      cat "$be_out"
      status=1
    fi
    rm -f "$be_out"
  fi
  if [ -n "$svc_cmd" ]; then
    for r in ${BFF_ROOT:-} ${SERVICE_ROOTS:-}; do
      [ -n "$r" ] && [ -d "$r" ] || continue
      ran=1
      rcmd="$(printf '%s' "$svc_cmd" | sed "s|{root}|$r|g")"
      printf -- '--- Service verify (%s): %s ---\n' "$r" "$rcmd"
      sh -c "$rcmd" || status=1
    done
  fi
  if [ -n "$fe_cmd" ] && { [ "$have_layout" = 0 ] || [ -n "${FRONTEND_ROOT:-}" ]; }; then
    ran=1
    printf -- '--- Frontend verify: %s ---\n' "$fe_cmd"
    sh -c "$fe_cmd" || status=1
  fi
fi

if [ "$ran" = 0 ]; then
  if [ "$have_layout" = 1 ]; then
    printf 'Layout profile: %s\n' "${LAYOUT_PROFILE:-unset}"
    audit_root "${BACKEND_ROOT:-}"
    audit_root "${BFF_ROOT:-}"
    for svc in ${SERVICE_ROOTS:-}; do audit_root "$svc"; done
    audit_root "${FRONTEND_ROOT:-}"
  else
    audit_root "."
  fi
fi

if [ "$ran" = 0 ]; then
  printf 'WARN: no profile verify command or recognized build file — run your project verify command manually\n'
  printf 'See docs/agents-v0/brownfield-onboarding.md\n'
  exit 2
fi

printf '\n'
if [ "$status" -eq 0 ]; then
  printf 'Baseline audit: PASSED. Safe to proceed with gated delivery.\n'
else
  printf 'Baseline audit: FAILED. See docs/agents-v0/brownfield-onboarding.md (stabilization, local quality override, CVE suppressions).\n'
fi
exit "$status"
