# NWOB Project Initialization

Bootstrap NWOB agent skills in any repository with persona-scoped bundles. Initialized projects use `.cursor/skills/`, `.cursor/rules/`, project-root `nwob-references/`, and optional `nwob-docs/` artifacts per [sdd-artifact-layout.md](../references/rules/sdd-artifact-layout.md).

**Quick install (scaffold vs no-scaffold, numbered steps, expected trees):** [installation.md](../installation.md).

## Prerequisites

- **Python 3.11+** — required for `setup-nwob.sh`, `pip install -e .`, and the `nwob` CLI (`requires-python >=3.11` in `pyproject.toml`).
- macOS often ships `/usr/bin/python3` at 3.9.x; `setup-nwob.sh` auto-detects `python3.13`, `python3.12`, or `python3.11` when present. Override with `NWOB_PYTHON=/path/to/python3.12` if needed.

## Quick Start

### Option A: setup-nwob.sh (one-step bootstrap)

From any shell, using a local clone **or** Git remote URL for the skills source:

```bash
source /path/to/nwob-agent-skills/scripts/setup-nwob.sh \
  <SKILLS_SOURCE> /path/to/your-project product-owner
```

`SKILLS_SOURCE` may be:

- Local path to an `nwob-agent-skills` clone
- Git URL (`https://`, `http://`, `ssh://`, `git://`, `file://`, `git@host:org/repo.git`) — shallow-cloned into `~/.cache/nwob-agent-skills`

GitLab examples:

```bash
# HTTPS
source setup-nwob.sh https://gitlab.example.com/org/nwob-agent-skills.git . product-owner

# SSH
source setup-nwob.sh git@gitlab.example.com:org/nwob-agent-skills.git . product-owner

# Pin a branch instead of the remote default
NWOB_SKILLS_REF=master source setup-nwob.sh https://gitlab.example.com/org/nwob-agent-skills.git . product-owner
```

**Use `source`, not `./setup-nwob.sh`** — sourcing keeps the virtual environment active and leaves you in the project directory. The script changes no shell options in your session, so a failure returns a status instead of closing your terminal.

**Default:** `setup-nwob.sh` passes `--no-scaffold-docs` (no `nwob-docs/` tree). Init writes `.nwob/artifact-paths.json` with SDD keys (`spec` required; `stories_dir` optional) when that file is missing. Remove obsolete `plan` / `tasks` keys from older mappings — CLI warns when present. Architecture, meetings, and other non-SDD paths are **not** in the mapping — they use fixed `nwob-docs/` defaults. Edit the mapping for existing SDD docs, then run `nwob config paths --validate`. For greenfield projects that want the default `nwob-docs/` layout:

```bash
NWOB_SCAFFOLD_DOCS=1 source setup-nwob.sh <SKILLS_SOURCE> /path/to/your-project product-owner
```

Init copies `setup-nwob.sh` into the project root so teammates can re-run bootstrap without hunting for the source repo.

### Option B: nwob-init.sh (init only)

From the `nwob-agent-skills` repository:

```bash
cd /path/to/your-project
/path/to/nwob-agent-skills/scripts/nwob-init.sh --here --persona product-owner
```

### Option C: Python CLI (full persona management)

```bash
# Local development
cd nwob-agent-skills
python3 -m venv .venv && source .venv/bin/activate
pip install -e .

# Initialize
cd /path/to/your-project
nwob init --here --persona product-owner --integration cursor
```

### Existing codebase (docs elsewhere)

When spec, plan, architecture, and other docs already live outside `nwob-docs/`, **Option A (`setup-nwob.sh`) already skips the `nwob-docs/` scaffold by default.** Init writes `.nwob/artifact-paths.json` (gitignored) with SDD defaults when the file is missing. After bootstrap:

```bash
# Edit required spec (and optionally stories_dir) to match this repo
# Remove obsolete plan/tasks keys and any non-SDD keys from older templates
# Omit stories_dir to keep default nwob-docs/sdd/stories/
nwob config paths --validate
```

