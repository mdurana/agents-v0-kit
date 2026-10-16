"""Load a backend or UI pack manifest.

A pack id is any directory name with a complete pack.json. Example manifests
live under core/<id>/ and core/ui/<id>/ in the kit. A project pack at
.agents-v0/packs/<id>/ or .agents-v0/ui/<id>/ is the one that wins.
"""

import json
import os
import re

ID_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
REQUIRED = (
    "id",
    "verify",
    "verifyFast",
    "coverage",
    "testsReport",
    "authMarker",
    "publicMarker",
    "migrationTool",
    "ciImage",
    "endpoints",
)


def _here():
    return os.path.dirname(os.path.abspath(__file__))


def library_roots():
    """Directories whose children are pack directories. Project roots come first."""
    roots = []
    cwd = os.getcwd()
    for rel in (
        os.path.join(cwd, ".agents-v0", "packs"),
        os.path.join(cwd, "kit", "core"),
        os.path.join(cwd, "core"),
    ):
        if os.path.isdir(rel):
            roots.append(os.path.abspath(rel))
    here = _here()
    for rel in (
        os.path.normpath(os.path.join(here, "..", "packs")),
        os.path.normpath(os.path.join(here, "..", "..", "..", "core")),
    ):
        if os.path.isdir(rel):
            roots.append(os.path.abspath(rel))
    seen = []
    for root in roots:
        if root not in seen:
            seen.append(root)
    return seen


def ui_roots():
    roots = []
    cwd = os.getcwd()
    for rel in (
        os.path.join(cwd, ".agents-v0", "ui"),
        os.path.join(cwd, "kit", "core", "ui"),
        os.path.join(cwd, "core", "ui"),
    ):
        if os.path.isdir(rel):
            roots.append(os.path.abspath(rel))
    here = _here()
    for rel in (
        os.path.normpath(os.path.join(here, "..", "ui")),
        os.path.normpath(os.path.join(here, "..", "..", "..", "core", "ui")),
    ):
        if os.path.isdir(rel):
            roots.append(os.path.abspath(rel))
    seen = []
    for root in roots:
        if root not in seen:
            seen.append(root)
    return seen


def _read_json(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, dict):
        raise ValueError("manifest is not an object")
    return data


def find_dir(pack_id, roots):
    if not pack_id or not ID_RE.match(pack_id):
        return ""
    for root in roots:
        path = os.path.join(root, pack_id, "pack.json")
        if os.path.isfile(path):
            return os.path.dirname(path)
    return ""


def errors_of(data, kind):
    """Return a list of reasons the manifest is not complete."""
    missing = []
    if kind == "ui":
        for key in ("id", "stack", "verify", "verifyFast", "layout"):
            if not str(data.get(key) or "").strip():
                missing.append(key)
        coverage = data.get("coverage") if isinstance(data.get("coverage"), dict) else {}
        if not coverage.get("path") or not coverage.get("format"):
            missing.append("coverage.path")
            missing.append("coverage.format")
        return missing
    for key in REQUIRED:
        if key not in data or data.get(key) in ("", None, [], {}):
            missing.append(key)
    coverage = data.get("coverage") if isinstance(data.get("coverage"), dict) else {}
    report = data.get("testsReport") if isinstance(data.get("testsReport"), dict) else {}
    cve = data.get("cve") if isinstance(data.get("cve"), dict) else {}
    if not coverage.get("path") or not coverage.get("format"):
        missing.append("coverage.path")
        missing.append("coverage.format")
    if not report.get("path") or not report.get("format"):
        missing.append("testsReport.path")
        missing.append("testsReport.format")
    if not cve.get("path"):
        missing.append("cve.path")
    endpoints = data.get("endpoints") if isinstance(data.get("endpoints"), list) else []
    if not endpoints:
        missing.append("endpoints")
    for index, spec in enumerate(endpoints):
        if not isinstance(spec, dict) or not spec.get("suffix"):
            missing.append(f"endpoints[{index}].suffix")
            continue
        if spec.get("parser") == "spring":
            continue
        if not spec.get("mapping") or not spec.get("security"):
            missing.append(f"endpoints[{index}].mapping")
    return missing


