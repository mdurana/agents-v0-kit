"""Bundle loading and validation."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import yaml

from ._assets import bundles_dir, repo_root, skills_dir

VALID_PERSONAS = [
    "product-owner",
    "solution-architect",
    "lead-builder",
    "builder",
    "pod-builder",
    "observer",
]


def load_catalog() -> dict[str, Any]:
    path = bundles_dir() / "catalog.json"
    return json.loads(path.read_text(encoding="utf-8"))


def bundle_path(persona_id: str) -> Path:
    if persona_id not in VALID_PERSONAS:
        raise ValueError(
            f"Unknown persona '{persona_id}'. Choose from: {', '.join(VALID_PERSONAS)}"
        )
    return bundles_dir() / persona_id / "bundle.yml"


def load_bundle(persona_id: str) -> dict[str, Any]:
    path = bundle_path(persona_id)
    if not path.is_file():
        raise FileNotFoundError(f"Bundle not found: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    data["_id"] = persona_id
    return data


def list_bundles() -> list[str]:
    return load_catalog().get("bundles", VALID_PERSONAS)


def skill_frontmatter_name(skill_rel: str) -> str:
    """Return the flat skill name from SKILL.md frontmatter."""
    skill_path = skills_dir() / skill_rel / "SKILL.md"
    if not skill_path.is_file():
        raise FileNotFoundError(f"Skill not found: {skill_path}")
    content = skill_path.read_text(encoding="utf-8")
    match = re.match(r"^---\s*\n(?:.*\n)*?name:\s*([^\n]+)\n", content, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing name in frontmatter: {skill_path}")
    return match.group(1).strip()
