"""Install persona bundles into target projects."""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from ._agents_overlay import update_agents_md
from ._assets import (
    agents_dir,
    integrations_dir,
    references_dir,
    repo_root,
    skills_dir,
    templates_dir,
)
from ._bundles import load_bundle, load_catalog, skill_frontmatter_name
from ._commands import (
    install_core_commands,
    install_cursor_commands,
    remove_persona_commands,
)
from ._gitignore import ensure_gitignore
from ._manifest import (
    load_active_persona,
    load_init_options,
    load_manifest,
    record_core_file,
    record_file,
    record_persona_asset,
    save_active_persona,
    save_init_options,
    save_manifest,
)
from ._artifact_paths import (
    init_mapping_from_example,
    is_nwob_docs_path,
    save_scaffold_option,
    scaffold_nwob_docs_enabled,
)
from ._paths import (
    NWOB_REFERENCES_DIR,
    rewrite_agent_content,
    rewrite_project_paths,
    rewrite_skill_content,
)

from . import __version__


def _copy_file(
    src: Path,
    dest: Path,
    *,
    transform: str | None = None,
    force: bool = False,
) -> bool:
    if dest.exists() and not force:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    content = src.read_text(encoding="utf-8")
    if transform == "skill":
        content = rewrite_skill_content(content)
    elif transform == "agent":
        content = rewrite_agent_content(content)
    dest.write_text(content, encoding="utf-8")
    return True


def _install_setup_script(project: Path, manifest: dict[str, Any], force: bool) -> None:
    src = repo_root() / "scripts" / "setup-nwob.sh"
    if not src.is_file():
        return
    dest = project / "setup-nwob.sh"
    if dest.exists() and not force:
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    dest.chmod(dest.stat().st_mode | 0o111)
    record_file(manifest, "setup-nwob.sh", dest)
    record_core_file(manifest, "setup-nwob.sh")


def _install_core_references(project: Path, manifest: dict[str, Any], force: bool) -> None:
    dest_base = project / NWOB_REFERENCES_DIR
    src_base = references_dir()

    files_to_copy: list[tuple[Path, Path]] = []
    rules_src = src_base / "rules"
    if rules_src.is_dir():
        for src in sorted(rules_src.glob("*.md")):
            files_to_copy.append((src, dest_base / "rules" / src.name))

    samples_src = src_base / "samples" / "presentation.config.md"
    if samples_src.is_file():
        files_to_copy.append((samples_src, dest_base / "samples" / "presentation.config.md"))

    for src, dest in files_to_copy:
        if _copy_file(src, dest, force=force):
            rel = str(dest.relative_to(project))
            record_file(manifest, rel, dest)
            record_core_file(manifest, rel)


def _install_nwob_docs_scaffold(
    project: Path,
    manifest: dict[str, Any],
    force: bool,
    *,
    scaffold_nwob_docs: bool = True,
) -> None:
    if not scaffold_nwob_docs:
        return
    catalog = load_catalog()
    for scaffold_rel in catalog.get("core", {}).get("scaffolds", []):
        dest = project / scaffold_rel
        if dest.exists() and not force:
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        if scaffold_rel.endswith(".gitkeep"):
            dest.write_text("", encoding="utf-8")
        record_file(manifest, scaffold_rel, dest)
        record_core_file(manifest, scaffold_rel)


def _install_core_scaffold_files(
    project: Path,
    manifest: dict[str, Any] | None,
    force: bool,
    *,
    scaffold_nwob_docs: bool = True,
) -> list[str]:
    """Copy template-backed core scaffold files. Returns relative paths created.

    Create-only: never overwrite existing content. ``force`` is ignored for
    content files (call-site compatibility with install_core).
    """
    del force  # create-only; asset force must not rewrite docs
    catalog = load_catalog()
    created: list[str] = []
    for entry in catalog.get("core", {}).get("scaffold_files", []):
        path_str = entry.get("path", "")
        template_rel = entry.get("template")
        if not path_str or not template_rel:
            continue
        if not scaffold_nwob_docs and is_nwob_docs_path(path_str):
            continue
        dest = project / path_str
        # Create-only: never overwrite authored docs (force does not apply).
        if dest.exists():
            continue
        src = templates_dir() / template_rel
        if not src.is_file():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
        created.append(path_str)
        if manifest is not None:
            record_file(manifest, path_str, dest)
            record_core_file(manifest, path_str)
    return created