Or via `nwob-init.sh` / CLI directly:

```bash
/path/to/nwob-agent-skills/scripts/nwob-init.sh --here --persona product-owner --no-scaffold-docs
# or: nwob init --here --persona product-owner --no-scaffold-docs
```

For `nwob-init.sh` only, environment variable (same as `--no-scaffold-docs`):

```bash
NWOB_NO_SCAFFOLD_DOCS=1 ./scripts/nwob-init.sh --here --persona product-owner
```

## Persona Bundles

| Persona | Bundle ID | Commands | Primary artifacts (default paths) |
|---------|-----------|----------|-----------------------------------|
| Product Owner | `product-owner` | `/problem` … `/value`, `/intake` … `/deck` | Mapped `spec` (epic-spec backlog index); presentations under `nwob-docs/presentations/` |
| Solution Architect | `solution-architect` | `/define`, `/problem` … `/features`, `/intake`, `/c4` … `/architecture`, `/orchestrate-design`, `/audit` (co-equal with LB; 14 skills) | Mapped `spec`; dual `architecture.md` ↔ `sdd/masterplan.md`; flat `sdd/components/*-plan.md` |
| Lead Builder | `lead-builder` | Same SA/LB command set (co-equal; 14 skills) including `/orchestrate-design`, `/audit` | Same as Solution Architect; `design-package.md`; `observations/audit-report.md` |
| Builder | `builder` | *(intent-only)* | `stories_dir` (writes `story-spec.md` (technical annex) + `story-tasks.md` via co-design); MR draft and comment resolve by intent |
| Pod Builder | `pod-builder` | `/audit` (Session 5 peer) + 6 story skills by intent | **Seven** skills (no `orchestrate-design`); no epic/architecture authorship; assigned-story guide: `docs/guides/assigned-story-workflow.md` |
| Observer | `observer` | `/summarize`, `/meeting`, `/handoff` | `nwob-docs/observations/`, `nwob-docs/meetings/` |

Override SDD defaults with `.nwob/artifact-paths.json` (`spec` required; `stories_dir` optional) — run `nwob config paths --show` after mapping.

Inspect a bundle before installing:

```bash
nwob bundle info product-owner
nwob bundle list
```

## Project Layout After Init

```text
your-project/
├── setup-nwob.sh                  # Bootstrap helper (copied at init)
├── .gitignore                     # Managed block — see Git policy below
├── nwob-references/               # Rules (gitignored; local copy)
│   └── rules/
├── nwob-docs/                     # Engagement artifacts (default init only)
│   └── ...
├── .nwob/                         # Manifest, templates, artifact-paths.json (gitignored)
├── agents/                        # Persona orchestrators (gitignored)
├── AGENTS.md                      # NWOB overlay (gitignored)
├── .cursor/                       # Skills, rules, commands (gitignored except constitution-custom.mdc)
│   ├── rules/
│   │   ├── constitution-core.mdc
│   │   ├── constitution-custom.mdc  # ONLY file under .cursor/ intended for git commit
│   │   └── nwob-product-owner.mdc
│   ├── skills/
│   └── commands/
└── ...
```

**Git policy:** Init upserts a managed `.gitignore` block ignoring `.cursor/**`, `.nwob/`, `nwob-references/`, `AGENTS.md`, and `/agents/`, with exception `!.cursor/rules/constitution-custom.mdc`.

**Default init** scaffolds the `nwob-docs/` tree (including `nwob-docs/sdd/stories/`) when not using `--no-scaffold-docs`. **With `--no-scaffold-docs`**, edit `.nwob/artifact-paths.json` (already written on init) to map existing paths.

Artifact content is created when you run the relevant command at **resolved paths** (e.g. `/problem` scaffolds `spec` from `.nwob/templates/spec-template.md`).

