---
name: initialize-project
description: >-
  Verifies NWOB project initialization and guides first-run setup. Use when
  .nwob/ is missing, init failed, or the user asks to initialize NWOB skills
  in the current repository.
---

# Initialize Project

## Overview

Validates or completes NWOB persona-scoped initialization in the current repository. Ensures `.nwob/`, `references/` (installed as `nwob-references/` in target projects), `.cursor/skills/`, `.cursor/rules/`, active persona, and Cursor command stubs are present before SDD workflows run.

NWOB install output is **local and gitignored** except `.cursor/rules/constitution-custom.mdc` (team stack governance).

## When to Use

- `.nwob/` directory is missing or incomplete.
- User requests project initialization or re-initialization.
- Slash command or skill fails because NWOB paths are not found.

## Process

1. **Detect state:** Check for `.nwob/manifest.json`, `.nwob/active-persona.json`, `.cursor/rules/constitution-core.mdc`, `.cursor/rules/constitution-custom.mdc`.
2. **If missing:** Instruct the user to run:
   - `nwob init --here --persona <persona> --integration cursor` (greenfield), or
   - `nwob init --here --persona <persona> --no-scaffold-docs` (brownfield — docs elsewhere), or
   - `./scripts/nwob-init.sh --here --persona <persona>` from the nwob-agent-skills repo.
3. **If partial:** Run `nwob doctor` (if CLI available) and report gaps.
4. **Verify Cursor integration:**
   - `.cursor/skills/` contains core skills (`initialize-project`, `switch-persona`) and active persona skills
   - `.cursor/rules/constitution-core.mdc` (NWOB operational core and cross-platform principles) and `constitution-custom.mdc` (project stack / overrides template) present. One `nwob-<persona>.mdc` for the active persona.
   - `.cursor/commands/` contains stubs for active persona commands plus `persona.md` / `switch.md`
5. **Phase 0 discovery:** Per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md):
   - Read `.nwob/init-options.json` → when `scaffold_nwob_docs` is not `false`, confirm `nwob-docs/` tree exists.
   - When `scaffold_nwob_docs` is `false`, confirm `.nwob/artifact-paths.json` exists (or instruct `nwob config paths --init`). Mapping is SDD-only (`spec` required; `stories_dir` optional). Remove obsolete `plan` / `tasks` keys. Init does not copy `artifact-paths.example.json` into the project.
6. **Gitignore:** Confirm `.gitignore` managed block ignores `.cursor/**` (except `constitution-custom.mdc`), `.nwob/`, `nwob-references/`, `AGENTS.md`, `/agents/`; `nwob init` / `nwob doctor` upsert it.
7. **Report SDD artifact status:** Note whether resolved `spec` and `stories_dir` paths exist (`nwob config paths --show`). Templates scaffold on first command at resolved paths. **Do not** create or overwrite existing `*-spec.md` / component `*-plan.md` during init verification.
8. **Do not scaffold SDD content preemptively** unless the user explicitly requests empty files from templates.

## Constitution Compliance

**Mandatory:** Initialized projects must reference `.cursor/rules/constitution-core.mdc` and `.cursor/rules/constitution-custom.mdc` as the effective constitution in project `AGENTS.md`.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "We can copy skills manually" | Manual copies miss path rewrites, manifest tracking, persona swap, and command routing. |
| "Init should create epic-spec.md now" | Templates are installed at init; artifact content is produced by persona commands at resolved paths. |
| "Our docs live in docs/ — skip nwob-docs" | Use `--no-scaffold-docs` and map `spec` (optionally `stories_dir`) in `.nwob/artifact-paths.json`. |
| "Commit all of .cursor/" | Only `constitution-custom.mdc` is intended for git; rest is local install output. |

## Red Flags

- Skills loaded without `nwob-references/rules/` at project root (links break).
- All persona skills installed simultaneously in `.cursor/skills/` (only one active persona at a time).
- Legacy `.nwob/skills/` layout still in use.
- External docs mode without `.nwob/artifact-paths.json` configured.
- Legacy `references/` folder without `nwob-references/` after re-init.

## Verification

- [ ] `.nwob/manifest.json` exists with installed personas?
- [ ] `nwob-references/rules/` present (when references were installed)?
- [ ] `.nwob/active-persona.json` has valid persona id?
- [ ] `.cursor/rules/constitution-core.mdc`, `constitution-custom.mdc`, and active persona `.mdc` present?
- [ ] Active persona skills present under `.cursor/skills/`?
- [ ] Installed persona commands present under `.cursor/commands/`?
- [ ] Default mode: `nwob-docs/sdd/` exists **or** external mode: `.nwob/artifact-paths.json` configured?
- [ ] `.gitignore` managed block ignores NWOB local output with `constitution-custom.mdc` exception?
- [ ] Project `AGENTS.md` points to `.cursor/rules/constitution-core.mdc` and `constitution-custom.mdc`, plus resolved artifact paths?
