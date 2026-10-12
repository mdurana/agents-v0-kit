#!/bin/sh
# activate-stack-pack.sh — bind one backend pack and install its rules and skills.
#
# Usage (from the target repo):
#   sh .agents-v0/scripts/activate-stack-pack.sh <java|dotnet|node|python|go> [--force]
#   sh .agents-v0/scripts/activate-stack-pack.sh --detect [--force]
#
# Writes the Pack row and still-placeholder stack and verify cells in
# docs/agents-v0/project-profile.md from .agents-v0/packs/<id>/PACK.md
# (or core/packs when this script is run from a kit checkout). Copies that
# pack's rules into .cursor/rules/org and its skills into .cursor/skills, and
# removes the other packs' rules and skills. A Pack cell that already names a
# different pack is left unchanged unless --force is set. --detect reads the
# tree and refuses when more than one backend marker is present.
#
# Exit 0 bound, 2 refused to replace, 3 ambiguous detect, 1 usage or missing pack.

set -eu

FORCE=0
DETECT=0
REQUESTED=""

usage() {
  printf 'usage: %s [--detect] [--force] [<java|dotnet|node|python|go>]\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --detect) DETECT=1; shift ;;
    -h|--help) usage ;;
    java|dotnet|node|python|go) REQUESTED="$1"; shift ;;
    *) usage ;;
  esac
done

if [ "$DETECT" = 0 ] && [ -z "$REQUESTED" ]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../packs/java/PACK.md" ]; then
  PACKS="$(cd "$SCRIPT_DIR/../packs" && pwd)"
elif [ -f "$SCRIPT_DIR/../../../core/packs/java/PACK.md" ]; then
  PACKS="$(cd "$SCRIPT_DIR/../../../core/packs" && pwd)"
else
  printf 'FAIL: no pack library (.agents-v0/packs or core/packs)\n' >&2
  exit 1
fi

KIT_RULES=""
KIT_SKILLS=""
if [ -d "$SCRIPT_DIR/../../../core/rules" ]; then
  KIT_RULES="$(cd "$SCRIPT_DIR/../../../core/rules" && pwd)"
  KIT_SKILLS="$(cd "$SCRIPT_DIR/../../../core/skills" && pwd)"
fi

export ACTIVATE_PACKS="$PACKS" ACTIVATE_FORCE="$FORCE" ACTIVATE_DETECT="$DETECT" \
  ACTIVATE_REQUESTED="$REQUESTED" ACTIVATE_RULES="$KIT_RULES" ACTIVATE_SKILLS="$KIT_SKILLS"

python3 - <<'PY'
import glob
import json
import os
import re
import shutil
import sys

packs_root = os.environ["ACTIVATE_PACKS"]
force = os.environ["ACTIVATE_FORCE"] == "1"
detect = os.environ["ACTIVATE_DETECT"] == "1"
requested = os.environ["ACTIVATE_REQUESTED"]
kit_rules = os.environ.get("ACTIVATE_RULES") or ""
kit_skills = os.environ.get("ACTIVATE_SKILLS") or ""
allowed = ("java", "dotnet", "node", "python", "go")
profile_path = os.path.join("docs", "agents-v0", "project-profile.md")
skip_dirs = {
    ".git", "node_modules", "target", "dist", "build", ".next", "bin", "obj",
    ".venv", "venv", "__pycache__",
}


def fail(message, code):
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(code)


def pack_file(pack_id):
    path = os.path.join(packs_root, pack_id, "PACK.md")
    if not os.path.isfile(path):
        fail(f"missing pack file {path}", 1)
    return path


def fields_of(pack_id):
    fields = {}
    for line in open(pack_file(pack_id), encoding="utf-8"):
        match = re.match(r"- \*\*([^*]+):\*\*\s*(.*)", line)
        if match:
            fields[match.group(1).strip()] = match.group(2).strip()
    if fields.get("Id") != pack_id:
        fail(f"{pack_id} PACK.md Id is {fields.get('Id')!r}", 1)
    return fields


def read_profile():
    if os.path.isfile(profile_path):
        return open(profile_path, encoding="utf-8").read()
    fail(f"missing {profile_path}", 1)


def section(text, heading):
    marker = f"## {heading}"
    if marker not in text:
        return None
    body = text.split(marker, 1)[1]
    nxt = body.find("\n## ")
    if nxt == -1:
        return body
    return body[:nxt]


def row_value(text, heading, name):
    body = section(text, heading)
    if body is None:
        return None
    for line in body.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and cells[0] == name and len(cells) > 1:
            return cells[1]
    return None


def placeholder(value):
    return value is None or value == "" or "<!--" in value


def current_pack(text):
    value = row_value(text, "Stack", "Pack")
    if value in allowed:
        return value
    return ""