`nwob doctor` auto-repairs the managed `.gitignore` block, `constitution-core.mdc`, and `constitution-custom.mdc` when absent. In default scaffold mode it also expects `nwob-docs/sdd/`. Removes legacy managed `nwob-core.mdc` and `nwob-default.mdc` when present. Does not create `repositories/`.

### Service clones (multi-repo)

Clone service codebases under `repositories/{service-name}/` when needed (prompter-managed; **not** created by init or doctor):

```bash
git clone <remote-url> repositories/order-service
```

Register each service in `nwob-docs/architecture/service-map.md`. `/contracts` writes OpenAPI to `repositories/{service-name}/src/main/resources/swagger/`.

## Add and Switch Personas

Personas are **registered additively** in `.nwob/manifest.json`, but only **one persona's cursor assets** are active at a time.

```bash
nwob persona add lead-builder      # Register persona (no cursor install if another is active)
nwob persona switch lead-builder   # Swap .cursor/skills and .cursor/rules
nwob persona list
```

**Swap behavior:** `nwob persona switch` removes the prior persona's `.cursor/skills`, persona/boundary `.mdc` files, `agents/<old>.md`, and slash commands; then installs the target persona bundle.

In Cursor chat:

```
/persona lead-builder
/switch product-owner
```

Both invoke the `switch-persona` core skill (`.cursor/skills/switch-persona/SKILL.md`).

## Command → Artifact Map

| Command / intent | Output |
|------------------|--------|
| `/problem` | `nwob-docs/sdd/epic-spec.md`, `nwob-docs/presentations/intake-record.md` |
| `/ideate` | `nwob-docs/sdd/epic-spec.md` (Solutions) |
| `/roadmap` | `nwob-docs/sdd/epic-spec.md` (Themes) |
| `/features` | `nwob-docs/sdd/epic-spec.md` (backlog index) + `{stories_dir}/{STORY_ID}/story-spec.md` |
| `/backlog` | `nwob-docs/sdd/epic-spec.md` (groomed index) + per-story `story-spec.md` |
| `/value` | `nwob-docs/process/` value stream map |
| `/intake` | `nwob-docs/presentations/intake-record.md` |
| `/collect`, `/present`, `/enrich`, `/deck` | `nwob-docs/presentations/` deck artifacts |
| `/orchestrate-design` (SA **or** LB) | `design-package.md`; dual-persist `architecture.md` ↔ `sdd/masterplan.md` and flat `sdd/components/{component-name}-plan.md`; may co-author `story-spec.md` annex + `story-tasks.md` |
| `co-design-solution` (intent; Builder/PB) | Technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` + `story-tasks.md` (default `nwob-docs/sdd/stories/`); may co-author product fields when blocking (flag material AC for PO). Pod Builder **MUST NOT** author architecture/masterplan/component plans |
| `trigger-ai-build` (intent) | Implementation per `story-tasks.md`; Cursor execution plan in `~/.cursor/plans/` only (not SDD) |
| `/audit` (SA **or** LB **or** PB peer) | `nwob-docs/observations/audit-report.md` |
| `/c4` | Dual-persist `architecture.md` ↔ `sdd/masterplan.md` (C4 Context + Container) |
| `/pattern` | `nwob-docs/architecture/adr/ADR-NNN-architectural-pattern-selection.md` (SA **or** LB) |
| `/platform` | `nwob-docs/architecture/network.md`, platform sections in `architecture.md` / `masterplan.md` |
| `/services` | Dual-persist architecture/masterplan (Data Flow, Data Models, State Machine, design-time DB Maintenance), `service-map.md`, flat `sdd/components/{component-name}-plan.md` |
| `/contracts` | OpenAPI at `repositories/{service-name}/src/main/resources/swagger/` (SA **or** LB); fitness + catalogue in `service-map.md` |
| `/ops` | SLOs, observability, runtime DB Maintenance & Operation in `architecture.md` / `masterplan.md` / `network.md` / owning `sdd/components/` twin |
| `/adr` | `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md` (SA **or** LB) |
| `/arc` | ARC record under `nwob-docs/architecture/` |
| `/architecture` | Full architecture package with dual-persist masterplan + `sdd/components/` |
| `/summarize` | `nwob-docs/observations/` chat summary |
| `/meeting` | `nwob-docs/observations/` meeting summary |
| `/handoff` | `nwob-docs/observations/mentor-handoff.md` |

## Verify Installation

```bash
nwob doctor
```

Checks `nwob-references/`, scaffold mode (`nwob-docs/sdd/` or `.nwob/artifact-paths.json`), `.cursor/rules/constitution-core.mdc`, catalog `project_rules` (`constitution-custom.mdc`), active persona skills, and Cursor commands.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `NWOB_PYTHON` | Python 3.11+ interpreter for `setup-nwob.sh` venv creation (auto-detected when unset) |
| `NWOB_SKILLS_ROOT` | Path to `nwob-agent-skills` repo (used by shell script and CLI when not installed as package) |
| `NWOB_CACHE_DIR` | Clone cache for `setup-nwob.sh` Git URL sources (default `~/.cache/nwob-agent-skills`) |
| `NWOB_SKILLS_REF` | Branch or tag to check out when `setup-nwob.sh` clones a Git URL (default: remote `HEAD`) |
| `NWOB_SCAFFOLD_DOCS` | Set to `1` in `setup-nwob.sh` to scaffold `nwob-docs/` (greenfield opt-out from default) |
| `NWOB_NO_SCAFFOLD_DOCS` | Set to `1` for `nwob-init.sh` / `nwob init` (same as `--no-scaffold-docs`) |

## SDD Lifecycle

```text
/problem → /ideate → /roadmap → /features → /orchestrate-design (SA|LB) → co-design-solution → validate-design-package → trigger-ai-build → raise-merge-request → /audit
   epic-spec.md    epic-spec.md   epic-spec.md    epic-spec.md (index)      design-package + dual arch/masterplan/flat component plans   story-spec annex + story-tasks   gate   code + Cursor plan   MR draft   peer audit
                                                 + story-spec.md (per story)
