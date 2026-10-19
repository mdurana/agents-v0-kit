#!/bin/sh
# link-project.sh — pin a project at a kit commit without copying kit files.
#
# Usage:
#   link-project.sh --commit <sha> (--url <git-url> | --path <kit-dir>) [--force] <project>
#
# Writes docs/agents-v0/kit-pin. --url checks out that commit as a git submodule
# at kit/. --path records a local kit checkout and does not register a submodule.
# .cursor and .agents-v0/ci are symlinks into the kit checkout. The project's
# .agents-v0/packs/<id>/ stack pack is not touched. A later kit commit does not
# change the project until the pin moves. A project commit does not change the kit.

set -eu

COMMIT=""
URL=""
PATH_ARG=""
FORCE=0
PROJECT=""

usage() {
  printf 'usage: %s --commit <sha> (--url <git-url> | --path <kit-dir>) [--force] <project>\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --commit) COMMIT="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --path) PATH_ARG="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage ;;
    *) PROJECT="$1"; shift ;;
  esac
done

[ -n "$COMMIT" ] && [ -n "$PROJECT" ] || usage
[ -n "$URL" ] || [ -n "$PATH_ARG" ] || usage
[ -z "$URL" ] || [ -z "$PATH_ARG" ] || { printf 'FAIL: pass --url or --path, not both\n' >&2; exit 1; }
[ -d "$PROJECT" ] || { printf 'FAIL: project not found: %s\n' "$PROJECT" >&2; exit 1; }
PROJECT="$(cd "$PROJECT" && pwd)"

if [ -n "$URL" ]; then
  if [ ! -d "$PROJECT/kit" ]; then
    git -C "$PROJECT" submodule add "$URL" kit
  fi
  git -C "$PROJECT/kit" fetch --tags origin
  git -C "$PROJECT/kit" checkout "$COMMIT"
  pin_path=""
else
  [ -d "$PATH_ARG" ] || { printf 'FAIL: kit path not found: %s\n' "$PATH_ARG" >&2; exit 1; }
  abs="$(cd "$PATH_ARG" && pwd -P)"
  git -C "$abs" rev-parse --verify "${COMMIT}^{commit}" >/dev/null
  pin_path=""
  for project_base in "$(cd "$PROJECT" && pwd)" "$(cd "$PROJECT" && pwd -P)"; do
    candidate="$(python3 - "$project_base" "$abs" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)"
    case "$candidate" in
      /*) continue ;;
    esac
    if ( cd "$PROJECT" && [ -d "$candidate" ] ); then
      pin_path="$candidate"
      break
    fi
  done
  [ -n "$pin_path" ] || { printf 'FAIL: kit path is not a relative path from the project\n' >&2; exit 1; }
  pin_url="$(git -C "$abs" remote get-url origin 2>/dev/null || true)"
fi

mkdir -p "$PROJECT/docs/agents-v0"
pin="$PROJECT/docs/agents-v0/kit-pin"
{
  if [ -n "$URL" ]; then
    printf 'url: %s\n' "$URL"
  else
    printf 'local: yes\n'
    printf 'path: %s\n' "$pin_path"
    if [ -n "$pin_url" ]; then
      printf 'url: %s\n' "$pin_url"
    fi
  fi
  printf 'commit: %s\n' "$COMMIT"
} > "$pin"

resolver="$(cd "$(dirname "$0")/.." && pwd)/templates/.agents-v0/scripts/resolve-kit-root.sh"
root="$(cd "$PROJECT" && sh "$resolver")"

python3 - "$PROJECT" "$root" "$FORCE" <<'PY'
import os
import shutil
import sys

project, root, force = os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2]), sys.argv[3] == "1"


def link(src, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.lexists(dest):
        if os.path.islink(dest) or force:
            os.remove(dest)
        else:
            raise SystemExit(f"FAIL: {dest} exists and is not a symlink (pass --force)")
    os.symlink(os.path.relpath(src, os.path.dirname(dest)), dest)


def link_children(src_dir, dest_dir):
    if not os.path.isdir(src_dir):
        return
    for name in sorted(os.listdir(src_dir)):
        src = os.path.join(src_dir, name)
        dest = os.path.join(dest_dir, name)
        if os.path.isdir(src) and not os.path.islink(src):
            if os.path.lexists(dest) and not os.path.islink(dest) and not force:
                raise SystemExit(f"FAIL: {dest} exists and is not a symlink (pass --force)")
            if os.path.lexists(dest):
                if os.path.islink(dest) or os.path.isfile(dest):
                    os.remove(dest)
                else:
                    shutil.rmtree(dest)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            os.symlink(os.path.relpath(src, os.path.dirname(dest)), dest)
        elif os.path.isfile(src):
            link(src, dest)


link_children(os.path.join(root, "core", "common", "rules"), os.path.join(project, ".cursor", "rules", "org"))
link_children(os.path.join(root, "core", "common", "commands"), os.path.join(project, ".cursor", "commands"))
link_children(os.path.join(root, "core", "common", "agents"), os.path.join(project, ".cursor", "agents"))
link_children(os.path.join(root, "core", "common", "skills"), os.path.join(project, ".cursor", "skills"))
link_children(os.path.join(root, "core", "common", "hooks"), os.path.join(project, ".cursor", "hooks"))
hooks_json = os.path.join(root, "core", "common", "adapters", "cursor", "hooks.json")
if os.path.isfile(hooks_json):
    link(hooks_json, os.path.join(project, ".cursor", "hooks.json"))
cli_json = os.path.join(root, "core", "common", "adapters", "cursor", "cli.json")
if os.path.isfile(cli_json):
    link(cli_json, os.path.join(project, ".cursor", "cli.json"))
link_children(os.path.join(root, "templates", ".agents-v0", "ci"), os.path.join(project, ".agents-v0", "ci"))
link_children(os.path.join(root, "templates", ".agents-v0", "scripts"), os.path.join(project, ".agents-v0", "scripts"))

model_src = os.path.join(root, "templates", ".cursor", "model-config.json")
model_dest = os.path.join(project, ".cursor", "model-config.json")
if os.path.isfile(model_src) and not os.path.exists(model_dest):
    shutil.copyfile(model_src, model_dest)

profile_src = os.path.join(root, "templates", "docs", "agents-v0", "project-profile.md")
profile_dest = os.path.join(project, "docs", "agents-v0", "project-profile.md")
if os.path.isfile(profile_src) and not os.path.exists(profile_dest):
    shutil.copyfile(profile_src, profile_dest)
PY

printf 'Linked %s at %s\n' "$PROJECT" "$root"
printf 'Pack files stay in %s/.agents-v0/packs/<id>/\n' "$PROJECT"
printf 'Commit docs/agents-v0/kit-pin in the project. Do not commit kit files.\n'
if [ -z "$URL" ]; then
  printf 'WARN: --path is a local checkout. CI on another machine needs --url so the runner can fetch that commit.\n'
fi
