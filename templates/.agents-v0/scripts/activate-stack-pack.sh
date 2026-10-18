#!/bin/sh
# activate-stack-pack.sh — bind one backend pack and install its rules and skills.
#
# Usage (from the target repo):
#   sh .agents-v0/scripts/activate-stack-pack.sh <pack-id> [--force]
#   sh .agents-v0/scripts/activate-stack-pack.sh --detect [--force]
#
# <pack-id> is any id with a complete pack.json. A project pack at
# .agents-v0/packs/<id>/ wins over an example pack in the kit. Writes the Pack
# row and still-placeholder stack and verify cells in
# docs/agents-v0/project-profile.md. Copies that pack's rules into
# .cursor/rules/org and its skills into .cursor/skills, and removes the other
# packs' rules and skills. A Pack cell that already names a different pack is
# left unchanged unless --force is set. --detect reads the tree and refuses
# when more than one pack marker is present. No marker asks for an id; it does
# not assume a pack.
#
# Exit 0 bound, 2 refused to replace, 3 ambiguous or no marker, 1 usage or incomplete pack.

set -eu

FORCE=0
DETECT=0
REQUESTED=""

usage() {
  printf 'usage: %s [--detect] [--force] [<pack-id>]\n' "$(basename "$0")" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --detect) DETECT=1; shift ;;
    -h|--help) usage ;;
    *)
      printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9_-]*$' || usage
      REQUESTED="$1"
      shift
      ;;
  esac
done

if [ "$DETECT" = 0 ] && [ -z "$REQUESTED" ]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CI_DIR="$(cd "$SCRIPT_DIR/../ci" && pwd)"
if [ ! -f "$CI_DIR/packlib.py" ]; then
  printf 'FAIL: packlib.py is not next to this script\n' >&2
  exit 1
fi

export ACTIVATE_CI="$CI_DIR" ACTIVATE_FORCE="$FORCE" ACTIVATE_DETECT="$DETECT" \
  ACTIVATE_REQUESTED="$REQUESTED"

python3 - <<'PY'
import glob
import os
import re
import shutil
import sys

sys.path.insert(0, os.environ["ACTIVATE_CI"])
import packlib

force = os.environ["ACTIVATE_FORCE"] == "1"
detect = os.environ["ACTIVATE_DETECT"] == "1"
requested = os.environ["ACTIVATE_REQUESTED"]
profile_path = os.path.join("docs", "agents-v0", "project-profile.md")


def fail(message, code):
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(code)


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


def require_complete(pack_id):
    data = packlib.load(pack_id)
    if data is None:
        fail(f"no pack manifest for {pack_id}", 1)
    problems = packlib.errors_of(data, "backend")
    directory = data["dir"]
    if not glob.glob(os.path.join(directory, "rules", "*.mdc")):
        problems.append("rules")
    for skill in ("implement-service", "implement-bff"):
        if not os.path.isfile(os.path.join(directory, "skills", skill, "SKILL.md")):
            problems.append(skill)
    ui_value = data.get("ui")
    ui = data.get("uiPack")
    if isinstance(ui_value, str):
        if not ui:
            problems.append("ui")
        else:
            problems.extend("ui." + item for item in packlib.errors_of(ui, "ui"))
    elif isinstance(ui_value, dict):
        problems.extend("ui." + item for item in packlib.errors_of(ui_value, "ui"))
    if problems:
        fail(f"{pack_id} pack is incomplete: " + ", ".join(problems), 1)
    return data


