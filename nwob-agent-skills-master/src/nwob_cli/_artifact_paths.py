"""Resolve SDD artifact paths from defaults or local mapping."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ._assets import references_dir
from ._manifest import load_init_options, nwob_dir

MAPPING_FILENAME = "artifact-paths.json"
MAPPING_EXAMPLE_FILENAME = "artifact-paths.example.json"
SCHEMA_VERSION = "1.0"

# SDD-only keys aligned to references/rules/sdd-artifact-layout.md
# Required: spec. Optional: stories_dir.
ARTIFACT_KEYS: tuple[str, ...] = (
    "spec",
    "stories_dir",
)

REQUIRED_KEYS: tuple[str, ...] = ("spec",)

# Retired keys — warn when present in older mappings; ignore at resolve.
OBSOLETE_KEYS: tuple[str, ...] = (
    "plan",
    "tasks",
)

DEFAULT_PATHS: dict[str, str] = {
    "spec": "nwob-docs/sdd/epic-spec.md",
    "stories_dir": "nwob-docs/sdd/stories/",
}


def mapping_path(project: Path) -> Path:
    return nwob_dir(project) / MAPPING_FILENAME


def bundled_example_path() -> Path:
    return references_dir() / "samples" / MAPPING_EXAMPLE_FILENAME


def scaffold_nwob_docs_enabled(project: Path) -> bool:
    """Return True when init should expect the default nwob-docs tree (default: True)."""
    options = load_init_options(project)
    return options.get("scaffold_nwob_docs", True)


def is_nwob_docs_path(rel_path: str) -> bool:
    normalized = rel_path.replace("\\", "/").lstrip("/")
    return normalized == "nwob-docs" or normalized.startswith("nwob-docs/")


def default_path(key: str) -> str:
    if key not in DEFAULT_PATHS:
        raise KeyError(f"Unknown artifact key: {key}")
    return DEFAULT_PATHS[key]


def load_mapping(project: Path) -> dict[str, str]:
    """Load path overrides from .nwob/artifact-paths.json; empty dict when absent."""
    path = mapping_path(project)
    if not path.is_file():
        return {}
    data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    raw_paths = data.get("paths", {})
    if not isinstance(raw_paths, dict):
        return {}
    mapping: dict[str, str] = {}
    for key, value in raw_paths.items():
        if key in OBSOLETE_KEYS:
            continue
        rel_str = str(value).replace("\\", "/").lstrip("/")
        if rel_str:
            mapping[str(key)] = rel_str
    return mapping


def resolve(project: Path, key: str) -> Path:
    """Resolve artifact key to absolute project path (mapping override or default)."""
    project = project.resolve()
    mapping = load_mapping(project)
    rel = mapping.get(key, default_path(key))
    return project / rel


def resolve_all(project: Path) -> dict[str, Path]:
    """Resolve every known SDD artifact key."""
    return {key: resolve(project, key) for key in ARTIFACT_KEYS}


def validate_mapping(
    project: Path,
    *,
    required_keys: tuple[str, ...] = REQUIRED_KEYS,
) -> tuple[list[str], list[str]]:
    """Validate mapping file. Returns (errors, warnings).

    Requires non-empty ``spec``. Optional key ``stories_dir`` may be absent
    or empty (resolve falls back to defaults). Obsolete keys ``plan`` /
    ``tasks`` warn only. Other unknown keys warn only.
    """
    project = project.resolve()
    errors: list[str] = []
    warnings: list[str] = []

    path = mapping_path(project)
    if not path.is_file():
        if not scaffold_nwob_docs_enabled(project):
            warnings.append(
                f"Missing `{path.relative_to(project)}` — run `nwob config paths --init` "
                "and map existing doc paths"
            )
        return errors, warnings

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        errors.append(f"Invalid JSON in {MAPPING_FILENAME}: {exc}")
        return errors, warnings

    if data.get("schema_version") != SCHEMA_VERSION:
        warnings.append(
            f"{MAPPING_FILENAME} schema_version is not {SCHEMA_VERSION!r}; "
            "continuing with best-effort parsing"
        )

    raw_paths = data.get("paths", {})
    if not isinstance(raw_paths, dict):
        errors.append(f"{MAPPING_FILENAME} must contain a 'paths' object")
        return errors, warnings

    for key, rel in raw_paths.items():
        if key in OBSOLETE_KEYS:
            warnings.append(
                f"Obsolete artifact key {key!r} in mapping — remove it; "
                f"backlog/HL US-TS live in epic-spec.md; tasks live in "
                f"stories/{{STORY_ID}}/story-tasks.md"
            )
            continue
        if key not in DEFAULT_PATHS:
            warnings.append(
                f"Unknown artifact key in mapping (ignored at resolve; "
                f"remove obsolete keys): {key!r}"
            )

    for key in required_keys:
        raw_value = raw_paths.get(key)
        if raw_value is None:
            errors.append(f"Missing required artifact key {key!r} in paths")
            continue
        rel_str = str(raw_value).replace("\\", "/").lstrip("/")
        if not rel_str:
            errors.append(f"Empty path for required artifact key {key!r}")

    return errors, warnings


def init_mapping_from_example(project: Path, *, force: bool = False) -> Path | None:
    """Create .nwob/artifact-paths.json with SDD default paths if missing.

    Writes only ``spec`` and ``stories_dir``. The bundled example uses empty
    strings as a fill-in template. Init writes populated ``DEFAULT_PATHS`` so
    resolve works immediately; brownfield users edit the written file to point
    at existing docs. ``stories_dir`` is optional for validation and may be
    deleted from the live mapping.
    """
    project = project.resolve()
    dest = mapping_path(project)
    if dest.exists() and not force:
        return None

    src = bundled_example_path()
    if not src.is_file():
        raise FileNotFoundError(f"Bundled example not found: {src}")

    data = {
        "schema_version": SCHEMA_VERSION,
        "paths": {key: DEFAULT_PATHS[key] for key in ARTIFACT_KEYS},
    }
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return dest


def save_scaffold_option(project: Path, scaffold_nwob_docs: bool) -> None:
    """Persist scaffold_nwob_docs in init-options.json."""
    from ._manifest import load_init_options, save_init_options

    options = load_init_options(project)
    options["scaffold_nwob_docs"] = scaffold_nwob_docs
    save_init_options(project, options)
