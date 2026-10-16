#!/bin/sh
# bootstrap-greenfield.sh — install agents-v0 into a new repo and seed the P0 milestone manifest.
#
# Usage:
#   bootstrap-greenfield.sh [--profile service|ui|app] [--pack <id>] [--scaffold-app] <target-repo>
#
# Prerequisite: <target-repo> exists (may be empty). --scaffold-app extracts
# templates/app/p0-platform-skeleton.tar.gz when --pack is omitted or is java.
# Any other --pack skips that archive and points at that pack's scaffold-service skill.
# Guide in the kit repo:
# templates/docs/agents-v0/greenfield-onboarding.md (installed as
# docs/agents-v0/greenfield-onboarding.md).
# --profile fills docs/agents-v0/project-profile.md Layout and verify commands when those
# cells are still placeholders. Omit it to infer service, ui, or app from the tree.
set -eu

KIT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE=""
PACK=""
SCAFFOLD_APP=0
TARGET=""

usage() {
  printf 'usage: %s [--profile service|ui|app] [--pack <id>] [--scaffold-app] <target-repo>\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      [ $# -ge 2 ] || usage
      PROFILE="$2"
      shift 2
      ;;
    --pack)
      [ $# -ge 2 ] || usage
      PACK="$2"
      shift 2
      ;;
    --scaffold-app)
      SCAFFOLD_APP=1
      shift
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

if [ -n "$PACK" ]; then
  "$KIT/scripts/install.sh" --with-starters --pack "$PACK" "$TARGET_ABS"
else
  "$KIT/scripts/install.sh" --with-starters "$TARGET_ABS"
fi

if [ "$SCAFFOLD_APP" = 1 ]; then
  if [ -z "$PACK" ] || [ "$PACK" = "java" ]; then
    scaffold_profile="$PROFILE"
    case "$scaffold_profile" in
      service|ui|app) ;;
      *) scaffold_profile=app ;;
    esac
    sh "$KIT/scripts/scaffold-app-template.sh" --profile "$scaffold_profile" "$TARGET_ABS"
  else
    printf 'Pack %s does not use the Java archive. Follow core/%s/skills/scaffold-service/SKILL.md for P0-A.\n' "$PACK" "$PACK"
  fi
fi

mkdir -p "$TARGET_ABS/docs/agents-v0/milestones"
for m in plan p0-platform-skeleton p1-contracts-and-data-models p2-mvp-core-features p3-feature-expansion p4-hardening p5-release-readiness; do
  dest="$TARGET_ABS/docs/agents-v0/milestones/$m.md"
  if [ ! -f "$dest" ]; then
    cp "$KIT/templates/docs/agents-v0/milestones/$m.md" "$dest"
    printf 'Seeded %s\n' "$dest"
  fi
done

load_markers() {
  MARKERS=""
  if [ ! -f "$TARGET_ABS/.agents-v0/ci/packlib.py" ]; then
    return 0
  fi
  MARKERS="$(PACKLIB_DIR="$TARGET_ABS/.agents-v0/ci" python3 - "$TARGET_ABS" <<'PY'
import os
import sys
os.chdir(sys.argv[1])
sys.path.insert(0, os.environ["PACKLIB_DIR"])
import packlib
print("\n".join(packlib.marker_roots(".", 4)))
PY
)"
}

