#!/bin/sh
# audit-brownfield-baseline.sh — run the target repo baseline build/test and report status.
#
# Usage: audit-brownfield-baseline.sh [--record] [<target-repo>]
#
# /v0-onboard runs it with --record on a brownfield repo; /v0-build and /v0-maintain read the record it
# leaves. Without --record it only prints and writes nothing (build or maintain time, a manual check).
# Exit: 0 passed, 1 failed, 2 no build found, 3 --record could not write the record, 64 bad arguments.
# See docs/agents-v0/brownfield-onboarding.md.
#
# --record (onboard fix JO-15a) saves a short summary to docs/agents-v0/discovery/baseline-audit.txt:
# result, exit code, the commands run (credentials masked), commit, time with its offset in the project
# zone, and on a red result the failing test names. Names only, never build output (Sensei 2A, SOC-8).
# A red result is recorded and the exit code stays 1.
set -eu

RECORD=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --record) RECORD=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) printf 'FAIL: unknown option: %s (usage: audit-brownfield-baseline.sh [--record] [<target-repo>])\n' "$arg" >&2; exit 64 ;;
    *)
      [ -z "$TARGET" ] || { printf 'FAIL: more than one target given: %s\n' "$arg" >&2; exit 64; }
      TARGET="$arg" ;;
  esac
done
TARGET="${TARGET:-.}"
[ -d "$TARGET" ] || {
  printf 'FAIL: target not found: %s\n' "$TARGET" >&2
  exit 1
}

cd "$TARGET"
TARGET_ABS="$(pwd)"

# The audit itself. With --record it runs in a subshell whose output is also kept for the summary.
audit_main() {
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
if [ -f .agents-v0/scripts/resolve-layout.sh ]; then
  eval "$(PYTHONDONTWRITEBYTECODE=1 sh .agents-v0/scripts/resolve-layout.sh)"
  have_layout=1
fi

if [ -f .agents-v0/scripts/run-backend-verify.sh ]; then
  be_cmd="$(PYTHONDONTWRITEBYTECODE=1 sh .agents-v0/scripts/run-backend-verify.sh "Backend verify" || true)"
  svc_cmd="$(PYTHONDONTWRITEBYTECODE=1 sh .agents-v0/scripts/run-backend-verify.sh "Service verify" || true)"
  fe_cmd="$(PYTHONDONTWRITEBYTECODE=1 sh .agents-v0/scripts/run-backend-verify.sh "Frontend verify" || true)"
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
}

[ "$RECORD" = 1 ] || audit_main

# --- --record (JO-15a) ---------------------------------------------------------
REC_DIR="docs/agents-v0/discovery"
REC="$REC_DIR/baseline-audit.txt"
work="$(mktemp -d "${TMPDIR:-/tmp}/kit-baseline.XXXXXX")" || { printf 'FAIL: could not make a temp folder for --record\n' >&2; exit 3; }
# Removes only the temp folder made just above (its own log, stamp and draft files).
trap 'rm -rf "$work"' EXIT
trap 'rm -rf "$work"; trap - EXIT; exit 130' INT
trap 'rm -rf "$work"; trap - EXIT; exit 143' TERM
: > "$work/start"
# The subshell keeps set -e (no || around it) and leaves its exit code in $work/rc.
( trap 'printf "%s\n" "$?" > "$work/rc"' EXIT; audit_main ) 2>&1 | tee "$work/log"
rc="$(cat "$work/rc" 2>/dev/null || echo 1)"

case "$rc" in
  0) result=PASSED ;;
  2) result=NO-BUILD ;;
  *) result=FAILED ;;
esac
commit="$(git rev-parse HEAD 2>/dev/null || echo none)"
if [ "$commit" != none ]; then
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then tree=dirty; else tree=clean; fi
else
  tree=none