def ensure_project_gitignore(
    project: Path,
    manifest: dict[str, Any] | None = None,
) -> list[str]:
    """Upsert managed .gitignore block. Returns paths created/repaired."""
    repaired: list[str] = []
    gitignore_rel = ensure_gitignore(project)
    if gitignore_rel is not None:
        repaired.append(gitignore_rel)
        if manifest is not None:
            record_file(manifest, gitignore_rel, project / gitignore_rel)
            record_core_file(manifest, gitignore_rel)
    return repaired


def _split_mdc(content: str) -> tuple[str, str]:
    """Return (frontmatter, body) from an .mdc file."""
    if not content.startswith("---"):
        return "", content.strip()
    parts = content.split("---", 2)
    if len(parts) < 3:
        return "", content.strip()
    return parts[1].strip(), parts[2].strip()


_CONSTITUTION_CORE_REL = ".cursor/rules/constitution-core.mdc"
_LEGACY_CORE_REL = ".cursor/rules/nwob-core.mdc"
_LEGACY_DEFAULT_REL = ".cursor/rules/nwob-default.mdc"

_DEDUP_DEFAULT_LINE_MARKERS = (
    "Phase 0 Discovery",
    "Agent Persona",
    "Artifact Management",
    "SDD Gates",
)


def _dedupe_default_guidelines_body(body: str) -> str:
    """Drop default bullets duplicated by the NWOB Core operational section."""
    return "\n".join(
        line
        for line in body.splitlines()
        if not any(marker in line for marker in _DEDUP_DEFAULT_LINE_MARKERS)
    ).strip()


def _render_constitution_core_rule(skills_root: Path) -> str:
    """Merge nwob-core operational rules with cross-platform constitution-core guidelines."""
    core_src = skills_root / "integrations" / "cursor" / "rules" / "nwob-core.mdc"
    constitution_src = skills_root / "rules" / "constitution-core.mdc"
    if not core_src.is_file() or not constitution_src.is_file():
        raise FileNotFoundError(
            f"Constitution core rule sources missing under {skills_root}"
        )

    _, core_body = _split_mdc(core_src.read_text(encoding="utf-8"))
    _, constitution_body = _split_mdc(constitution_src.read_text(encoding="utf-8"))
    constitution_body = constitution_body.removeprefix("# Constitution Core").strip()
    constitution_body = _dedupe_default_guidelines_body(constitution_body)

    frontmatter = (
        "---\n"
        "description: NWOB Phase 0 discovery, SDD gates, and cross-platform constitution "
        "core principles\n"
        "alwaysApply: true\n"
        "---"
    )
    return (
        rewrite_project_paths(
            f"{frontmatter}\n\n"
            f"{core_body.strip()}\n\n"
            f"# Constitution Core\n\n"
            f"{constitution_body.strip()}\n"
        )
    )


def _render_combined_default_rule(skills_root: Path) -> str:
    """Backward-compatible alias for constitution core rule rendering."""
    return _render_constitution_core_rule(skills_root)


def _remove_managed_legacy_rule(
    project: Path,
    manifest: dict[str, Any] | None,
    legacy_rel: str,
) -> bool:
    """Remove a stale managed rule file when superseded by a newer constitution rule."""
    legacy = project / legacy_rel
    if not legacy.is_file():
        return False
    if manifest is None:
        return False
    core_files = manifest.get("core_files", [])
    if legacy_rel not in core_files:
        return False
    legacy.unlink()
    manifest["core_files"] = [path for path in core_files if path != legacy_rel]
    manifest.get("files", {}).pop(legacy_rel, None)
    return True


def _remove_legacy_core_rule(project: Path, manifest: dict[str, Any] | None) -> bool:
    """Remove stale nwob-core.mdc when it was NWOB-managed."""
    return _remove_managed_legacy_rule(project, manifest, _LEGACY_CORE_REL)


def _remove_legacy_default_rule(project: Path, manifest: dict[str, Any] | None) -> bool:
    """Remove stale nwob-default.mdc when superseded by constitution-core.mdc."""
    return _remove_managed_legacy_rule(project, manifest, _LEGACY_DEFAULT_REL)


