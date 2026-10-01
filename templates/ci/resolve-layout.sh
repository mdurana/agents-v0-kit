#!/bin/sh
# resolve-layout.sh — print directory-profile variables for eval.
#
# Usage: eval "$(sh ci/resolve-layout.sh [docs/project-profile.md])"
#
# Reads the two-column "This repo" rows under ## Layout. When Profile is
# service, ui, or app, those rows win. Otherwise detect pom.xml / package.json
# under backend/, frontend/, and bff/, and JVM modules under services/*/. A root
# pom.xml or package.json is a legacy tree only; greenfield profiles never put
# source at the repo root.
# Output variables: LAYOUT_PROFILE, BACKEND_ROOT, FRONTEND_ROOT, BFF_ROOT, and
# SERVICE_ROOTS (space-separated; one entry per deployable service when the repo
# holds more than one, e.g. "services/order services/inventory").
# Profiles: project-delivery-core.mdc.
set -eu

profile_file="${1:-docs/project-profile.md}"

is_placeholder() {
  case "$1" in
    *'<!--'*) return 0 ;;
  esac
  return 1
}

is_na() {
  case "$1" in
    '' | n/a | N/A | na | NA | '-' | '—') return 0 ;;
  esac
  return 1
}

# Relative path only. Reject absolute paths and parent segments.
safe_root() {
  r="$1"
  case "$r" in
    */) r="${r%/}" ;;
  esac
  case "$r" in
    /* | *..*) return 1 ;;
  esac
  case "$r" in
    *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  [ -n "$r" ] || return 1
  printf '%s\n' "$r"
}

cell() {
  label="$1"
  [ -f "$profile_file" ] || return 0
  awk -F'|' -v label="$label" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    {
      n = 0
      for (i = 1; i <= NF; i++) {
        c = trim($i)
        if (c != "") {
          n++
          cell[n] = c
        }
      }
      if (n == 2 && cell[1] == label) {
        print cell[2]
        exit
      }
    }
  ' "$profile_file"
}

emit() {
  printf "LAYOUT_PROFILE='%s'\n" "$1"
  printf "BACKEND_ROOT='%s'\n" "$2"
  printf "FRONTEND_ROOT='%s'\n" "$3"
  printf "BFF_ROOT='%s'\n" "$4"
  printf "SERVICE_ROOTS='%s'\n" "${5:-}"
}

# Comma-separated list of relative roots, printed space-separated.
normalize_list() {
  v="$1"
  if is_na "$v"; then
    return 0
  fi
  list="$(printf '%s\n' "$v" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  res=""
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    out="$(safe_root "$item")" || {
      printf 'FAIL: layout root is not a relative path: %s\n' "$item" >&2
      exit 1
    }
    res="${res:+$res }$out"
  done <<EOF
$list
EOF
  printf '%s\n' "$res"
}

has_jvm() {
  dir="$1"
  [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]
}

normalize() {
  v="$1"
  if is_na "$v"; then
    return 0
  fi
  out="$(safe_root "$v")" || {
    printf 'FAIL: layout root is not a relative path: %s\n' "$v" >&2
    exit 1
  }
  printf '%s\n' "$out"
}

profile="$(cell Profile || true)"
backend="$(cell "Backend root" || true)"
frontend="$(cell "Frontend root" || true)"
bff="$(cell "BFF root" || true)"
services="$(cell "Service roots" || true)"

if is_placeholder "$profile"; then profile=""; fi
if is_placeholder "$backend"; then backend=""; fi
if is_placeholder "$frontend"; then frontend=""; fi
if is_placeholder "$bff"; then bff=""; fi
if is_placeholder "$services"; then services=""; fi

case "$profile" in
  service | ui | app) ;;
  *) profile="" ;;
esac

if [ -n "$profile" ]; then
  case "$profile" in
    service) [ -n "$backend" ] || [ -n "$bff" ] || [ -n "$services" ] || backend="backend" ;;
    ui) [ -n "$frontend" ] || frontend="frontend" ;;
    app)
      [ -n "$backend" ] || [ -n "$services" ] || backend="backend"
      [ -n "$frontend" ] || frontend="frontend"
      ;;
  esac
fi

if [ -n "$profile" ] || [ -n "$backend" ] || [ -n "$frontend" ] || [ -n "$bff" ] || [ -n "$services" ]; then
  backend="$(normalize "$backend")"
  frontend="$(normalize "$frontend")"
  bff="$(normalize "$bff")"
  services="$(normalize_list "$services")"
  emit "$profile" "$backend" "$frontend" "$bff" "$services"
  exit 0
fi

# No profile: list JVM modules under services/*/ (one deployable service each).
auto_services=""
for d in services/*/; do
  [ -d "$d" ] || continue
  if has_jvm "${d%/}"; then
    auto_services="${auto_services:+$auto_services }${d%/}"
  fi
done

if has_jvm backend; then
  backend="backend"
  if [ -f frontend/package.json ]; then
    profile="app"
    frontend="frontend"
  else
    profile="service"
    frontend=""
  fi
  if has_jvm bff; then bff="bff"; else bff=""; fi
elif [ -n "$auto_services" ]; then
  if [ -f frontend/package.json ]; then
    profile="app"
    frontend="frontend"
  else
    profile="service"
  fi
  if has_jvm bff; then bff="bff"; fi
elif [ -f frontend/package.json ]; then
  profile="ui"
  frontend="frontend"
elif has_jvm bff; then
  profile="service"
  bff="bff"
elif has_jvm . || [ -f package.json ]; then
  if has_jvm .; then backend="."; fi
  if [ -f package.json ]; then frontend="."; fi
fi

# services/*/ modules are listed only when they are the backend tree: a repo with
# backend/ keeps that as its one backend root.
if has_jvm backend; then auto_services=""; fi

emit "$profile" "$backend" "$frontend" "$bff" "$auto_services"