def set_row(text, heading, name, value, overwrite):
    marker = f"## {heading}"
    if marker not in text:
        fail(f"{profile_path} has no {marker} section", 1)
    before, rest = text.split(marker, 1)
    nxt = rest.find("\n## ")
    if nxt == -1:
        body, after = rest, ""
    else:
        body, after = rest[:nxt], rest[nxt:]
    lines = body.splitlines(keepends=True)
    found = False
    out = []
    for line in lines:
        if line.startswith("|"):
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if cells and cells[0] == name and len(cells) > 1:
                found = True
                if overwrite or placeholder(cells[1]):
                    line = f"| {name} | {value} |\n"
        out.append(line if line.endswith("\n") else line + "\n")
    if not found and name == "Pack":
        inserted = False
        rebuilt = []
        for line in out:
            rebuilt.append(line)
            if not inserted and re.match(r"^\|[-: |]+\|\s*$", line):
                rebuilt.append(f"| Pack | {value} |\n")
                inserted = True
        if not inserted:
            fail("Stack table has no header row to attach Pack", 1)
        out = rebuilt
    elif not found:
        fail(f"{profile_path} ## {heading} has no {name} row", 1)
    return before + marker + "".join(out) + after


def detect_pack():
    found = set()
    for dirpath, dirnames, filenames in os.walk("."):
        dirnames[:] = [name for name in dirnames if name not in skip_dirs and not name.startswith(".agents")]
        for name in filenames:
            if name == "pom.xml":
                found.add("java")
            elif name.endswith(".csproj") or name.endswith(".sln"):
                found.add("dotnet")
            elif name == "go.mod":
                found.add("go")
            elif name == "pyproject.toml":
                found.add("python")
            elif name == "package.json":
                path = os.path.join(dirpath, name)
                try:
                    data = json.load(open(path, encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    continue
                deps = {}
                for key in ("dependencies", "devDependencies"):
                    deps.update(data.get(key) or {})
                if "@nestjs/core" in deps or "express" in deps:
                    found.add("node")
    if not found:
        fail("no java, dotnet, node, python, or go backend marker", 3)
    if len(found) > 1:
        fail("ambiguous backend markers: " + ", ".join(sorted(found)), 3)
    return found.pop()


def frontmatter_pack(path):
    pack = ""
    with open(path, encoding="utf-8") as handle:
        first = handle.readline()
        if first.strip() != "---":
            return ""
        for line in handle:
            if line.strip() == "---":
                break
            if line.startswith("pack:"):
                pack = line.split(":", 1)[1].strip()
    return pack


def materialize(pack_id):
    """Rules and skills for one pack: the installed pack dir, or the kit source."""
    rules = sorted(glob.glob(os.path.join(packs_root, pack_id, "rules", "*.mdc")))
    skills = sorted(glob.glob(os.path.join(packs_root, pack_id, "skills", "*", "SKILL.md")))
    if rules or skills or not kit_rules:
        return rules, skills
    rules = [
        path for path in glob.glob(os.path.join(kit_rules, "*.mdc"))
        if frontmatter_pack(path) == pack_id
    ]
    skills = [
        path for path in glob.glob(os.path.join(kit_skills, "*", "SKILL.md"))
        if frontmatter_pack(path) == pack_id
    ]
    return rules, skills


def install_cursor(pack_id):
    os.makedirs(os.path.join(".cursor", "rules", "org"), exist_ok=True)
    os.makedirs(os.path.join(".cursor", "skills"), exist_ok=True)
    selected_rules, selected_skills = materialize(pack_id)
    other_rule_names = set()
    other_skill_names = set()
    for other in allowed:
        if other == pack_id:
            continue
        rules, skills = materialize(other)
        other_rule_names.update(os.path.basename(path) for path in rules)
        other_skill_names.update(os.path.basename(os.path.dirname(path)) for path in skills)
    org = os.path.join(".cursor", "rules", "org")
    for name in other_rule_names:
        path = os.path.join(org, name)
        if os.path.isfile(path):
            os.remove(path)
    skills_root = os.path.join(".cursor", "skills")
    for name in other_skill_names:
        path = os.path.join(skills_root, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
    if not selected_rules:
        fail(f"pack {pack_id} has no rules", 1)
    for path in selected_rules:
        shutil.copyfile(path, os.path.join(org, os.path.basename(path)))
    for path in selected_skills:
        name = os.path.basename(os.path.dirname(path))
        dest = os.path.join(skills_root, name)
        os.makedirs(dest, exist_ok=True)
        shutil.copyfile(path, os.path.join(dest, "SKILL.md"))


text = read_profile()
existing = current_pack(text)
if detect:
    if existing and not force:
        print(f"pack: {existing}")
        raise SystemExit(0)
    requested = detect_pack()
if existing and existing != requested and not force:
    fail(f"Pack is already {existing}; refusing to replace it with {requested}", 2)

info = fields_of(requested)
text = set_row(text, "Stack", "Pack", requested, True)
mapping = [
    ("Stack", "Backend", "Backend"),
    ("Stack", "HTTP", "HTTP"),
    ("Stack", "Security", "Security"),
    ("Stack", "Database", "Database"),
    ("Stack", "Tests", "Tests"),
    ("Stack", "Local run", "Local run"),
    ("Commands", "Backend verify", "Backend verify"),
    ("Commands", "Backend verify (fast, no OWASP)", "Backend verify (fast)"),
]
for heading, row, key in mapping:
    if key not in info:
        fail(f"{requested} PACK.md has no {key}", 1)
    text = set_row(text, heading, row, info[key], force)
os.makedirs(os.path.dirname(profile_path), exist_ok=True)
with open(profile_path, "w", encoding="utf-8") as handle:
    handle.write(text)
install_cursor(requested)
print(f"pack: {requested}")
PY