def _install_constitution_core_rule(
    project: Path,
    manifest: dict[str, Any],
    force: bool,
    *,
    skills_root: Path | None = None,
) -> bool:
    root = skills_root or _resolve_skills_root(manifest)
    if root is None:
        return False
    dest = project / _CONSTITUTION_CORE_REL
    if dest.exists() and not force:
        return False
    content = _render_constitution_core_rule(root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(content, encoding="utf-8")
    record_file(manifest, _CONSTITUTION_CORE_REL, dest)
    record_core_file(manifest, _CONSTITUTION_CORE_REL)
    return True


def _install_combined_default_rule(
    project: Path,
    manifest: dict[str, Any],
    force: bool,
    *,
    skills_root: Path | None = None,
) -> bool:
    """Backward-compatible alias for constitution core rule installation."""
    return _install_constitution_core_rule(
        project, manifest, force, skills_root=skills_root
    )


def ensure_constitution_core_rule(
    project: Path,
    manifest: dict[str, Any] | None,
    *,
    force: bool = False,
    skills_root: Path | None = None,
) -> list[str]:
    """Ensure constitution-core.mdc exists. Returns relative paths created/repaired."""
    if manifest is None:
        return []
    repaired: list[str] = []
    dest = project / _CONSTITUTION_CORE_REL
    if not dest.exists() or force:
        if _install_constitution_core_rule(
            project, manifest, force, skills_root=skills_root
        ):
            repaired.append(_CONSTITUTION_CORE_REL)
    if _remove_legacy_core_rule(project, manifest):
        repaired.append(f"removed {_LEGACY_CORE_REL}")
    if _remove_legacy_default_rule(project, manifest):
        repaired.append(f"removed {_LEGACY_DEFAULT_REL}")
    return repaired


def ensure_combined_default_rule(
    project: Path,
    manifest: dict[str, Any] | None,
    *,
    force: bool = False,
    skills_root: Path | None = None,
) -> list[str]:
    """Backward-compatible alias for ensure_constitution_core_rule."""
    return ensure_constitution_core_rule(
        project, manifest, force=force, skills_root=skills_root
    )


def _resolve_skills_root(manifest: dict[str, Any] | None) -> Path | None:
    """Resolve nwob-agent-skills root; fall back to manifest record when env lookup fails."""
    try:
        return repo_root()
    except FileNotFoundError:
        if manifest and manifest.get("nwob_skills_root"):
            root = Path(manifest["nwob_skills_root"])
            if (root / "bundles" / "catalog.json").is_file():
                return root
    return None


def _install_project_cursor_rules(
    project: Path,
    manifest: dict[str, Any],
    force: bool,
    *,
    skills_root: Path | None = None,
) -> None:
    catalog = load_catalog()
    root = skills_root or _resolve_skills_root(manifest)
    if root is None:
        return
    src_base = root / "rules"
    for entry in catalog.get("core", {}).get("project_rules", []):
        source = entry.get("source")
        dest_name = entry.get("dest")
        if not source or not dest_name:
            continue
        src = src_base / source
        if not src.is_file():
            continue
        dest = project / ".cursor" / "rules" / dest_name
        if _copy_file(src, dest, force=force):
            rel = f".cursor/rules/{dest_name}"
            record_file(manifest, rel, dest)
            record_core_file(manifest, rel)


def ensure_project_cursor_rules(
    project: Path,
    manifest: dict[str, Any] | None,
    *,
    force: bool = False,
    skills_root: Path | None = None,
) -> list[str]:
    """Ensure generic and stack-specific project rules exist. Returns relative paths created."""
    catalog = load_catalog()
    root = skills_root or _resolve_skills_root(manifest)
    if root is None:
        return []
    repaired: list[str] = []
    src_base = root / "rules"
    for entry in catalog.get("core", {}).get("project_rules", []):
        source = entry.get("source")
        dest_name = entry.get("dest")
        if not source or not dest_name:
            continue
        src = src_base / source
        if not src.is_file():
            continue
        dest = project / ".cursor" / "rules" / dest_name
        if dest.exists() and not force:
            continue
        if _copy_file(src, dest, force=force):
            rel = f".cursor/rules/{dest_name}"
            repaired.append(rel)
            if manifest is not None:
                record_file(manifest, rel, dest)
                record_core_file(manifest, rel)
    return repaired


def _install_cursor_skill_flat(
    project: Path,
    skill_rel: str,
    manifest: dict[str, Any],
    persona_id: str,
    force: bool,
) -> str:
    """Copy skill dir to .cursor/skills/<frontmatter-name>/. Returns skill name."""
    skill_path = skills_dir() / skill_rel
    if not skill_path.is_dir():
        raise FileNotFoundError(f"Skill directory not found: {skill_path}")

    skill_name = skill_frontmatter_name(skill_rel)
    dest_dir = project / ".cursor" / "skills" / skill_name

    md_files = sorted(skill_path.glob("*.md"))
    if not any(f.name == "SKILL.md" for f in md_files):
        raise FileNotFoundError(f"Skill not found: {skill_path / 'SKILL.md'}")

    for src in md_files:
        dest = dest_dir / src.name
        transform = "skill" if src.name == "SKILL.md" else None
        if _copy_file(src, dest, transform=transform, force=force):
            rel = f".cursor/skills/{skill_name}/{src.name}"
            record_file(manifest, rel, dest)
            record_persona_asset(manifest, persona_id, "skills", f".cursor/skills/{skill_name}")

    return skill_name


def _install_core_skills(project: Path, manifest: dict[str, Any], force: bool) -> None:
    catalog = load_catalog()
    for skill_name in catalog.get("core", {}).get("skills", []):
        _install_cursor_skill_flat(
            project, f"core/{skill_name}", manifest, "core", force
        )
        record_core_file(manifest, f".cursor/skills/{skill_name}")


def _install_template(project: Path, template_rel: str, manifest: dict[str, Any], force: bool) -> None:
    src = templates_dir() / template_rel
    if not src.is_file():
        return
    dest_name = Path(template_rel).name
    dest = project / ".nwob" / "templates" / dest_name
    if _copy_file(src, dest, force=force):
        record_file(manifest, f".nwob/templates/{dest_name}", dest)


def _render_persona_mdc(persona_id: str, bundle: dict[str, Any]) -> str:
    template_path = integrations_dir() / "cursor" / "rules" / "_persona-template.mdc"
    template = template_path.read_text(encoding="utf-8")
    meta = bundle.get("bundle", {})
    boundaries = (
        bundle.get("provides", {})
        .get("cursor", {})
        .get("rules", {})
        .get("boundaries", [])
    )
    boundary_lines = []
    for boundary_ref in boundaries:
        stem = Path(boundary_ref).stem
        title = stem.replace("-", " ").title()
        boundary_lines.append(
            f"- {title}: [`{stem}.md`](../../{NWOB_REFERENCES_DIR}/{boundary_ref})"
        )
    return (
        template.replace("{{PERSONA_TITLE}}", meta.get("name", persona_id))
        .replace("{{PERSONA_ID}}", persona_id)
        .replace("{{BOUNDARY_LINKS}}", "\n".join(boundary_lines) if boundary_lines else "")
    )


def _render_boundary_mdc(boundary_ref: str) -> str:
    template_path = integrations_dir() / "cursor" / "rules" / "_boundary-template.mdc"
    template = template_path.read_text(encoding="utf-8")
    stem = Path(boundary_ref).stem
    title = stem.replace("-", " ").title()
    return (
        template.replace("{{BOUNDARY_TITLE}}", title)
        .replace("{{BOUNDARY_FILE}}", Path(boundary_ref).name)
        .replace("{{BOUNDARY_REF}}", boundary_ref)
    )


def _install_persona_cursor_rules(
    project: Path,
    persona_id: str,
    bundle: dict[str, Any],
    manifest: dict[str, Any],
    force: bool,
) -> None:
    cursor_rules = bundle.get("provides", {}).get("cursor", {}).get("rules", {})
    rules_dest_dir = project / ".cursor" / "rules"

    if cursor_rules.get("persona"):
        dest = rules_dest_dir / f"nwob-{persona_id}.mdc"
        content = _render_persona_mdc(persona_id, bundle)
        if force or not dest.exists():
            rules_dest_dir.mkdir(parents=True, exist_ok=True)
            dest.write_text(content, encoding="utf-8")
            rel = f".cursor/rules/nwob-{persona_id}.mdc"
            record_file(manifest, rel, dest)
            record_persona_asset(manifest, persona_id, "rules", rel)

    for boundary_ref in cursor_rules.get("boundaries", []):
        stem = Path(boundary_ref).stem
        dest = rules_dest_dir / f"{stem}.mdc"
        content = _render_boundary_mdc(boundary_ref)
        if force or not dest.exists():
            rules_dest_dir.mkdir(parents=True, exist_ok=True)
            dest.write_text(content, encoding="utf-8")
            rel = f".cursor/rules/{stem}.mdc"
            record_file(manifest, rel, dest)
            record_persona_asset(manifest, persona_id, "rules", rel)


def _install_agent(project: Path, agent_rel: str, persona_id: str, manifest: dict[str, Any], force: bool) -> None:
    src = agents_dir() / Path(agent_rel).name
    persona = Path(agent_rel).stem
    dest = project / "agents" / f"{persona}.md"
    if _copy_file(src, dest, transform="agent", force=force):
        rel = f"agents/{persona}.md"
        record_file(manifest, rel, dest)
        record_persona_asset(manifest, persona_id, "agents", rel)


def _install_scaffolds(
    project: Path,
    bundle: dict[str, Any],
    manifest: dict[str, Any],
    force: bool = False,
    *,
    scaffold_nwob_docs: bool = True,
) -> None:
    """Install persona scaffold files. Create-only — never overwrite existing content.

    ``force`` is accepted for call-site compatibility but ignored for content files;
    living SDD/architecture docs must not be clobbered by init, persona add, or switch.
    """
    del force  # create-only; asset force must not rewrite docs
    for scaffold in bundle.get("provides", {}).get("scaffolds", []):
        path_str = scaffold.get("path", "")
        if not path_str:
            continue
        if not scaffold_nwob_docs and is_nwob_docs_path(path_str):
            continue
        if path_str.endswith("/"):
            dest = project / path_str
            dest.mkdir(parents=True, exist_ok=True)
            continue
        dest = project / path_str
        if dest.exists():
            continue
        template_rel = scaffold.get("template")
        if template_rel:
            src = templates_dir() / template_rel
            if src.is_file():
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
                record_file(manifest, path_str, dest)


def install_core(
    project: Path,
    manifest: dict[str, Any],
    *,
    force: bool = False,
    scaffold_nwob_docs: bool = True,
) -> None:
    """Install shared core assets (references, nwob-docs, core rules/skills/commands)."""
    _install_setup_script(project, manifest, force)
    init_mapping_from_example(project, force=False)
    _install_core_references(project, manifest, force)
    _install_nwob_docs_scaffold(
        project, manifest, force, scaffold_nwob_docs=scaffold_nwob_docs
    )
    _install_core_scaffold_files(
        project, manifest, force, scaffold_nwob_docs=scaffold_nwob_docs
    )
    ensure_project_gitignore(project, manifest)
    _install_constitution_core_rule(project, manifest, force)
    _remove_legacy_core_rule(project, manifest)
    _remove_legacy_default_rule(project, manifest)
    _install_project_cursor_rules(project, manifest, force)
    _install_core_skills(project, manifest, force)
    for rel in install_core_commands(project, force=force):
        record_core_file(manifest, rel)
    manifest["core_installed"] = True


def _remove_persona_assets(project: Path, persona_id: str, manifest: dict[str, Any]) -> None:
    """Remove persona-specific cursor assets from the project."""
    assets = manifest.get("persona_assets", {}).get(persona_id, {})

    for skill_dir_rel in assets.get("skills", []):
        skill_dir = project / skill_dir_rel
        if skill_dir.is_dir():
            shutil.rmtree(skill_dir)

    for rule_rel in assets.get("rules", []):
        rule_file = project / rule_rel
        if rule_file.is_file():
            rule_file.unlink()

    for agent_rel in assets.get("agents", []):
        agent_file = project / agent_rel
        if agent_file.is_file():
            agent_file.unlink()

    try:
        bundle = load_bundle(persona_id)
        remove_persona_commands(project, persona_id, bundle)
    except FileNotFoundError:
        pass

    for cmd_rel in assets.get("commands", []):
        cmd_file = project / cmd_rel
        if cmd_file.is_file():
            cmd_file.unlink()

    manifest["persona_assets"][persona_id] = {
        "skills": [],
        "rules": [],
        "agents": [],
        "commands": [],
    }


def install_persona_cursor_assets(
    project: Path,
    persona_id: str,
    manifest: dict[str, Any],
    *,
    force: bool = False,
    scaffold_nwob_docs: bool | None = None,
) -> dict[str, Any]:
    """Install cursor skills, rules, agent, commands, and scaffolds for one persona."""
    if scaffold_nwob_docs is None:
        scaffold_nwob_docs = scaffold_nwob_docs_enabled(project)
    bundle = load_bundle(persona_id)
    provides = bundle.get("provides", {})

    for skill_rel in provides.get("skills", []):
        _install_cursor_skill_flat(project, skill_rel, manifest, persona_id, force)

    agent_rel = provides.get("agent")
    if agent_rel:
        _install_agent(project, agent_rel, persona_id, manifest, force)

    for template_rel in provides.get("templates", []):
        _install_template(project, template_rel, manifest, force)

    _install_persona_cursor_rules(project, persona_id, bundle, manifest, force)
    # Asset force must not rewrite living docs — scaffolds are always create-only.
    _install_scaffolds(
        project, bundle, manifest, force=False, scaffold_nwob_docs=scaffold_nwob_docs
    )

    written_commands = install_cursor_commands(project, persona_id, bundle, force=force)
    for rel in written_commands:
        dest = project / rel
        if dest.is_file():
            record_file(manifest, rel, dest)
            record_persona_asset(manifest, persona_id, "commands", rel)

    return {
        "skills": len(provides.get("skills", [])),
        "commands": written_commands,
        "templates": len(provides.get("templates", [])),
    }


def install_persona(
    project: Path,
    persona_id: str,
    *,
    integration: str = "cursor",
    force: bool = False,
    set_active: bool = False,
    scaffold_nwob_docs: bool = True,
) -> dict[str, Any]:
    """Install a persona bundle into project. Returns summary dict."""
    project = project.resolve()
    manifest = load_manifest(project)

    if not manifest.get("core_installed"):
        install_core(project, manifest, force=force, scaffold_nwob_docs=scaffold_nwob_docs)

    save_scaffold_option(project, scaffold_nwob_docs)

    installed = manifest.get("installed_personas", [])
    if persona_id not in installed:
        installed.append(persona_id)
    manifest["installed_personas"] = installed

    summary: dict[str, Any] = {"persona": persona_id, "skills": 0, "commands": [], "templates": 0}

    if set_active:
        old_persona = load_active_persona(project).get("persona")
        if old_persona and old_persona != persona_id:
            _remove_persona_assets(project, old_persona, manifest)

        summary = install_persona_cursor_assets(
            project, persona_id, manifest, force=force, scaffold_nwob_docs=scaffold_nwob_docs
        )
        save_active_persona(project, persona_id)
        update_agents_md(project, persona_id, installed)
    elif not load_active_persona(project).get("persona"):
        summary = install_persona_cursor_assets(
            project, persona_id, manifest, force=force, scaffold_nwob_docs=scaffold_nwob_docs
        )
        save_active_persona(project, persona_id)
        update_agents_md(project, persona_id, installed)
    else:
        current = load_active_persona(project).get("persona")
        if current:
            update_agents_md(project, current, installed)

    manifest["nwob_version"] = __version__
    manifest["nwob_skills_root"] = str(repo_root())
    save_manifest(project, manifest)

    options = load_init_options(project)
    options["integration"] = integration
    options["installed_personas"] = installed
    options["nwob_skills_root"] = str(repo_root())
    options["scaffold_nwob_docs"] = scaffold_nwob_docs
    save_init_options(project, options)

    return summary


def switch_persona(project: Path, persona_id: str, *, force: bool = False) -> None:
    """Swap active persona — remove prior cursor assets and install new persona."""
    project = project.resolve()
    manifest = load_manifest(project)
    installed = manifest.get("installed_personas", [])

    if persona_id not in installed:
        raise ValueError(
            f"Persona '{persona_id}' is not installed. Run: nwob persona add {persona_id}"
        )

    old_persona = load_active_persona(project).get("persona")
    if old_persona == persona_id and not force:
        return

    if old_persona and old_persona != persona_id:
        _remove_persona_assets(project, old_persona, manifest)

    install_persona_cursor_assets(project, persona_id, manifest, force=True)
    save_active_persona(project, persona_id)
    update_agents_md(project, persona_id, manifest["installed_personas"])
    save_manifest(project, manifest)
