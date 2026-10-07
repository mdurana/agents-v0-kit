"""Manifest and init-options management."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def nwob_dir(project: Path) -> Path:
    return project / ".nwob"


def manifest_path(project: Path) -> Path:
    return nwob_dir(project) / "manifest.json"


def init_options_path(project: Path) -> Path:
    return nwob_dir(project) / "init-options.json"


def active_persona_path(project: Path) -> Path:
    return nwob_dir(project) / "active-persona.json"


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest(project: Path) -> dict[str, Any]:
    path = manifest_path(project)
    if not path.is_file():
        return {
            "schema_version": "2.0",
            "nwob_version": "1.0.0",
            "core_installed": False,
            "installed_personas": [],
            "core_files": [],
            "persona_assets": {},
            "files": {},
        }
    return json.loads(path.read_text(encoding="utf-8"))


def save_manifest(project: Path, manifest: dict[str, Any]) -> None:
    path = manifest_path(project)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def record_file(manifest: dict[str, Any], rel_path: str, abs_path: Path) -> None:
    manifest["files"][rel_path] = {
        "hash": file_hash(abs_path),
        "managed": True,
    }


def ensure_persona_assets(manifest: dict[str, Any], persona_id: str) -> dict[str, list[str]]:
    if "persona_assets" not in manifest:
        manifest["persona_assets"] = {}
    if persona_id not in manifest["persona_assets"]:
        manifest["persona_assets"][persona_id] = {
            "skills": [],
            "rules": [],
            "agents": [],
            "commands": [],
        }
    return manifest["persona_assets"][persona_id]


def record_core_file(manifest: dict[str, Any], rel_path: str) -> None:
    if "core_files" not in manifest:
        manifest["core_files"] = []
    if rel_path not in manifest["core_files"]:
        manifest["core_files"].append(rel_path)


def record_persona_asset(
    manifest: dict[str, Any], persona_id: str, category: str, rel_path: str
) -> None:
    assets = ensure_persona_assets(manifest, persona_id)
    if rel_path not in assets[category]:
        assets[category].append(rel_path)


def load_init_options(project: Path) -> dict[str, Any]:
    path = init_options_path(project)
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save_init_options(project: Path, options: dict[str, Any]) -> None:
    path = init_options_path(project)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(options, indent=2) + "\n", encoding="utf-8")


def load_active_persona(project: Path) -> dict[str, Any]:
    path = active_persona_path(project)
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save_active_persona(project: Path, persona_id: str) -> None:
    data = {
        "persona": persona_id,
        "switched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path = active_persona_path(project)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
