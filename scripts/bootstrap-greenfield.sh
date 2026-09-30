#!/bin/sh
# bootstrap-greenfield.sh — install agents-v0 into a new repo and seed the P0 milestone manifest.
#
# Usage:
#   bootstrap-greenfield.sh [--tool cursor|kilo|claude|all] [--profile service|ui|app] <target-repo>
#
# Prerequisite: scaffold the application (Spring Initializr, create-svelte, etc.) so
# <target-repo> exists. See docs/greenfield-onboarding.md.
# --profile fills docs/project-profile.md Layout and verify commands when those
# cells are still placeholders. Omit it to infer service, ui, or app from the tree.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="all"
PROFILE=""
TARGET=""

usage() {
  printf 'usage: %s [--tool cursor|kilo|claude|all] [--profile service|ui|app] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tool)
      [ $# -ge 2 ] || usage
      TOOL="$2"
      shift 2
      ;;
    --profile)
      [ $# -ge 2 ] || usage
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

case "$TOOL" in
  cursor|kilo|claude|all) ;;
  *)
    printf 'error: unknown tool: %s\n' "$TOOL" >&2
    usage
    ;;
esac

case "$PROFILE" in
  ''|service|ui|app) ;;
  *)
    printf 'error: unknown profile: %s\n' "$PROFILE" >&2
    usage
    ;;
esac

[ -n "$TARGET" ] || usage
[ -d "$TARGET" ] || {
  printf 'error: target not found: %s (create/scaffold the repo first)\n' "$TARGET" >&2
  exit 1
}

TARGET_ABS="$(cd "$TARGET" && pwd)"

"$KIT/scripts/install.sh" --tool "$TOOL" --with-starters "$TARGET_ABS"

mkdir -p "$TARGET_ABS/docs/milestones"
for m in p0-platform-skeleton p1-contracts-and-data-models p2-mvp-core-features p3-feature-expansion p4-hardening p5-release-readiness; do
  dest="$TARGET_ABS/docs/milestones/$m.md"
  if [ ! -f "$dest" ]; then
    cp "$KIT/templates/docs/milestones/$m.md" "$dest"
    printf 'Seeded %s\n' "$dest"
  fi
done

has_jvm_at() {
  dir="$1"
  [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]
}

infer_profile() {
  be=0
  fe=0
  bff=0
  if has_jvm_at "$TARGET_ABS/backend"; then be=1; fi
  if [ -f "$TARGET_ABS/frontend/package.json" ]; then fe=1; fi
  if has_jvm_at "$TARGET_ABS/bff"; then bff=1; fi
  if [ "$be" = 1 ] && [ "$fe" = 1 ] && [ "$bff" = 1 ]; then
    printf 'app-bff\n'
  elif [ "$be" = 1 ] && [ "$fe" = 1 ]; then
    printf 'app\n'
  elif [ "$be" = 1 ] && [ "$bff" = 1 ]; then
    printf 'service-bff\n'
  elif [ "$be" = 1 ]; then
    printf 'service\n'
  elif [ "$fe" = 1 ]; then
    printf 'ui\n'
  elif [ "$bff" = 1 ]; then
    printf 'bff\n'
  else
    printf '\n'
  fi
}

layout_cell() {
  label="$1"
  file="$2"
  [ -f "$file" ] || return 0
  awk -F'|' -v label="$label" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      n = 0
      for (i = 1; i <= NF; i++) {
        c = trim($i)
        if (c != "") { n++; cell[n] = c }
      }
      if (n == 2 && cell[1] == label) { print cell[2]; exit }
    }
  ' "$file"
}

