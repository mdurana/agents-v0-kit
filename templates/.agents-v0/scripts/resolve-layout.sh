#!/bin/sh
# resolve-layout.sh — print directory-profile variables for eval.
#
# Usage: eval "$(sh .agents-v0/scripts/resolve-layout.sh [docs/agents-v0/project-profile.md])"
#
# Reads the two-column "This repo" rows under ## Layout. When Profile is
# service, ui, or app, those rows win. Otherwise detect a pack marker
# (pom.xml, Gradle, *.csproj, go.mod, pyproject.toml, or a Nest/Express package.json)
# under app/backend/, app/frontend/, and app/bff/ (else backend/, frontend/, and bff/),
# and the same markers under app/services/*/ (else services/*/). A root
# marker or package.json is a legacy tree only; greenfield profiles never put
# source at the repo root.
# Output variables: LAYOUT_PROFILE, BACKEND_ROOT, FRONTEND_ROOT, BFF_ROOT, and
# SERVICE_ROOTS (space-separated; one entry per deployable service when the repo
# holds more than one, e.g. "services/order services/inventory").
# Profiles: project-delivery-core.mdc.
set -eu

profile_file="${1:-docs/agents-v0/project-profile.md}"

is_placeholder() {
  case "$1" in
    *'<!--'*) return 0 ;;
  esac
  return 1
}

is_na() {
  case "$1" in
    '' | n/a | N/A | na | NA | '-' | '—' | '–') return 0 ;;
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

# Directories that contain a pack detect marker. Loaded on first use so a filled
# Layout table does not need python3. Without python3, the five example markers
# still match so a JDK image can resolve a Maven tree.
LAYOUT_HERE="$(cd "$(dirname "$0")" && pwd)"
MARKERS=""
USE_PACK_MARKERS=0
markers_loaded=0

load_markers() {
  [ "$markers_loaded" = 1 ] && return 0
  markers_loaded=1
  if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$LAYOUT_HERE/packlib.py" ]; then
    return 0
  fi
  if MARKERS="$(PACKLIB_DIR="$LAYOUT_HERE" python3 - <<'PY'
import os
import sys
sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib
print("\n".join(packlib.marker_roots(".", 4)))
PY
)"; then
    USE_PACK_MARKERS=1
  else
    MARKERS=""
  fi
}

has_marker_shell() {
  dir="$1"
  if [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
    return 0
  fi
  [ -f "$dir/go.mod" ] && return 0
  [ -f "$dir/pyproject.toml" ] && return 0
  if find "$dir" -maxdepth 1 \( -name '*.csproj' -o -name '*.sln' \) -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  if [ -f "$dir/package.json" ] && grep -Eq '"(@nestjs/core|express)"' "$dir/package.json"; then
    return 0
  fi
  return 1
}

# A backend module is any directory marker_roots reported for the packs on disk.
has_marker() {
  dir="${1%/}"
  [ -d "$dir" ] || return 1
  load_markers
  if [ "$USE_PACK_MARKERS" = 1 ]; then
    [ -n "$MARKERS" ] || return 1
    printf '%s\n' "$MARKERS" | grep -Fxq -- "$dir"
    return $?
  fi
  has_marker_shell "$dir"
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
      if [ -z "$backend" ] && [ -z "$services" ]; then
        if has_marker "app/backend" || ! has_marker "backend"; then
          backend="app/backend"
        else
          backend="backend"
        fi
      fi
      if [ -z "$frontend" ]; then
        if [ -f app/frontend/package.json ] || [ ! -f frontend/package.json ]; then
          frontend="app/frontend"
        else
          frontend="frontend"
        fi
      fi
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

# No profile: prefer app/<module>, else the same name at the repo root.
# app/ itself is not a module. A pom.xml directly under app/ is not a root.
collect_services() {
  parent="$1"
  [ -d "$parent" ] || return 0
  for d in "$parent"/*/; do
    [ -d "$d" ] || continue
    mod="${d%/}"
    if has_marker "$mod"; then
      auto_services="${auto_services:+$auto_services }$mod"
    fi
  done
}

jvm_at() {
  if has_marker "app/$1"; then
    printf 'app/%s' "$1"
    return 0
  fi
  if has_marker "$1"; then
    printf '%s' "$1"
    return 0
  fi
  return 1
}

ui_at() {
  if [ -f app/frontend/package.json ]; then
    printf 'app/frontend'
    return 0
  fi
  if [ -f frontend/package.json ]; then
    printf 'frontend'
    return 0
  fi
  return 1
}

auto_services=""
collect_services app/services
if [ -z "$auto_services" ]; then
  collect_services services
fi

backend="$(jvm_at backend)" || backend=""
frontend="$(ui_at)" || frontend=""
bff="$(jvm_at bff)" || bff=""

if [ -n "$backend" ]; then
  if [ -n "$frontend" ]; then
    profile="app"
  else
    profile="service"
    frontend=""
  fi
elif [ -n "$auto_services" ]; then
  if [ -n "$frontend" ]; then
    profile="app"
  else
    profile="service"
  fi
elif [ -n "$frontend" ]; then
  profile="ui"
elif [ -n "$bff" ]; then
  profile="service"
elif has_marker . || [ -f package.json ]; then
  if has_marker .; then backend="."; fi
  if [ -f package.json ]; then
    if [ -z "$backend" ] || grep -Eq '"(react|svelte|@sveltejs/kit|vue|next|vite)"' package.json \
      || [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ] || [ -f go.mod ] || [ -f pyproject.toml ] \
      || find . -maxdepth 1 \( -name '*.csproj' -o -name '*.sln' \) -print -quit 2>/dev/null | grep -q .; then
      frontend="."
    fi
  fi
fi

# A backend module is the one backend root. Service roots apply only when it is absent.
if [ -n "$backend" ]; then auto_services=""; fi

emit "$profile" "$backend" "$frontend" "$bff" "$auto_services"
