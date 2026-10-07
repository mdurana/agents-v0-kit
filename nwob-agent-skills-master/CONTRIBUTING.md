# Contributing to NWOB Agent Skills

Thanks for your interest in contributing! This project is a collection of production-grade Product Owner, Solution Architect, Lead Builder, Builder, Pod Builder, and Observer skills for AI coding agents — constitution-compliant workflows for spec-driven delivery, enterprise architecture, leader-facing presentations, AI-assisted implementation, pod co-design/audit, and pilot observation.

## Adding a New Skill

1. Create a directory under `skills/<role>/` with a kebab-case name (`product-owner`, `solution-architect`, `lead-builder`, `builder`, or `observer`). Persona bundles (e.g. `pod-builder`) compose existing skills — see `bundles/<persona>/bundle.yml`.
2. Add a `SKILL.md` following the format in [README.md#how-skills-work](README.md#how-skills-work) and [AGENTS.md](AGENTS.md#creating-a-new-skill)
3. Include YAML frontmatter with `name` and `description` fields
4. Ensure the `description` starts with what the skill does (third person), then includes one or more `Use when` trigger conditions
5. Update documentation when adding a new skill:
   - [AGENTS.md](AGENTS.md) intent mapping (and command mapping for Product Owner or Observer skills)
   - Skill table in [README.md](README.md#all-26-skills)
   - Persona file in [agents/](agents/) when the role has one
   - For Product Owner presentation skills: [references/rules/presentation-standards.md](references/rules/presentation-standards.md) and [product-owner-skill-boundaries.md](references/rules/product-owner-skill-boundaries.md)
   - For Solution Architect slash commands: [references/rules/solution-architect-command-standards.md](references/rules/solution-architect-command-standards.md), [solution-architect-skill-boundaries.md](references/rules/solution-architect-skill-boundaries.md), and [bundles/solution-architect/bundle.yml](bundles/solution-architect/bundle.yml)
   - For new Product Owner, Solution Architect, or Observer slash commands: README [Commands](README.md#commands) section, AGENTS.md [Slash Commands](AGENTS.md#slash-commands), `bundles/<persona>/bundle.yml`, and `src/nwob_cli/_commands.py` (`_implement_guard`)

### Skill Quality Bar

Skills should be:

- **Specific** — Actionable steps, not vague advice
- **Verifiable** — Clear exit criteria with evidence requirements
- **Battle-tested** — Based on real product, architecture, and presentation workflows, not theoretical ideals
- **Minimal** — Only the content needed to guide the agent correctly

### Default vs. override constraints

Per [AGENTS.md — Default vs. Override Constraints](AGENTS.md#default-vs-override-constraints):

- New skills must **not** hard-code technology stack (Default technology stack in constitution-core) or soft-delete/DLM (Default data lifecycle in constitution-core) as immovable
- Use *"default per constitution sections 2 and 5 unless overridden"* language
- The **Constitution Compliance** section must distinguish **mandatory** rules (SDD, Gherkin, stateless K8s, coverage, RFC 7807, etc.) from **default-overridable** rules (stack, data lifecycle)

### Structure

Every new skill must have:

- `SKILL.md` in the skill directory
- YAML frontmatter with valid `name` and `description`

New skills should generally follow the standard anatomy:

- **Overview** — What this skill does and why it matters
- **When to Use** — Triggering conditions
- **Process** — Step-by-step workflow
- **Constitution Compliance** — Alignment with [rules/constitution-core.mdc](rules/constitution-core.mdc)
- **Common Rationalizations** — Excuses agents use to skip steps, with rebuttals
- **Red Flags** — Warning signs that the skill is being applied incorrectly
- **Verification** — How to confirm the skill was applied correctly

The frontmatter fields above are required. The section anatomy is a recommended pattern: equivalent headings such as `How It Works`, `Workflow`, or `Core Process` are fine when they preserve the same intent and keep the skill easy to follow.

Keep `SKILL.md` under 500 lines. Put detailed reference material in separate files under `references/` and link from `SKILL.md` (one level deep only).

All new skills must comply with mandatory constitution rules; treat technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) as defaults overridable per [AGENTS.md](AGENTS.md#default-vs-override-constraints).

## Persona Bundles and Initialization

Persona-scoped project bootstrap is defined in [bundles/](bundles/). Each persona has a `bundle.yml` manifest listing skills, commands, templates, and expected artifacts.

When adding a skill that belongs to a persona bundle:

1. Add the skill under `skills/<role>/<skill-name>/` with unique frontmatter `name` (used as `.cursor/skills/<name>/` install path)
2. Update `bundles/<persona>/bundle.yml`:
   - `provides.skills` — repo path `role/skill-dir`
   - `provides.commands` — if slash command applies
   - `provides.scaffolds` — `nwob-docs/` paths and template refs
   - `provides.cursor.rules.boundaries` — role-scoped rules to mirror as `.mdc`
3. Add a Cursor command stub entry if the skill has a slash command (CLI generates from `integrations/cursor/commands/_command-template.md`)
4. Update [docs/initialization.md](docs/initialization.md) artifact map if outputs change
5. For shared rules, add under `references/rules/` and update `bundles/catalog.json` `core.references` if universal

Run `nwob bundle info <persona>` to verify bundle contents after changes.

See [README — Syncing agent and skill changes to bundles](README.md#syncing-agent-and-skill-changes-to-bundles) for the full change-type matrix.

### What Not to Do

- Don't duplicate content between skills — reference other skills instead
- Don't add skills that are vague advice instead of actionable processes
- Don't create supporting files unless content exceeds 100 lines
- Don't create an empty `scripts/` directory just to match another skill — add `scripts/` only when the skill includes runnable helpers
- Don't put reference material inside skill directories — use `references/` instead
- Don't bypass spec-driven development gates — skills enforce `epic-spec.md` → `epic-spec.md` backlog index → `story-tasks.md` / `story-tasks.md` before implementation

## Modifying Existing Skills

- Keep changes focused and minimal
- Preserve the existing structure and tone
- Test that YAML frontmatter remains valid after edits
- Verify intent mapping in [AGENTS.md](AGENTS.md) still matches any renamed or re-scoped skills
- Verify command→skill mappings in [README.md](README.md), [AGENTS.md](AGENTS.md), and (for PM) [presentation-standards.md](references/rules/presentation-standards.md) remain accurate after renames; for Lead Builder, Builder, and Observer slash commands, also verify the respective [agents/](agents/) persona file

## Reporting Issues

Open an issue if you find:

- A skill that gives incorrect or outdated guidance
- Missing coverage for a common product, architecture, or presentation workflow
- Inconsistencies between skills, command/skill documentation, or with the [Enterprise System Constitution](rules/constitution-core.mdc)
- Gaps in SDD artifact requirements (`epic-spec.md`, `epic-spec.md` backlog index, `story-tasks.md` + `story-tasks.md`)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
