"""Generate and update project AGENTS.md overlay."""

from __future__ import annotations

from pathlib import Path

MARKER_START = "<!-- nwob:active-persona:start -->"
MARKER_END = "<!-- nwob:active-persona:end -->"
NWOB_HEADER = "<!-- nwob:managed — do not remove this block without `nwob init` -->"

PERSONA_COMMANDS: dict[str, list[str]] = {
    "product-owner": [
        "/problem",
        "/ideate",
        "/roadmap",
        "/features",
        "/backlog",
        "/value",
        "/intake",
        "/collect",
        "/present",
        "/enrich",
        "/deck",
    ],
    "solution-architect": [
        "/c4",
        "/pattern",
        "/platform",
        "/services",
        "/contracts",
        "/ops",
        "/adr",
        "/arc",
        "/architecture",
    ],
    "lead-builder": ["*(intent-only — LB skills in `.cursor/skills/`)*"],
    "builder": ["/audit", "*(co-design, validate, review by intent)*"],
    "pod-builder": ["/audit", "*(orchestrate-design, trigger-ai-build, co-design, validate, review by intent)*"],
    "observer": ["/summarize", "/meeting", "/handoff"],
}


def _active_block(active: str, installed: list[str]) -> str:
    lines = [
        MARKER_START,
        f"**Active persona:** `{active}`",
        f"**Installed personas:** {', '.join(f'`{p}`' for p in installed)}",
        "",
        f"Persona file: [`agents/{active}.md`](agents/{active}.md)",
        f"Persona rule: [`.cursor/rules/nwob-{active}.mdc`](.cursor/rules/nwob-{active}.mdc)",
        "",
        "### Available commands (installed personas)",
        "",
    ]
    for pid in installed:
        cmds = PERSONA_COMMANDS.get(pid, [])
        lines.append(f"- **{pid}:** {' '.join(cmds)}")
    lines.append("")
    lines.append("Switch persona: `/persona` or `/switch` (swaps `.cursor/skills` and `.cursor/rules`)")
    lines.append(MARKER_END)
    return "\n".join(lines)


def _full_agents_md(active: str, installed: list[str]) -> str:
    return "\n".join(
        [
            NWOB_HEADER,
            "",
            "# NWOB Agent Skills (Project)",
            "",
            "This project uses [NWOB Agent Skills](https://github.com/nwob-agent-skills) "
            "for constitution-compliant spec-driven delivery.",
            "",
            "## Core Rules",
            "",
            "- If a task matches a skill, load it from `.cursor/skills/<skill-name>/SKILL.md` "
            "and follow exactly.",
            "- Constitution core: [`.cursor/rules/constitution-core.mdc`](.cursor/rules/constitution-core.mdc)",
            "- Constitution custom (product overrides): [`.cursor/rules/constitution-custom.mdc`](.cursor/rules/constitution-custom.mdc)",
            "- Rules: [`nwob-references/rules/`](nwob-references/rules/)",
            "- SDD gate: initial `epic-spec.md` (`spec`); build needs in-scope `story-spec.md` + `story-tasks.md`.",
            "- Artifact paths: resolve via `.nwob/artifact-paths.json` when present; default `nwob-docs/` layout otherwise.",
            "- Switch persona: `/persona` or `/switch` (see `.cursor/skills/switch-persona/SKILL.md`).",
            "- One active persona in `.cursor/` at a time; only `.cursor/rules/constitution-custom.mdc` is intended for git commit.",
            "",
            _active_block(active, installed),
            "",
            "## SDD Artifacts",
            "",
            "Paths resolve from `.nwob/artifact-paths.json` (gitignored, local) or default under `nwob-docs/`:",
            "",
            "| Key | Required | Default path | Purpose |",
            "|-----|----------|--------------|---------|",
            "| `spec` | yes | `nwob-docs/sdd/epic-spec.md` | Problem, vision, HL US/TS, chronological backlog index |",
            "| `stories_dir` | no | `nwob-docs/sdd/stories/` | Per-story folders (`{STORY_ID}/story-spec.md`, `story-tasks.md`) |",
            "",
            "Omit optional keys to use defaults. Architecture (`masterplan.md`, flat "
            "`sdd/components/{component-name}-plan.md`), meetings, and other non-SDD "
            "artifacts use fixed `nwob-docs/` paths (not in this mapping).",
            "",
            "Write ACL: read any `*-spec.md` / `*-plan.md` / `*-tasks.md`; write only via "
            "owning skills (PO/SA/LB for epic-spec and product story-spec; "
            "`co-design-solution` for story-spec technical annex + story-tasks).",
            "",
            "Cursor execution plans from `trigger-ai-build` live in `~/.cursor/plans/` only — they are not SDD files.",
            "",
            "Run `nwob config paths --show` to print resolved SDD paths for this project.",
            "",
        ]
    )


def update_agents_md(project: Path, active: str, installed: list[str]) -> Path:
    """Create or patch AGENTS.md with NWOB overlay."""
    agents_path = project / "AGENTS.md"
    block = _active_block(active, installed)

    if not agents_path.exists():
        agents_path.write_text(_full_agents_md(active, installed), encoding="utf-8")
        return agents_path

    content = agents_path.read_text(encoding="utf-8")
    if MARKER_START in content and MARKER_END in content:
        before = content[: content.index(MARKER_START)]
        after = content[content.index(MARKER_END) + len(MARKER_END) :]
        content = before.rstrip() + "\n\n" + block + after
    elif NWOB_HEADER in content:
        if MARKER_START not in content:
            content = content.rstrip() + "\n\n" + block + "\n"
    else:
        content = content.rstrip() + "\n\n" + _full_agents_md(active, installed)

    agents_path.write_text(content, encoding="utf-8")
    return agents_path
