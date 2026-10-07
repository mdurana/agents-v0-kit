---
name: switch-persona
description: >-
  Switches the active NWOB persona within an initialized project. Use when the
  user invokes /persona or /switch, or asks to change agent role mid-engagement.
---

# Switch Persona

## Overview

Changes the active persona for the current NWOB-initialized project. **Swap model:** switching removes the prior persona's `.cursor/skills`, `.cursor/rules` persona files, and `agents/<persona>.md`, then installs the target persona's assets. Shared `references/`, `constitution-core.mdc`, and `constitution-custom.mdc` persist.

**MUST NOT** create, edit, or delete project SDD artifacts (`epic-spec.md`, `story-spec.md`, `story-tasks.md`, component `*-plan.md`, dual-persist architecture/masterplan) during a persona switch. Those files are owned by skills only — see write ACL in `constitution-core.mdc` and [sdlc-role-matrix.md](../../../references/rules/sdlc-role-matrix.md).

## When to Use

- User invokes `/persona` or `/switch` with a target persona.
- User asks to work as Product Owner, Lead Builder, Solution Architect, etc.
- Engagement phase changes (e.g., PO → Lead Builder after `epic-spec.md` backlog index is sprint-ready).

## Process

1. **Read state:**
   - `.nwob/active-persona.json` — current persona
   - `.nwob/manifest.json` — installed personas and managed files
2. **Resolve target persona** from user input. Valid ids:
   `product-owner`, `solution-architect`, `lead-builder`, `builder`, `pod-builder`, `observer`
3. **If target not installed:**
   - Instruct: `nwob persona add <persona>` then `nwob persona switch <persona>`
   - If `nwob` CLI is available, offer to run it.
   - Stop until persona is registered.
4. **Swap persona assets** (preferred — via CLI):
   ```bash
   nwob persona switch <target-id>
   ```
   This removes prior persona `.cursor/skills`, `.cursor/rules` persona/boundary `.mdc` files, and `agents/<old>.md`, then installs the target persona bundle. It does **not** touch SDD content under resolved `spec` / `stories_dir`. Cursor assets refresh; existing SDD files (`epic-spec.md`, per-story `story-spec.md` / `story-tasks.md`, etc.) are never overwritten — missing files may be created from templates only when an owning skill runs.
5. **Manual fallback** (no CLI): disable current persona `.mdc` in Cursor Rules UI; enable target `nwob-<persona>.mdc`; copy target persona skills per [README Cursor setup](../../../README.md#cursor-setup). Do not edit SDD artifacts while switching.
6. **Refresh project `AGENTS.md`** active-persona block (between `<!-- nwob:active-persona:start -->` and `<!-- nwob:active-persona:end -->`):
   - Active persona name and id
   - Link to `agents/<persona>.md` and `.cursor/rules/nwob-<persona>.mdc`
   - Available slash commands for installed personas
7. **Report context:**
   - List commands for the new active persona
   - SDD artifact status: `epic-spec.md`, per-story `story-spec.md` / `story-tasks.md` (exists / missing)
   - Suggested next command for typical lifecycle phase

## Persona Command Reference

| Persona | Commands |
|---------|----------|
| product-owner | `/problem`, `/ideate`, `/roadmap`, `/features`, `/backlog`, `/value`, `/intake`, `/collect`, `/present`, `/enrich`, `/deck` |
| solution-architect | `/define`, `/problem`, `/ideate`, `/roadmap`, `/features`, `/intake`, `/c4`, `/pattern`, `/platform`, `/services`, `/contracts`, `/ops`, `/adr`, `/arc`, `/architecture`, `/orchestrate-design`, `/audit` |
| lead-builder | Same SA/LB command set as solution-architect |
| builder | `/audit` (+ co-design, validate, review by intent) |
| pod-builder | `/audit` (+ co-design, validate, review, build by intent) |
| observer | `/summarize`, `/meeting`, `/handoff` |

## Constitution Compliance

**Mandatory:** After switch, all skill invocations must load from `.cursor/skills/` and respect `.cursor/rules/constitution-core.mdc` (and `.cursor/rules/constitution-custom.mdc` for stack/lifecycle overrides).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Switching persona keeps old skills installed" | Swap model removes prior persona cursor assets to prevent role collision. |
| "I can adopt the persona without updating files" | Without swap, PO and Builder boundaries conflict in `.cursor/`. |
| "Switch will reset our authored SDD" | Persona switch never overwrites existing SDD content. |
| "I'll fix epic-spec / annex while switching" | Switch only swaps `.cursor/` assets. SDD writes require owning skills. |

## Red Flags

- Active persona set to an id not in `manifest.json` installed personas.
- Multiple persona `.mdc` files with `alwaysApply: true`.
- Agent continues using skills from the previous persona without explicit user direction.
- Agent edits SDD artifacts during or as a side effect of `/persona` / `/switch`.

## Verification

- [ ] `active-persona.json` updated with target id and timestamp?
- [ ] Target persona listed in `manifest.json` installed personas?
- [ ] Prior persona skills removed from `.cursor/skills/`?
- [ ] Target persona skills and `.mdc` rules installed?
- [ ] AGENTS.md active-persona block refreshed?
- [ ] User informed of available commands and SDD artifact status?
- [ ] No SDD artifact files created or modified by the switch?
