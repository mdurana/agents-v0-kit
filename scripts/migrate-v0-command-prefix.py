#!/usr/bin/env python3
"""One-off: rename core/commands to v0-* and prefix slash invocations with /v0-."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = (
    "onboard",
    "deliver",
    "intake",
    "build",
    "triage",
    "design",
    "plan",
    "verify",
    "maintain",
    "status",
    "release",
)
ALT = "|".join(re.escape(c) for c in COMMANDS)
# Slash command, not already v0-, not a path segment like agents-v0/design/
SLASH_CMD = re.compile(rf"(?<![/\w-])/(?!v0-)({ALT})(?![a-z0-9-.])")

SCAN_DIRS = ("core", "docs", "templates", "scripts", ".")
SCAN_ROOT_FILES = ("AGENTS.md", "README.md")
SKIP_SUFFIX = {".png", ".jpg", ".jsonl"}


def rename_command_files() -> None:
    cmd_dir = ROOT / "core" / "commands"
    for cmd in COMMANDS:
        src = cmd_dir / f"{cmd}.md"
        dst = cmd_dir / f"v0-{cmd}.md"
        if src.is_file():
            src.rename(dst)
            print(f"rename: {src.relative_to(ROOT)} -> {dst.name}")


def patch_text(text: str) -> str:
    return SLASH_CMD.sub(r"/v0-\1", text)


def patch_file(path: Path) -> bool:
    if path.suffix in SKIP_SUFFIX or path.name == Path(__file__).name:
        return False
    if "migrate-v0-command-prefix" in path.name:
        return False
    try:
        original = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    updated = patch_text(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        return True
    return False


def main() -> int:
    rename_command_files()
    changed = 0
    for rel in SCAN_DIRS:
        base = ROOT / rel if rel != "." else ROOT
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if path.is_file() and patch_file(path):
                changed += 1
                print(f"patched: {path.relative_to(ROOT)}")
    for name in SCAN_ROOT_FILES:
        path = ROOT / name
        if path.is_file() and patch_file(path):
            changed += 1
            print(f"patched: {name}")
    print(f"done: {changed} files patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
