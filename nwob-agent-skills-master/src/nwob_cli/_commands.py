"""Generate Cursor slash command stubs."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from ._assets import integrations_dir
from ._bundles import skill_frontmatter_name


def _scaffold_step(scaffold: str | None, template: str | None) -> str:
    if not scaffold:
        return ""
    template_ref = template or ""
    resolve_note = (
        " Resolve the target path via `.nwob/artifact-paths.json` when present "
        "(see `nwob-references/rules/sdd-artifact-layout.md`); otherwise use the default scaffold path."
    )
    if template_ref:
        return (
            f"2. Resolve the artifact path for this command (mapping or `{scaffold}`).{resolve_note} "
            f"If missing, create it from `.nwob/templates/{Path(template_ref).name}` at the resolved path."
        )
    return (
        f"2. Resolve the artifact path for this command (mapping or `{scaffold}`).{resolve_note} "
        "If missing, scaffold per the skill Process section at the resolved path."
    )


def _implement_guard(command_name: str) -> str:
    po_commands = {
        "problem",
        "ideate",
        "roadmap",
        "features",
        "backlog",
        "value",
        "intake",
        "collect",
        "present",
        "enrich",
        "deck",
    }
    observer_commands = {"summarize", "meeting", "handoff"}
    sa_commands = {
        "c4",
        "pattern",
        "platform",
        "services",
        "contracts",
        "ops",
        "adr",
        "arc",
        "architecture",
    }
    if command_name in po_commands | observer_commands | sa_commands:
        return "5. Do not implement application code — artifact output only."
    if command_name == "audit":
        return "5. Do not implement application code — audit report only."
    return ""


def render_command_stub(
    persona_id: str,
    command: dict[str, Any],
    template_text: str,
) -> str:
    name = command["name"]
    skill_rel = command["skill"]
    skill_name = skill_frontmatter_name(skill_rel)
    scaffold = command.get("scaffold")
    template = command.get("template")
    return (
        template_text.replace("{{PERSONA}}", persona_id)
        .replace("{{SKILL_NAME}}", skill_name)
        .replace("{{SCAFFOLD_STEP}}", _scaffold_step(scaffold, template))
        .replace("{{IMPLEMENT_GUARD}}", _implement_guard(name))
    )


def install_cursor_commands(
    project: Path,
    persona_id: str,
    bundle: dict[str, Any],
    force: bool = False,
) -> list[str]:
    """Write .cursor/commands stubs for a persona bundle. Returns relative paths written."""
    commands_dir = project / ".cursor" / "commands"
    commands_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []

    template_path = integrations_dir() / "cursor" / "commands" / "_command-template.md"
    template_text = template_path.read_text(encoding="utf-8")

    for cmd in bundle.get("provides", {}).get("commands", []):
        name = cmd["name"]
        dest = commands_dir / f"{name}.md"
        if dest.exists() and not force:
            continue
        content = render_command_stub(persona_id, cmd, template_text)
        dest.write_text(content, encoding="utf-8")
        written.append(f".cursor/commands/{name}.md")

    return written


def remove_persona_commands(project: Path, persona_id: str, bundle: dict[str, Any]) -> None:
    """Remove slash command stubs for a persona (keeps core persona/switch)."""
    commands_dir = project / ".cursor" / "commands"
    for cmd in bundle.get("provides", {}).get("commands", []):
        dest = commands_dir / f"{cmd['name']}.md"
        if dest.is_file():
            dest.unlink()


def install_core_commands(project: Path, force: bool = False) -> list[str]:
    """Install persona.md and switch.md core commands."""
    src_dir = integrations_dir() / "cursor" / "commands"
    dest_dir = project / ".cursor" / "commands"
    dest_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    for name in ("persona.md", "switch.md"):
        src = src_dir / name
        dest = dest_dir / name
        if dest.exists() and not force:
            continue
        dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        written.append(f".cursor/commands/{name}")
    return written