# Pod Builder Session 1 skips /orchestrate-design (prerequisite: SA/LB already produced epic-spec + masterplan/architecture + component plans)
# Session 1 for PB: co-design-solution → validate-design-package
```

Constitution and SDD gates apply throughout. See [AGENTS.md](../AGENTS.md) and [constitution-core.mdc](../rules/constitution-core.mdc).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Package 'nwob-cli' requires a different Python: 3.9.x not in '>=3.11'` | Install Python 3.11+ (`brew install python@3.12` on macOS), remove stale venv (`rm -rf /path/to/nwob-agent-skills/.venv`), re-run `source setup-nwob.sh ...`, or set `NWOB_PYTHON=/path/to/python3.12` |
| `nwob: command not found` (including `nwob doctor`, `nwob --version`) | Init can succeed via `python -m nwob_cli` without installing `nwob` on PATH. See [README — CLI not on PATH after init?](../README.md#cli-not-on-path-after-init). Quick fix: `pip install -e .` in nwob clone, or `PYTHONPATH=$NWOB_SKILLS_ROOT/src python3 -m nwob_cli <command>` |
| Missing commands in Cursor | `nwob persona switch <id>` or `nwob init --force` |
| Skill links to rules break | Ensure `nwob-references/rules/` at project root (not under `.cursor/`); re-run `nwob init --force` if legacy `references/` |
| Active persona not installed | `nwob persona add <id>` then `nwob persona switch <id>` |
| Docs live outside `nwob-docs/` | `nwob init --no-scaffold-docs`; edit `.nwob/artifact-paths.json` (written on init); `nwob config paths --validate` |
| Legacy `.nwob/skills/` layout | Re-init or `nwob persona switch <id>` to migrate to `.cursor/skills/` |

## Syncing Changes

When modifying skills or bundles in this repository, see [README — Syncing agent and skill changes to bundles](../README.md#syncing-agent-and-skill-changes-to-bundles).