fill_layout() {
  chosen="$1"
  file="$TARGET_ABS/docs/project-profile.md"
  [ -f "$file" ] || {
    printf 'WARN: %s missing — Layout profile not recorded\n' "$file" >&2
    return 0
  }
  current="$(layout_cell Profile "$file" || true)"
  case "$current" in
    service|ui|app)
      printf 'Layout profile already set to %s (left unchanged)\n' "$current"
      return 0
      ;;
  esac
  case "$current" in
    *'<!--'*) ;;
    *)
      printf 'WARN: Layout Profile cell is not a placeholder — left unchanged\n' >&2
      return 0
      ;;
  esac
  if [ -z "$chosen" ]; then
    if has_jvm_at "$TARGET_ABS" || [ -f "$TARGET_ABS/package.json" ]; then
      printf 'Source at the repo root is not a greenfield layout. Move it under backend/, bff/, or frontend/, then re-run with --profile service|ui|app\n'
    else
      printf 'Layout profile not inferred. Re-run with --profile service|ui|app\n'
    fi
    return 0
  fi
  case "$chosen" in
    service)
      profile_name='service'
      backend_root='backend/'
      frontend_root='n/a'
      bff_root='n/a'
      backend_verify='cd backend && ./mvnw -B clean verify'
      backend_fast='cd backend && ./mvnw -B clean verify -P!ci-security'
      frontend_verify='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    service-bff)
      profile_name='service'
      backend_root='backend/'
      frontend_root='n/a'
      bff_root='bff/'
      backend_verify='cd backend && ./mvnw -B clean verify'
      backend_fast='cd backend && ./mvnw -B clean verify -P!ci-security'
      frontend_verify='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    bff)
      profile_name='service'
      backend_root='n/a'
      frontend_root='n/a'
      bff_root='bff/'
      backend_verify='cd bff && ./mvnw -B clean verify'
      backend_fast='cd bff && ./mvnw -B clean verify -P!ci-security'
      frontend_verify='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    ui)
      profile_name='ui'
      backend_root='n/a'
      frontend_root='frontend/'
      bff_root='n/a'
      backend_verify='n/a'
      backend_fast='n/a'
      frontend_verify='cd frontend && npm run verify'
      openapi='n/a'
      ;;
    app|app-bff)
      profile_name='app'
      backend_root='backend/'
      frontend_root='frontend/'
      if [ "$chosen" = app-bff ]; then bff_root='bff/'; else bff_root='n/a'; fi
      backend_verify='cd backend && ./mvnw -B clean verify'
      backend_fast='cd backend && ./mvnw -B clean verify -P!ci-security'
      frontend_verify='cd frontend && npm run verify'
      openapi='openapi/api-v1.yaml'
      ;;
  esac
  tmp="$(mktemp)"
  awk -F'|' \
    -v profile="$profile_name" \
    -v backend_root="$backend_root" \
    -v frontend_root="$frontend_root" \
    -v bff_root="$bff_root" \
    -v backend_verify="$backend_verify" \
    -v backend_fast="$backend_fast" \
    -v frontend_verify="$frontend_verify" \
    -v openapi="$openapi" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      n = 0
      for (i = 1; i <= NF; i++) {
        c = trim($i)
        if (c != "") { n++; a[n] = c }
      }
      if (n == 2 && a[2] ~ /<!--/) {
        repl = ""
        if (a[1] == "Profile") repl = profile
        else if (a[1] == "Backend root") repl = backend_root
        else if (a[1] == "Frontend root") repl = frontend_root
        else if (a[1] == "BFF root") repl = bff_root
        else if (a[1] == "OpenAPI") repl = openapi
        else if (a[1] == "Backend verify") repl = backend_verify
        else if (a[1] == "Backend verify (fast, no OWASP)") repl = backend_fast
        else if (a[1] == "Frontend verify") repl = frontend_verify
        if (repl != "") {
          printf "| %s | %s |\n", a[1], repl
          next
        }
      }
      if ($0 ~ /Approved OpenAPI:/ && $0 ~ /<!--/) {
        sub(/<!--[^>]*-->/, openapi)
      }
      print
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  printf 'Recorded layout profile %s in %s\n' "$chosen" "$file"
}

if [ -z "$PROFILE" ]; then
  PROFILE="$(infer_profile)"
fi
fill_layout "$PROFILE"

printf '\nGreenfield bootstrap complete.\n'
printf 'Next: wire Maven quality snippets from maven/ if Java; copy docker/Dockerfile.* to Dockerfile (see docker/README.md)\n'
printf '      run ./scripts/audit-brownfield-baseline.sh %s\n' "$TARGET_ABS"
printf 'Greenfield scaffold hardening: follow skill scaffold-service during P0 build stories.\n'
printf 'Then start P0 story P0-A with /intake in chat. Guide: docs/greenfield-onboarding.md\n'
