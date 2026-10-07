---
name: co-design-solution
description: >-
  Writes the technical annex into story-spec.md and full story-tasks.md during
  design. Use when a design workshop is active, orchestrate-design has produced
  strategy and architecture, and technical co-design plus task bodies are needed
  before the build gate.
---

# Write the story technical annex and story-tasks.md

Write the **Technical design annex** inside `{stories_dir}/{STORY_ID}/story-spec.md` and full bodies at `{stories_dir}/{STORY_ID}/story-tasks.md`. This skill is **primary** for the annex and **full task bodies** (Lead Builder / Solution Architect may co-author via `/orchestrate-design`). SA/LB `/orchestrate-design` owns strategy and dual-persist architecture (system SoT only). `validate-design-package` owns sign-off.

Boundaries: [builder-skill-boundaries.md](../../../references/rules/builder-skill-boundaries.md). Pod Builder mode: [pod-builder-skill-boundaries.md](../../../references/rules/pod-builder-skill-boundaries.md). Task patterns: [task-breakdown-patterns.md](../../../references/rules/task-breakdown-patterns.md).

Product Owner, Solution Architect, or Lead Builder owns `epic-spec.md` (backlog index + HL US/TS). `story-spec.md` product fields are PO/SA/LB-primary; this skill **fills the technical annex sections** in the same file and may **co-author** product fields when annex work is blocked (Gherkin + six fields; flag material AC changes for PO).

**Must NOT author** `architecture.md`, `sdd/masterplan.md`, flat `sdd/components/{component-name}-plan.md`, ADR bodies, or OpenAPI — those belong to SA **or** LB (co-equal). When Pod Builder is active, this skill writes only the annex in `story-spec.md` and `story-tasks.md`; route architecture gaps to SA/LB `/orchestrate-design` or architecture commands. **Do not** generate `story-plan.md`, `epic-plan.md`, or `epic-tasks.md`.

Frontend implementation patterns live in Builder `trigger-ai-build` via [build-execution-patterns.md](../../../references/rules/build-execution-patterns.md). Co-design shapes test and UI strategy only.

## When to use

- A design workshop is active and SA/LB `/orchestrate-design` is in progress or has produced strategy and architecture.
- Selected stories need technical feasibility review before architecture is finalized.
- A story indexed in `epic-spec.md` needs a persisted technical annex and `story-tasks.md` before build.
- Pod Builder Session 1 — story-level annex and tasks (no `/orchestrate-design`).

## Workflow

### Step 1: Confirm SDD

Confirm that `epic-spec.md` exists with a backlog index for selected stories.

Confirm that each selected story has `{stories_dir}/{STORY_ID}/story-spec.md` with constitution-compliant Gherkin AC in product fields.

If `epic-spec.md` is missing, stop. Route to the matching Product Owner skill (or SA/LB `/define` / `/features`).

If a `story-spec.md` is missing or lacks Gherkin AC, prefer PO/SA/LB `/features` or PO `/backlog`. When design is blocked, co-author product fields in `story-spec.md` (Gherkin + six story fields) and **flag material AC changes for PO**.

### Step 2: Resolve effective constraints

Per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints), check the user prompt, then `epic-spec.md`, `story-spec.md`, and existing `story-tasks.md` when present, then other sources. Read architecture twins (`architecture.md` or `sdd/masterplan.md`; flat `sdd/components/*-plan.md` or legacy nested paths read-only) for constraints — do not author them.

Record effective stack and effective data lifecycle. If sources conflict, flag them to the user. Do not pick one yourself.

### Step 3: Review selected scope

Review selected epics and stories for technical feasibility and dependency risks.

Map stories to likely service boundaries, integration points, and test surfaces.

Name implementation risks, unknowns, and decisions that need SA/LB input (`/pattern`, `/adr`) or ADRs.

### Step 4: Contribute implementation-level design

Collaborate on module boundaries, API sketches, data flow, and test strategy.

Reference SA/LB artifacts (system SoT, flat component plans, ADRs, OpenAPI). **Do not** create or update `architecture.md`, `masterplan.md`, `sdd/components/**`, ADR bodies, or OpenAPI. If complementary system or container detail is missing, **route to SA or LB** `/orchestrate-design`, `/c4` … `/ops`, `/architecture`, `/adr`, or `/contracts`.

Do not own the strategy plan or SA/LB skill coordination. Those belong to `/orchestrate-design` (SA **or** LB).

### Step 5: Write the technical annex in story-spec.md

For each in-scope story, persist co-design under **`## Technical design annex`** (and related sections) in `{stories_dir}/{STORY_ID}/story-spec.md`. Do not leave it in chat. Do **not** create a separate `story-plan.md`.

1. Resolve `stories_dir` per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md). Default is `nwob-docs/sdd/stories/`.
2. Lazy-create `{stories_dir}/{STORY_ID}/` if missing. Ensure `story-spec.md` exists from [templates/sdd/story-spec-template.md](../../../templates/sdd/story-spec-template.md).
3. Grep `repositories/{service-name}/`. Record what exists versus what this story owns in the annex baseline audit. Do not guess. `validate-design-package` fails if Overall is Not started with no grep evidence.
4. Fill scope boundary, prerequisites, reusable artifacts, mocking, and the subtasks table in the annex. Fill every column: Task ID, Description, Artifacts, Category, and `story-tasks.md` ID.
5. Choose each `story-tasks.md` ID for this story (example: `S16-T-01`). Use that same ID unchanged in `story-tasks.md` in Step 6. Do not invent a second ID later.
6. Apply `.cursor/rules/constitution-custom.mdc` when that file is present.

