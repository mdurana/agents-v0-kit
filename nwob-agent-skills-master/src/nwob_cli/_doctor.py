"""Doctor — verify NWOB project health."""

from __future__ import annotations

from pathlib import Path

from ._artifact_paths import mapping_path, scaffold_nwob_docs_enabled, validate_mapping
from ._bundles import load_bundle, load_catalog, skill_frontmatter_name
from ._install import ensure_constitution_core_rule, ensure_project_cursor_rules, ensure_project_gitignore
from ._manifest import load_active_persona, load_manifest, manifest_path, nwob_dir, save_manifest
from ._paths import NWOB_REFERENCES_DIR


def run_doctor(project: Path) -> tuple[bool, list[str]]:
    project = project.resolve()
    issues: list[str] = []
    warnings: list[str] = []
    repairs: list[str] = []

    if not nwob_dir(project).is_dir():
        issues.append("Missing `.nwob/` directory — run `nwob init`")
        return False, issues

    if not manifest_path(project).is_file():
        issues.append("Missing `.nwob/manifest.json`")

    sdd_layout = project / NWOB_REFERENCES_DIR / "rules" / "sdd-artifact-layout.md"
    if not sdd_layout.is_file():
        issues.append(f"Missing `{NWOB_REFERENCES_DIR}/rules/sdd-artifact-layout.md`")

    for leftover in (
        project / NWOB_REFERENCES_DIR / "constitution.md",
        project / "references" / "constitution.md",
    ):
        if leftover.is_file():
            warnings.append(
                f"Leftover `{leftover.relative_to(project)}` detected — constitution now lives in "
                "`.cursor/rules/constitution-core.mdc` and `.cursor/rules/constitution-custom.mdc`; "
                "delete the leftover file or re-run `nwob init --force`"
            )

    nwob_docs_sdd = project / "nwob-docs" / "sdd"
    if scaffold_nwob_docs_enabled(project):
        if not nwob_docs_sdd.is_dir():
            issues.append("Missing `nwob-docs/sdd/` directory")
    elif not mapping_path(project).is_file():
        warnings.append(
            "External docs mode: missing `.nwob/artifact-paths.json` — "
            "run `nwob config paths --init` and map existing doc paths"
        )

    mapping_errors, mapping_warnings = validate_mapping(project)
    warnings.extend(mapping_warnings)
    issues.extend(mapping_errors)

    manifest = load_manifest(project)
    gitignore_repaired = ensure_project_gitignore(project, manifest)
    if gitignore_repaired:
        save_manifest(project, manifest)
        repairs.append("Updated managed .gitignore block for NWOB local install output")

    core_repaired = ensure_constitution_core_rule(project, manifest)
    if core_repaired:
        save_manifest(project, manifest)
        repairs.append(
            "Repaired constitution core cursor rule: " + ", ".join(core_repaired)
        )

    rules_repaired = ensure_project_cursor_rules(project, manifest)
    if rules_repaired:
        save_manifest(project, manifest)
        repairs.append(
            "Created or migrated project cursor rules: " + ", ".join(rules_repaired)
        )

    core_rule = project / ".cursor" / "rules" / "constitution-core.mdc"
    if not core_rule.is_file():
        issues.append("Missing `.cursor/rules/constitution-core.mdc`")

    custom_rule = project / ".cursor" / "rules" / "constitution-custom.mdc"
    if not custom_rule.is_file():
        issues.append("Missing `.cursor/rules/constitution-custom.mdc`")

    legacy_default = project / ".cursor" / "rules" / "nwob-default.mdc"
    if legacy_default.is_file():
        warnings.append(
            "Legacy `.cursor/rules/nwob-default.mdc` detected — run `nwob doctor` "
            "or `nwob init --force` to migrate to `constitution-core.mdc`"
        )

    legacy_core = project / ".cursor" / "rules" / "nwob-core.mdc"
    if legacy_core.is_file():
        warnings.append(
            "Legacy `.cursor/rules/nwob-core.mdc` detected — run `nwob doctor` "
            "or `nwob init --force` to migrate to `constitution-core.mdc`"
        )

    try:
        catalog = load_catalog()
        for entry in catalog.get("core", {}).get("project_rules", []):
            dest_name = entry.get("dest")
            if not dest_name:
                continue
            dest = project / ".cursor" / "rules" / dest_name
            if not dest.is_file():
                issues.append(f"Missing `.cursor/rules/{dest_name}`")
    except (FileNotFoundError, ValueError) as exc:
        issues.append(str(exc))

    installed = manifest.get("installed_personas", [])
    if not installed:
        issues.append("No personas installed in manifest")

    active = load_active_persona(project)
    persona = active.get("persona")
    if not persona:
        issues.append("Missing or empty `.nwob/active-persona.json`")
    elif persona not in installed:
        issues.append(f"Active persona '{persona}' is not in installed personas")
    else:
        agent_file = project / "agents" / f"{persona}.md"
        if not agent_file.is_file():
            issues.append(f"Missing agent file for active persona '{persona}'")

        persona_rule = project / ".cursor" / "rules" / f"nwob-{persona}.mdc"
        if not persona_rule.is_file():
            issues.append(f"Missing persona rule `.cursor/rules/nwob-{persona}.mdc`")

        try:
            bundle = load_bundle(persona)
            for skill_rel in bundle.get("provides", {}).get("skills", []):
                skill_name = skill_frontmatter_name(skill_rel)
                skill_file = project / ".cursor" / "skills" / skill_name / "SKILL.md"
                if not skill_file.is_file():
                    issues.append(f"Missing skill `.cursor/skills/{skill_name}/SKILL.md`")
            for cmd in bundle.get("provides", {}).get("commands", []):
                cmd_name = cmd.get("name")
                if not cmd_name:
                    continue
                cmd_file = project / ".cursor" / "commands" / f"{cmd_name}.md"
                if not cmd_file.is_file():
                    issues.append(f"Missing command `.cursor/commands/{cmd_name}.md`")
        except (FileNotFoundError, ValueError) as exc:
            issues.append(str(exc))

    core_switch = project / ".cursor" / "skills" / "switch-persona" / "SKILL.md"
    if not core_switch.is_file():
        issues.append("Missing core skill: `.cursor/skills/switch-persona/SKILL.md`")

    persona_cmd = project / ".cursor" / "commands" / "persona.md"
    if not persona_cmd.is_file():
        issues.append("Missing `.cursor/commands/persona.md`")

    legacy_skills = project / ".nwob" / "skills"
    if legacy_skills.is_dir():
        issues.append(
            "Legacy `.nwob/skills/` detected — run `nwob persona switch <persona> --force` "
            "or re-init to migrate to `.cursor/skills/`"
        )

    legacy_memory = project / ".nwob" / "memory"
    if legacy_memory.is_dir():
        issues.append(
            "Legacy `.nwob/memory/` detected — constitution should be at "
            "`.cursor/rules/constitution-core.mdc` and `.cursor/rules/constitution-custom.mdc`"
        )

    all_messages = repairs + [f"[warning] {w}" for w in warnings] + issues
    return len(issues) == 0, all_messages