has_backend_at() {
  rel="$1"
  case "$rel" in
    "$TARGET_ABS") rel="." ;;
    "$TARGET_ABS"/*) rel="${rel#"$TARGET_ABS"/}" ;;
  esac
  rel="${rel%/}"
  [ -n "${MARKERS:-}" ] || return 1
  printf '%s\n' "$MARKERS" | grep -Fxq -- "$rel"
}

apply_root() {
  cmd="$1"
  root="${2%/}"
  body="$(printf '%s\n' "$cmd" | sed -E 's/^cd[[:space:]]+[^[:space:]]+[[:space:]]+&&[[:space:]]+//')"
  printf 'cd %s && %s' "$root" "$body"
}

load_pack_commands() {
  PACK_VERIFY=""
  PACK_VERIFY_FAST=""
  UI_VERIFY=""
  UI_VERIFY_FAST=""
  if [ -z "$PACK" ] || [ ! -f "$KIT/core/$PACK/pack.json" ]; then
    return 0
  fi
  eval "$(python3 - "$KIT/core/$PACK/pack.json" "$KIT/core/ui" <<'PY'
import json
import os
import sys
pack = json.load(open(sys.argv[1], encoding="utf-8"))
ui = {}
ui_id = pack.get("ui") if isinstance(pack.get("ui"), str) else ""
ui_path = os.path.join(sys.argv[2], ui_id, "pack.json") if ui_id else ""
if ui_path and os.path.isfile(ui_path):
    ui = json.load(open(ui_path, encoding="utf-8"))

def quote(value):
    return "'" + str(value).replace("'", "'\"'\"'") + "'"

print("PACK_VERIFY=" + quote(pack.get("verify") or ""))
print("PACK_VERIFY_FAST=" + quote(pack.get("verifyFast") or ""))
print("UI_VERIFY=" + quote(ui.get("verify") or ""))
print("UI_VERIFY_FAST=" + quote(ui.get("verifyFast") or ""))
PY
)"
}

backend_verify_for() {
  root="$1"
  if [ -n "${PACK_VERIFY:-}" ]; then
    apply_root "$PACK_VERIFY" "$root"
  else
    printf 'cd %s && ./mvnw -B clean verify' "${root%/}"
  fi
}

backend_fast_for() {
  root="$1"
  if [ -n "${PACK_VERIFY_FAST:-}" ]; then
    apply_root "$PACK_VERIFY_FAST" "$root"
  else
    printf 'cd %s && ./mvnw -B clean verify -P!ci-security' "${root%/}"
  fi
}

frontend_verify_for() {
  root="$1"
  if [ -n "${UI_VERIFY:-}" ]; then
    apply_root "$UI_VERIFY" "$root"
  else
    printf 'cd %s && npm run verify' "${root%/}"
  fi
}

frontend_fast_for() {
  root="$1"
  if [ -n "${UI_VERIFY_FAST:-}" ]; then
    apply_root "$UI_VERIFY_FAST" "$root"
  else
    printf 'cd %s && npm test' "${root%/}"
  fi
}

infer_profile() {
  be=0
  fe=0
  bff=0
  if has_backend_at "$TARGET_ABS/app/backend" || has_backend_at "$TARGET_ABS/backend"; then be=1; fi
  if [ -f "$TARGET_ABS/app/frontend/package.json" ] || [ -f "$TARGET_ABS/frontend/package.json" ]; then fe=1; fi
  if has_backend_at "$TARGET_ABS/app/bff" || has_backend_at "$TARGET_ABS/bff"; then bff=1; fi
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

# Prefer an existing app/<name> module, else the repo-root module, else app/<name>.
module_root() {
  name="$1"
  kind="$2"
  if [ "$kind" = ui ]; then
    if [ -f "$TARGET_ABS/app/$name/package.json" ]; then
      printf 'app/%s/' "$name"
      return 0
    fi
    if [ -f "$TARGET_ABS/$name/package.json" ]; then
      printf '%s/' "$name"
      return 0
    fi
  else
    if has_backend_at "$TARGET_ABS/app/$name"; then
      printf 'app/%s/' "$name"
      return 0
    fi
    if has_backend_at "$TARGET_ABS/$name"; then
      printf '%s/' "$name"
      return 0
    fi
  fi
  printf 'app/%s/' "$name"
}

fill_layout() {
  chosen="$1"
  file="$TARGET_ABS/docs/agents-v0/project-profile.md"
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
    if has_backend_at "$TARGET_ABS" || [ -f "$TARGET_ABS/package.json" ]; then
      printf 'Source at the repo root is not a greenfield layout. Move it under app/backend/, app/bff/, or app/frontend/, then re-run with --profile service|ui|app\n'
    else
      printf 'Layout profile not inferred. Re-run with --profile service|ui|app\n'
    fi
    return 0
  fi
  case "$chosen" in
    service)
      profile_name='service'
      backend_root="$(module_root backend jvm)"
      frontend_root='n/a'
      bff_root='n/a'
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    service-bff)
      profile_name='service'
      backend_root="$(module_root backend jvm)"
      frontend_root='n/a'
      bff_root="$(module_root bff jvm)"
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    bff)
      profile_name='service'
      backend_root='n/a'
      frontend_root='n/a'
      bff_root="$(module_root bff jvm)"
      backend_verify="$(backend_verify_for "$bff_root")"
      backend_fast="$(backend_fast_for "$bff_root")"
      frontend_verify='n/a'
      frontend_fast='n/a'
      openapi='openapi/api-v1.yaml'
      ;;
    ui)
      profile_name='ui'
      backend_root='n/a'
      frontend_root="$(module_root frontend ui)"
      bff_root='n/a'
      backend_verify='n/a'
      backend_fast='n/a'
      frontend_verify="$(frontend_verify_for "$frontend_root")"
      frontend_fast="$(frontend_fast_for "$frontend_root")"
      openapi='n/a'
      ;;
    app|app-bff)
      profile_name='app'
      backend_root="$(module_root backend jvm)"
      frontend_root="$(module_root frontend ui)"
      if [ "$chosen" = app-bff ]; then bff_root="$(module_root bff jvm)"; else bff_root='n/a'; fi
      backend_verify="$(backend_verify_for "$backend_root")"
      backend_fast="$(backend_fast_for "$backend_root")"
      frontend_verify="$(frontend_verify_for "$frontend_root")"
      frontend_fast="$(frontend_fast_for "$frontend_root")"
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
    -v frontend_fast="$frontend_fast" \
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
        else if (a[1] == "Frontend verify (fast)") repl = frontend_fast
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

load_markers
load_pack_commands
if [ -z "$PROFILE" ]; then
  PROFILE="$(infer_profile)"
fi
fill_layout "$PROFILE"

printf '\nGreenfield bootstrap complete.\n'
if [ "$SCAFFOLD_APP" = 1 ] && [ -z "$PACK" ]; then
  printf 'No --pack was given. Extracted the java example archive templates/app/p0-platform-skeleton.tar.gz.\n'
  printf 'P0-A: prove AC-1–AC-4 with /v0-build (scaffold-service verifies; does not reinvent the skeleton).\n'
elif [ "$SCAFFOLD_APP" = 1 ] && [ "$PACK" = "java" ]; then
  printf 'Extracted the java example archive templates/app/p0-platform-skeleton.tar.gz.\n'
  printf 'P0-A: prove AC-1–AC-4 with /v0-build (scaffold-service verifies; does not reinvent the skeleton).\n'
elif [ "$SCAFFOLD_APP" = 1 ]; then
  printf 'P0-A: follow the %s scaffold-service skill. The Java archive was not extracted.\n' "$PACK"
else
  printf 'Next: add --scaffold-app on bootstrap, or scaffold externally, then harden with scaffold-service.\n'
  printf '      wire the reports named in pack.json; Pack java uses maven/. See docker/README.md\n'
fi
printf '      run ./scripts/audit-brownfield-baseline.sh %s\n' "$TARGET_ABS"
printf 'Then start P0-A with /v0-build or /v0-deliver. Guide: docs/agents-v0/greenfield-onboarding.md\n'
