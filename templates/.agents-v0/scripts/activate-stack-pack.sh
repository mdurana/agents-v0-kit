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
CI_DIR="$SCRIPT_DIR"
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


def same_file(src, dst):
    if not os.path.isfile(dst) or os.path.islink(dst):
        return False
    try:
        with open(src, "rb") as f1, open(dst, "rb") as f2:
            return f1.read() == f2.read()
    except OSError:
        return False


def install_cursor(data):
    import tempfile
    pack_id = data["id"]
    directory = data["dir"]
    org = os.path.join(".cursor", "rules", "org")
    skills_root = os.path.join(".cursor", "skills")
    agents = os.path.join(".cursor", "agents")
    hooks = os.path.join(".cursor", "hooks")

    selected_rules = sorted(glob.glob(os.path.join(directory, "rules", "*.mdc")))
    selected_rule_names = {os.path.basename(p) for p in selected_rules}
    selected_skills = sorted(glob.glob(os.path.join(directory, "skills", "*", "SKILL.md")))
    selected_skill_names = {os.path.basename(os.path.dirname(p)) for p in selected_skills}
    selected_agents = sorted(glob.glob(os.path.join(directory, "agents", "*.md")))

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
    other_rule_names -= selected_rule_names
    other_skill_names -= selected_skill_names

    # Build list of (src, dst, is_exec) writes needed
    planned_writes = []
    for path in selected_rules:
        dst = os.path.join(org, os.path.basename(path))
        if not same_file(path, dst):
            planned_writes.append((path, dst, False))
    for path in selected_skills:
        name = os.path.basename(os.path.dirname(path))
        dst = os.path.join(skills_root, name, "SKILL.md")
        if not same_file(path, dst):
            planned_writes.append((path, dst, False))
    for path in selected_agents:
        dst = os.path.join(agents, os.path.basename(path))
        if not same_file(path, dst):
            planned_writes.append((path, dst, False))
    scan = os.path.join(directory, "hooks", "pack-scan.sh")
    if os.path.isfile(scan):
        dst = os.path.join(hooks, "pack-scan.sh")
        if not same_file(scan, dst):
            planned_writes.append((scan, dst, True))
        elif not os.access(dst, os.X_OK):
            try:
                os.chmod(dst, 0o755)
            except OSError as e:
                sys.stderr.write(f"WARN: could not chmod {dst}: {e}\n")

    # Phase 1: Ensure directories and stage all writes to <dst>.tmp before deleting anything
    created_dirs = []
    staged_tmps = []

    def ensure_dir(d):
        parts = []
        cur = d
        while cur and cur not in (".", "/") and not os.path.exists(cur):
            parts.append(cur)
            cur = os.path.dirname(cur)
        for p in reversed(parts):
            os.mkdir(p)
            created_dirs.append(p)
        if os.path.exists(d) and not os.path.isdir(d):
            raise OSError(f"{d} is not a directory")

    try:
        ensure_dir(org)
        ensure_dir(skills_root)
        for src, dst, is_exec in planned_writes:
            ensure_dir(os.path.dirname(dst))
            tmp_dst = dst + ".tmp"
            shutil.copyfile(src, tmp_dst)
            staged_tmps.append((tmp_dst, dst))
            if is_exec:
                try:
                    os.chmod(tmp_dst, 0o755)
                except OSError as e:
                    sys.stderr.write(f"WARN: could not chmod {dst}: {e}\n")
    except Exception:
        for tmp_dst, _ in staged_tmps:
            try:
                if os.path.lexists(tmp_dst):
                    os.remove(tmp_dst)
            except OSError:
                pass
        for d in reversed(created_dirs):
            try:
                os.rmdir(d)
            except OSError:
                pass
        raise

    # Phase 2: Back up only the specific pack-owned files/dirs being overwritten or removed, then commit
    obsolete_rules = [
        os.path.join(org, name) for name in sorted(other_rule_names)
        if os.path.isfile(os.path.join(org, name)) or os.path.islink(os.path.join(org, name))
    ]
    obsolete_skills = [
        os.path.join(skills_root, name) for name in sorted(other_skill_names)
        if os.path.lexists(os.path.join(skills_root, name))
    ]
    overwritten_files = [dst for _, dst in staged_tmps if os.path.lexists(dst)]
    created_files = [dst for _, dst in staged_tmps if not os.path.lexists(dst)]

    backup_root = tempfile.mkdtemp(prefix="cursor_backup_")
    backed_up = []  # list of (target_path, backup_path, is_dir)
    restore_ok = True
    try:
        for p in overwritten_files + obsolete_rules:
            b_dst = os.path.join(backup_root, os.path.relpath(p, "."))
            os.makedirs(os.path.dirname(b_dst), exist_ok=True)
            shutil.copy2(p, b_dst, follow_symlinks=False)
            backed_up.append((p, b_dst, False))
        for p in obsolete_skills:
            b_dst = os.path.join(backup_root, os.path.relpath(p, "."))
            os.makedirs(os.path.dirname(b_dst), exist_ok=True)
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.copytree(p, b_dst, symlinks=True)
                backed_up.append((p, b_dst, True))
            else:
                shutil.copy2(p, b_dst, follow_symlinks=False)
                backed_up.append((p, b_dst, False))

        for tmp_dst, dst in staged_tmps:
            os.replace(tmp_dst, dst)
        for p in obsolete_rules:
            os.remove(p)
        for p in obsolete_skills:
            if os.path.isdir(p) and not os.path.islink(p):
                shutil.rmtree(p)
            elif os.path.lexists(p):
                os.remove(p)
    except Exception as exc:
        for tmp_dst, _ in staged_tmps:
            try:
                if os.path.lexists(tmp_dst):
                    os.remove(tmp_dst)
            except OSError:
                pass
        for dst in created_files:
            try:
                if os.path.lexists(dst):
                    os.remove(dst)
            except OSError:
                restore_ok = False
        for target_p, b_src, is_dir in backed_up:
            try:
                if is_dir:
                    tmp_restore = target_p + ".restore_tmp"
                    if os.path.lexists(tmp_restore):
                        shutil.rmtree(tmp_restore)
                    shutil.copytree(b_src, tmp_restore, symlinks=True)
                    if os.path.isdir(target_p) and not os.path.islink(target_p):
                        shutil.rmtree(target_p)
                    elif os.path.lexists(target_p):
                        os.remove(target_p)
                    os.replace(tmp_restore, target_p)
                else:
                    tmp_restore = target_p + ".restore_tmp"
                    shutil.copy2(b_src, tmp_restore, follow_symlinks=False)
                    os.replace(tmp_restore, target_p)
            except OSError:
                restore_ok = False
        for d in reversed(created_dirs):
            try:
                os.rmdir(d)
            except OSError:
                pass
        if not restore_ok:
            raise OSError(f"{exc} (backup preserved at {backup_root})") from exc
        raise
    finally:
        if restore_ok:
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