def install_cursor(data):
    pack_id = data["id"]
    directory = data["dir"]
    os.makedirs(os.path.join(".cursor", "rules", "org"), exist_ok=True)
    os.makedirs(os.path.join(".cursor", "skills"), exist_ok=True)
    selected_rules = sorted(glob.glob(os.path.join(directory, "rules", "*.mdc")))
    other_rule_names = set()
    other_skill_names = set()
    for other_id in packlib.all_ids():
        if other_id == pack_id:
            continue
        other = packlib.load(other_id)
        if not other:
            continue
        other_dir = other["dir"]
        other_rule_names.update(
            os.path.basename(path) for path in glob.glob(os.path.join(other_dir, "rules", "*.mdc"))
        )
        other_skill_names.update(
            os.path.basename(os.path.dirname(path))
            for path in glob.glob(os.path.join(other_dir, "skills", "*", "SKILL.md"))
        )
    import tempfile
    tracked_dirs = [
        os.path.join(".cursor", "rules", "org"),
        os.path.join(".cursor", "skills"),
        os.path.join(".cursor", "agents"),
        os.path.join(".cursor", "hooks"),
    ]
    backup_root = tempfile.mkdtemp(prefix="cursor_backup_")
    try:
        for t in tracked_dirs:
            if os.path.exists(t):
                b_dst = os.path.join(backup_root, os.path.relpath(t, "."))
                os.makedirs(os.path.dirname(b_dst), exist_ok=True)
                if os.path.isdir(t):
                    shutil.copytree(t, b_dst, symlinks=True)
                else:
                    shutil.copy2(t, b_dst)

        org = os.path.join(".cursor", "rules", "org")
        os.makedirs(org, exist_ok=True)
        for name in other_rule_names:
            path = os.path.join(org, name)
            if os.path.isfile(path) or os.path.islink(path):
                os.remove(path)
        skills_root = os.path.join(".cursor", "skills")
        os.makedirs(skills_root, exist_ok=True)
        for name in other_skill_names:
            path = os.path.join(skills_root, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.remove(path)
        for path in selected_rules:
            shutil.copyfile(path, os.path.join(org, os.path.basename(path)))
        for path in sorted(glob.glob(os.path.join(directory, "skills", "*", "SKILL.md"))):
            name = os.path.basename(os.path.dirname(path))
            dest = os.path.join(skills_root, name)
            os.makedirs(dest, exist_ok=True)
            shutil.copyfile(path, os.path.join(dest, "SKILL.md"))
        agents = os.path.join(".cursor", "agents")
        os.makedirs(agents, exist_ok=True)
        for path in glob.glob(os.path.join(directory, "agents", "*.md")):
            shutil.copyfile(path, os.path.join(agents, os.path.basename(path)))
        scan = os.path.join(directory, "hooks", "pack-scan.sh")
        if os.path.isfile(scan):
            hooks = os.path.join(".cursor", "hooks")
            os.makedirs(hooks, exist_ok=True)
            dst = os.path.join(hooks, "pack-scan.sh")
            shutil.copyfile(scan, dst)
            try:
                os.chmod(dst, 0o755)
            except OSError as e:
                sys.stderr.write(f"WARN: could not chmod {dst}: {e}\n")
    except Exception as exc:
        for t in tracked_dirs:
            b_src = os.path.join(backup_root, os.path.relpath(t, "."))
            if os.path.exists(b_src):
                if os.path.isdir(b_src):
                    if os.path.exists(t):
                        shutil.rmtree(t)
                    shutil.copytree(b_src, t, symlinks=True)
                else:
                    shutil.copy2(b_src, t)
            else:
                if os.path.isdir(t) and not os.path.islink(t):
                    shutil.rmtree(t)
                elif os.path.lexists(t):
                    os.remove(t)
        raise exc
    finally:
        shutil.rmtree(backup_root, ignore_errors=True)


def with_backend_root(text, command):
    """Run the pack command in the profile Backend root when that cell is filled."""
    root = row_value(text, "Layout", "Backend root")
    if not root or "<!--" in root or root.strip().lower() in ("n/a", "na"):
        return command
    root = root.strip().strip("`").rstrip("/")
    body = re.sub(r"^cd\s+\S+\s+&&\s+", "", command)
    return f"cd {root} && {body}"


def with_frontend_root(text, command):
    """Run the UI pack command in the profile Frontend root when that cell is filled."""
    root = row_value(text, "Layout", "Frontend root")
    if not root or "<!--" in root or root.strip().lower() in ("n/a", "na"):
        return command
    root = root.strip().strip("`").rstrip("/")
    body = re.sub(r"^cd\s+\S+\s+&&\s+", "", command)
    return f"cd {root} && {body}"


def has_frontend_surface(text):
    """Return False when Layout Profile is service or Frontend root is explicitly n/a."""
    prof = row_value(text, "Layout", "Profile").strip().strip("`").lower()
    froot = row_value(text, "Layout", "Frontend root").strip().strip("`").lower()
    if prof == "service" or froot in ("n/a", "na"):
        return False
    return True


text = read_profile()
existing = packlib.profile_pack(profile_path)
if detect:
    if existing and not force:
        print(f"pack: {existing}")
        raise SystemExit(0)
    found = packlib.detect(".")
    if not found:
        fail("no pack marker; name the pack id", 3)
    if len(found) > 1:
        fail("ambiguous backend markers: " + ", ".join(sorted(found)), 3)
    requested = found.pop()
if existing and existing != requested and not force:
    fail(f"Pack is already {existing}; refusing to replace it with {requested}", 2)

info = require_complete(requested)
text = set_row(text, "Stack", "Pack", requested, True)
mapping = [
    ("Stack", "Backend", info.get("backend", "")),
    ("Stack", "HTTP", info.get("http", "")),
    ("Stack", "Security", info.get("security", "")),
    ("Stack", "Database", info.get("database", "")),
    ("Stack", "Tests", info.get("tests", "")),
    ("Stack", "Local run", info.get("localRun", "")),
    ("Commands", "Backend verify", info.get("verify", "")),
    ("Commands", "Backend verify (fast, no OWASP)", info.get("verifyFast", "")),
]
ui = info.get("uiPack") or {}
if has_frontend_surface(text):
    if ui.get("stack"):
        mapping.append(("Stack", "Frontend", ui["stack"]))
    if ui.get("verify"):
        mapping.append(("Commands", "Frontend verify", ui["verify"]))
    if ui.get("verifyFast"):
        mapping.append(("Commands", "Frontend verify (fast)", ui["verifyFast"]))
if info.get("serviceVerify"):
    mapping.append(("Commands", "Service verify", info["serviceVerify"]))
if info.get("serviceVerifyFast"):
    mapping.append(("Commands", "Service verify (fast, no OWASP)", info["serviceVerifyFast"]))
# Descriptive stack rows are optional. A pack that passed errors_of still binds.
optional = {
    ("Stack", "Backend"),
    ("Stack", "HTTP"),
    ("Stack", "Security"),
    ("Stack", "Database"),
    ("Stack", "Tests"),
    ("Stack", "Local run"),
    ("Stack", "Frontend"),
}
for heading, row, value in mapping:
    if not value:
        if (heading, row) in optional:
            continue
        fail(f"{requested} pack.json has no {row}", 1)
    owned_be = heading == "Commands" and row.startswith("Backend verify")
    owned_fe = heading == "Commands" and row.startswith("Frontend verify")
    if owned_be:
        value = with_backend_root(text, value)
    elif owned_fe:
        value = with_frontend_root(text, value)
    text = set_row(text, heading, row, value, force or owned_be or owned_fe)
try:
    install_cursor(info)
except Exception as exc:
    fail(f"could not install cursor configuration: {exc}", 1)

os.makedirs(os.path.dirname(profile_path), exist_ok=True)
tmp_profile = profile_path + ".tmp"
with open(tmp_profile, "w", encoding="utf-8") as handle:
    handle.write(text)
os.replace(tmp_profile, profile_path)
print(f"pack: {requested}")
PY
