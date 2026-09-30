#!/bin/sh
# resolve-layout.sh — print directory-profile variables for eval.
#
# Usage: eval "$(sh ci/resolve-layout.sh [docs/project-profile.md])"
#
# Reads the two-column "This repo" rows under ## Layout. When Profile is
# service, ui, or app, those rows win. Otherwise detect pom.xml / package.json
# under backend/, frontend/, and bff/. A root pom.xml or package.json is a legacy
# tree only; greenfield profiles never put source at the repo root.
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

if is_placeholder "$profile"; then profile=""; fi
if is_placeholder "$backend"; then backend=""; fi
if is_placeholder "$frontend"; then frontend=""; fi
if is_placeholder "$bff"; then bff=""; fi

case "$profile" in
  service | ui | app) ;;
  *) profile="" ;;
esac

if [ -n "$profile" ]; then
  case "$profile" in
    service) [ -n "$backend" ] || [ -n "$bff" ] || backend="backend" ;;
    ui) [ -n "$frontend" ] || frontend="frontend" ;;
    app)
      [ -n "$backend" ] || backend="backend"
      [ -n "$frontend" ] || frontend="frontend"
      ;;
  esac
fi

if [ -n "$profile" ] || [ -n "$backend" ] || [ -n "$frontend" ] || [ -n "$bff" ]; then
  backend="$(normalize "$backend")"
  frontend="$(normalize "$frontend")"
  bff="$(normalize "$bff")"
  emit "$profile" "$backend" "$frontend" "$bff"
  exit 0
fi

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

emit "$profile" "$backend" "$frontend" "$bff"