def load(pack_id):
    """Return the backend manifest plus its directory, or None."""
    directory = find_dir(pack_id, library_roots())
    if not directory:
        return None
    try:
        data = _read_json(os.path.join(directory, "pack.json"))
    except (OSError, json.JSONDecodeError, ValueError):
        return None
    if data.get("id") != pack_id:
        return None
    data["dir"] = directory
    ui = data.get("ui")
    if isinstance(ui, str) and ui:
        ui_dir = find_dir(ui, ui_roots())
        if ui_dir:
            try:
                ui_data = _read_json(os.path.join(ui_dir, "pack.json"))
            except (OSError, json.JSONDecodeError, ValueError):
                ui_data = None
            if ui_data and ui_data.get("id") == ui:
                ui_data["dir"] = ui_dir
                data["uiPack"] = ui_data
    elif isinstance(ui, dict):
        data["uiPack"] = ui
    return data


def all_ids():
    found = []
    for root in library_roots():
        for name in sorted(os.listdir(root)):
            if name in found:
                continue
            if os.path.isfile(os.path.join(root, name, "pack.json")):
                found.append(name)
    return found


def all_manifests():
    out = []
    for pack_id in all_ids():
        data = load(pack_id)
        if data:
            out.append(data)
    return out


def profile_pack(profile="docs/agents-v0/project-profile.md"):
    """Pack cell when it is an id. A placeholder or a blank cell is empty."""
    if not os.path.isfile(profile):
        return ""
    text = open(profile, encoding="utf-8", errors="replace").read()
    if "## Stack" not in text:
        return ""
    body = text.split("## Stack", 1)[1].split("\n## ", 1)[0]
    for line in body.splitlines():
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if cells and cells[0] == "Pack" and len(cells) > 1 and ID_RE.match(cells[1]):
            return cells[1]
    return ""


def _basename_match(name, pattern):
    if pattern.startswith("*."):
        return name.endswith(pattern[1:])
    return name == pattern


def marker_roots(root=".", max_depth=4):
    """Relative directories that contain a backend pack detect marker.

    A React package.json is not a marker. node_modules, build output, and
    .agents-v0 are skipped. max_depth counts separators under root.
    """
    skip = {
        ".git", "node_modules", "target", "dist", "build", ".next", "bin", "obj",
        ".venv", "venv", "__pycache__", "kit",
    }
    manifests = []
    for pack_id in all_ids():
        data = load(pack_id)
        if data and data.get("detect"):
            manifests.append(data)
    if not manifests or not os.path.isdir(root):
        return []
    found = []
    root_abs = os.path.abspath(root)
    for dirpath, dirnames, filenames in os.walk(root_abs):
        dirnames[:] = [name for name in dirnames if name not in skip and not name.startswith(".agents")]
        rel = os.path.relpath(dirpath, root_abs)
        depth = 0 if rel == "." else rel.count(os.sep) + 1
        if depth > max_depth:
            dirnames[:] = []
            continue
        hit = False
        for name in filenames:
            for data in manifests:
                patterns = data.get("detect") or []
                if not any(_basename_match(name, pattern) for pattern in patterns):
                    continue
                deps = data.get("detectDeps") or []
                if deps:
                    if name != "package.json":
                        continue
                    try:
                        payload = json.load(open(os.path.join(dirpath, name), encoding="utf-8"))
                    except (OSError, json.JSONDecodeError):
                        continue
                    have = {}
                    for key in ("dependencies", "devDependencies"):
                        have.update(payload.get(key) or {})
                    if not any(dep in have for dep in deps):
                        continue
                hit = True
                break
            if hit:
                break
        if hit:
            found.append("." if rel == "." else rel.replace(os.sep, "/"))
    return found


def detect(root="."):
    """Return the set of pack ids whose detect markers are present under root."""
    skip = {
        ".git", "node_modules", "target", "dist", "build", ".next", "bin", "obj",
        ".venv", "venv", "__pycache__", "kit",
    }
    found = set()
    manifests = []
    for pack_id in all_ids():
        data = load(pack_id)
        if data and data.get("detect"):
            manifests.append(data)
    if not manifests:
        return found
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in skip and not name.startswith(".agents")]
        for name in filenames:
            for data in manifests:
                pack_id = data["id"]
                if pack_id in found:
                    continue
                patterns = data.get("detect") or []
                if not any(_basename_match(name, pattern) for pattern in patterns):
                    continue
                deps = data.get("detectDeps") or []
                if deps:
                    if name != "package.json":
                        continue
                    try:
                        payload = json.load(open(os.path.join(dirpath, name), encoding="utf-8"))
                    except (OSError, json.JSONDecodeError):
                        continue
                    have = {}
                    for key in ("dependencies", "devDependencies"):
                        have.update(payload.get(key) or {})
                    if not any(dep in have for dep in deps):
                        continue
                found.add(pack_id)
    return found