Annex section patterns (baseline audit, subtasks table, sign-off) follow the former `story-plan-template.md` shape embedded in `story-spec-template.md`.

Prefer restating product AC from `story-spec.md` in the annex. If co-design makes an acceptance criterion more precise, update product Gherkin in `story-spec.md` and **flag material AC changes for PO**, or route to Product Owner `/backlog`.

### Step 6: Write `story-tasks.md`

For each in-scope story, author full task bodies at `{stories_dir}/{STORY_ID}/story-tasks.md`.

1. Copy [templates/sdd/story-tasks-template.md](../../../templates/sdd/story-tasks-template.md) when the file is missing.
2. Apply [task-breakdown-patterns.md](../../../references/rules/task-breakdown-patterns.md). One item per annex subtask row. Copy the annex `story-tasks.md` ID unchanged.
3. Each item MUST include: ID, story trace, description, acceptance signal, verify, dependencies, files, and scope (XS–XL; prefer XS–S).
4. Prefer vertical slices. Order respects `epic-spec.md` backlog index chronology and technical dependencies.

Do not load `references/agent-skills-main/skills/planning-and-task-breakdown` when the embed applies.

### Step 7: Hand off

Deliver updated `story-spec.md` (with annex) and `story-tasks.md` files, plus any remaining feasibility notes, to SA/LB `/orchestrate-design` when system architecture gaps remain, or directly to `validate-design-package` when the design package is complete. Pod Builder Session 1: hand off to `validate-design-package` — do not invoke `/orchestrate-design`.

Formal sign-off is `validate-design-package`. Do not generate a Cursor execution plan.

## Constitution compliance

Mandatory: SDD pre-gate (`epic-spec.md`, `story-spec.md` with product anatomy). Story anatomy and Gherkin AC in `story-spec.md`. Co-design input must match mandatory constitution rules: stateless K8s, RFC 7807, coverage expectations. Full task bodies in `story-tasks.md` before build handoff (build gate: in-scope `story-spec.md` + `story-tasks.md`).

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Co-design input must show effective constraints, not constitution defaults, when overrides are active.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| I will validate the design package here too | Formal sign-off is `validate-design-package`. Co-design produces the annex and `story-tasks.md`. |
| I can orchestrate SA skills directly | SA/LB skill coordination is `/orchestrate-design` (SA **or** LB). Pod Builder must not invoke it. |
| `story-spec.md` product fields are enough. Skip technical review | Builder co-design catches implementation risks before AI build. |
| Create a separate `story-spec.md` (technical annex) | Retired — annex lives **in** `story-spec.md` only. |
| Leave `story-tasks.md` ID blank for orchestrate-design | Fill every subtask row, including `story-tasks.md` ID, when you write the annex. |
| Chat notes are enough. Skip the annex | Persist annex sections in `{stories_dir}/{STORY_ID}/story-spec.md` and `story-tasks.md` from the templates. |
| I will tighten Gherkin only in the annex | Update product Gherkin in `story-spec.md` and flag for PO, or route to `/backlog`. |
| Use reference `frontend-ui-engineering` during co-design | UI patterns are embedded in Builder `trigger-ai-build`. Co-design contributes test and UI strategy only. |
| I will author architecture / masterplan / components / ADR / OpenAPI here | Route to SA **or** LB. This skill writes annex + `story-tasks.md` (+ product fields in `story-spec.md` if blocking) only. |

## Red flags

- Co-design started without `epic-spec.md` or selected `story-spec.md` with Gherkin AC.
- Builder or Pod Builder owning the strategy plan or SA/LB skill coordination.
- Architecture, masterplan, flat component plans, ADR, or OpenAPI authored from this skill.
- New `story-spec.md` (technical annex), `epic-spec.md` backlog index, or `story-tasks.md` generated.
- Co-design left only in chat, with no annex in `story-spec.md` or `story-tasks.md` under `stories_dir/{STORY_ID}/`.
- Material AC changes in `story-spec.md` without flagging PO.
- Subtask `story-tasks.md` ID column left blank.
- Annex written without matching `story-tasks.md` items, or IDs that do not match the annex.

## Verification

- [ ] `epic-spec.md` and selected `story-spec.md` files exist with Gherkin AC?
- [ ] Effective stack and data lifecycle resolved?
- [ ] Technical feasibility and implementation-level design input documented?
- [ ] Technical annex written in `{stories_dir}/{STORY_ID}/story-spec.md` (not a separate `story-spec.md` (technical annex))?
- [ ] Phase 0 grep of `repositories/{service-name}/` recorded in the baseline audit?
- [ ] Subtasks table present with every column filled, including `story-tasks.md` ID on each row?
- [ ] `{stories_dir}/{STORY_ID}/story-tasks.md` has one item per annex subtask, same IDs, with story trace, verify, files, and scope?
- [ ] No architecture / masterplan / component plans / ADR / OpenAPI authorship from this skill?
- [ ] Material `story-spec.md` AC changes flagged for PO?
- [ ] Formal sign-off deferred to `validate-design-package`?
