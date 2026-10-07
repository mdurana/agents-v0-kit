"""Resolve bundled assets from the nwob-agent-skills package or source checkout."""

from __future__ import annotations

import os
import sys
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def repo_root() -> Path:
    """Return the nwob-agent-skills repository root."""
    env = os.environ.get("NWOB_SKILLS_ROOT")
    if env:
        path = Path(env).resolve()
        if (path / "bundles" / "catalog.json").is_file():
            return path

    # Installed package: walk up from this file
    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        if (parent / "bundles" / "catalog.json").is_file():
            return parent
        if parent.name == "site-packages":
            break

    # Development: src/nwob_cli -> repo root
    candidate = here.parents[2]
    if (candidate / "bundles" / "catalog.json").is_file():
        return candidate

    raise FileNotFoundError(
        "Cannot locate nwob-agent-skills root. Set NWOB_SKILLS_ROOT to the repository path."
    )


def bundles_dir() -> Path:
    return repo_root() / "bundles"


def templates_dir() -> Path:
    return repo_root() / "templates"


def skills_dir() -> Path:
    return repo_root() / "skills"


def agents_dir() -> Path:
    return repo_root() / "agents"


def references_dir() -> Path:
    return repo_root() / "references"


def integrations_dir() -> Path:
    return repo_root() / "integrations"


def rules_dir() -> Path:
    return repo_root() / "rules"