fi
# The project zone: the Timezone row of docs/agents-v0/project-profile.md, else the system zone.
tzname="$(awk -F'|' '
  { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c); lc = tolower(c) }
  lc == "timezone" || lc == "time zone" {
    v = $3; gsub(/<!--.*-->/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
    if (v != "" && v !~ /^</ && v !~ / /) print v
    exit
  }' docs/agents-v0/project-profile.md 2>/dev/null || :)"
# A zone name that is not a real zone would make date fall back to UTC silently, so check it first.
tz_known() {
  case "$1" in *..*|/*|*[!A-Za-z0-9_+/-]*) return 1 ;; esac
  [ -f "${TZDIR:-/usr/share/zoneinfo}/$1" ] && return 0
  command -v python3 >/dev/null 2>&1 &&
    PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys, zoneinfo; zoneinfo.ZoneInfo(sys.argv[1])' "$1" >/dev/null 2>&1
}
if [ -n "$tzname" ] && tz_known "$tzname"; then
  when="$(TZ="$tzname" date '+%Y-%m-%dT%H:%M:%S%z') ($tzname)"
elif [ -n "$tzname" ]; then
  printf "WARN: the Timezone row '%s' is not a known zone; the baseline record uses the system zone\n" "$tzname" >&2
  when="$(date '+%Y-%m-%dT%H:%M:%S%z') (system zone; the Timezone row '$tzname' is not a known zone)"
else
  when="$(date '+%Y-%m-%dT%H:%M:%S%z') (system zone)"
fi

# Mask credentials in a command line: user:password@ in URLs, secret-looking key=value or key:value pairs,
# the value after a secret-looking flag (--token X, -PapiKey X, -u X, --user X), and known token prefixes.
mask() {
  sed -E \
    -e 's#://[^/@[:space:]]+@#://***@#g' \
    -e 's#((^|[[:space:]])-{1,2}[A-Za-z0-9_.-]*([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss]([Ww][Oo][Rr][Dd])?|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll])[A-Za-z0-9_.-]*)[[:space:]]+[^-[:space:]][^[:space:]]*#\1 ***#g' \
    -e 's#((^|[[:space:]])(-u|--user))[[:space:]]+[^-[:space:]][^[:space:]]*#\1 ***#g' \
    -e 's#(([Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss]([Ww][Oo][Rr][Dd])?|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy])[A-Za-z0-9_.-]*[=:])[^[:space:]]+#\1***#g' \
    -e 's#(ghp_|gho_|ghs_|github_pat_|glpat-|xox[abpr]-|AKIA)[A-Za-z0-9_-]+#\1***#g'
}
# Failing test names from common runner lines (pytest, go, Maven, Gradle, dotnet) and fresh JUnit XML reports.
names() {
  sed -n -E \
    -e 's/^FAILED ([^[:space:]]+).*/\1/p' \
    -e 's/^[[:space:]]*--- FAIL: ([^[:space:]]+).*/\1/p' \
    -e 's/^\[ERROR\]   ([A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)+)(:[0-9]+)?([[:space:]].*)?$/\1/p' \
    -e 's/^([A-Za-z_$][A-Za-z0-9_$.]*) > ([^[:space:]]+) FAILED$/\1.\2/p' \
    -e 's/^[[:space:]]+Failed ([A-Za-z_][A-Za-z0-9_.]*) \[.*/\1/p' \
    "$work/log"
  command -v python3 >/dev/null 2>&1 || return 0
  find . \( -name .git -o -name node_modules \) -prune -o -type f -name 'TEST-*.xml' -newer "$work/start" -print 2>/dev/null |
    while IFS= read -r x; do
      PYTHONDONTWRITEBYTECODE=1 python3 -c '
import sys, xml.etree.ElementTree as ET
for tc in ET.parse(sys.argv[1]).getroot().iter("testcase"):
    if tc.find("failure") is not None or tc.find("error") is not None:
        cls, name = tc.get("classname", ""), tc.get("name", "")
        print(cls + "." + name if cls else name)
' "$x" 2>/dev/null || :
    done
}

{
  printf '# Baseline audit record, written by audit-brownfield-baseline.sh --record (JO-15a).\n'
  printf '# Summary only: no build output. Failing tests are listed by name.\n'
  printf 'result: %s\n' "$result"
  printf 'exit: %s\n' "$rc"
  printf 'commit: %s\n' "$commit"
  printf 'worktree: %s\n' "$tree"
  printf 'time: %s\n' "$when"
  cmds="$(sed -n -E 's/^--- (.*) ---$/\1/p' "$work/log" | grep -v '^layout root ' | mask | awk '!seen[$0]++')"
  if [ -n "$cmds" ]; then printf '%s\n' "$cmds" | sed 's/^/command: /'; else printf 'command: none\n'; fi
  if [ "$result" = FAILED ]; then
    names | awk 'NF && !seen[$0]++' > "$work/names"
    # Names only: a strict character set, at most 200 characters, and nothing that looks like a credential.
    grep -E '^[][A-Za-z0-9_.$:/#()-]{1,200}$' "$work/names" |
      grep -Ev '(ghp_|gho_|ghs_|github_pat_|glpat-|xox[abpr]-|AKIA[0-9A-Z]{8}|[A-Za-z0-9]{32,})' > "$work/kept" || :
    total="$(grep -c '' "$work/names" || :)"
    kept="$(grep -c '' "$work/kept" || :)"
    head -n 20 "$work/kept" | sed 's/^/failing-test: /'
    [ "$kept" -le 20 ] || printf 'failing-tests-more: %s\n' "$((kept - 20))"
    [ "$total" = "$kept" ] || printf 'failing-tests-withheld: %s\n' "$((total - kept))"
    [ "$total" != 0 ] || printf 'failing-tests: none recognized (read the build output)\n'
  fi
} > "$work/record"

tmpf="$REC_DIR/.baseline-audit.txt.$$"
if mkdir -p "$REC_DIR" 2>/dev/null && cp "$work/record" "$tmpf" 2>/dev/null && mv -f "$tmpf" "$REC" 2>/dev/null; then
  printf 'Baseline record: %s (%s)\n' "$REC" "$result"
else
  printf 'FAIL: could not write %s; onboard stops here\n' "$REC" >&2
  exit 3
fi
exit "$rc"
