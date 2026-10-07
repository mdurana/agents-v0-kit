---
name: validate-design-package
description: >-
  Checks that the design package is complete, constitution-compliant, and ready
  for AI build. Use when orchestrate-design has produced a design package draft
  and co-design-solution has written the annex and story-tasks.md.
---

# Validate the design package

Independently check that the design package from SA/LB `/orchestrate-design` and the technical annex plus `story-tasks.md` from `co-design-solution` are complete, constitution-compliant, and ready for Builder `trigger-ai-build`. Sign-off is required before the build starts.

Boundaries: [lead-builder-skill-boundaries.md](../../../references/rules/lead-builder-skill-boundaries.md). Pod Builder mode: [pod-builder-skill-boundaries.md](../../../references/rules/pod-builder-skill-boundaries.md).

This skill does not produce architecture or story bodies. SA **or** LB produce architecture dual-persist twins, flat component plans, ADRs, and OpenAPI; Builder / Pod Builder `co-design-solution` produces annex in `story-spec.md` and `story-tasks.md`. This skill only validates. A user-orchestrated `doubt-driven-development` checkpoint may run before sign-off. It does not replace this gate.

**Twin acceptance (system SoT only):** For system architecture, presence of **either** twin satisfies the check (`architecture.md` **or** `sdd/masterplan.md`). Prefer both when writers have dual-persisted; do not fail solely because one twin name is missing if the other exists with the same body. Component plans are single flat files: `nwob-docs/sdd/components/{component-name}-plan.md`.

**Pod Builder mode:** Validate the story annex in `story-spec.md` and `story-tasks.md` against **existing** architecture (read either system twin; legacy nested `sdd/components/` and `architecture/components/` is read-only brownfield fallback). **MUST NOT** produce missing architecture. Route produce-architecture gaps to SA **or** LB `/orchestrate-design` or `/c4` … `/ops` / `/architecture`.

## When to use

- SA/LB `/orchestrate-design` has produced a design package draft.
- In-scope `story-tasks.md` files exist and are traceable to the `epic-spec.md` backlog index.
- The user requests design-package review or build-readiness sign-off.
- Pod Builder Session 1 story-level gate after `co-design-solution`.

In-scope stories must have annex in `story-spec.md` and `story-tasks.md` under `stories_dir` before sign-off. `trigger-ai-build` and Cursor execution plans must not start until this validation passes.

## Workflow

### Step 1: Confirm SDD

Confirm that `epic-spec.md` exists with a backlog index covering selected stories.

Confirm that each selected story has `{stories_dir}/{STORY_ID}/story-spec.md` with Gherkin AC and `{stories_dir}/{STORY_ID}/story-tasks.md` with full bodies from `co-design-solution`.

If an artifact is missing, stop. Route to `/orchestrate-design` (SA **or** LB) for strategy or architecture gaps; to `co-design-solution` for annex and `story-tasks.md` gaps; or to the matching Product Owner / SA/LB author skill.

### Step 2: Resolve effective constraints

Per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints), check the user prompt, then SDD artifacts, then other sources.

Record effective stack and effective data lifecycle. If sources conflict, flag them to the user. Do not pick one yourself.

### Step 3: Check design package completeness

Confirm architecture artifacts are present as scope requires (accept either system twin):

1. ADRs for significant decisions.
2. Diagrams in `nwob-docs/architecture/architecture.md` **or** `nwob-docs/sdd/masterplan.md` for non-trivial scope.
3. For each in-scope container: `nwob-docs/sdd/components/{component-name}-plan.md` (linked from `service-map.md`; complements system SoT). Brownfield: legacy nested paths may satisfy as **read-only** evidence — do not require or author new files there.
4. `nwob-docs/architecture/service-map.md` with rows for in-scope services (Component plan column when present — prefer flat `sdd/components/*-plan.md` links).
5. OpenAPI 3.0 files at `repositories/{service-name}/src/main/resources/swagger/` where APIs are in scope.
6. Initialized submodule paths for `Status: active` services in service-map.

Confirm the artifacts are present and implementable. This skill **does not** author architecture or story bodies — route gaps to SA/LB `/orchestrate-design` or architecture commands, or to `co-design-solution` for annex/tasks. In Pod Builder mode, route all produce-architecture work to SA/LB.

### Step 4: Check `story-tasks.md` bodies

For each in-scope story, confirm `{stories_dir}/{STORY_ID}/story-tasks.md` items are actionable for AI-assisted implementation. Scope and acceptance signal are clear.

Tasks are ordered and traceable to stories in the `epic-spec.md` backlog index. Dependencies match chronological story sequencing. Use `story-tasks.md` for implementable anatomy; use `epic-spec.md` index for cross-story order.

### Step 5: Check story annex in story-spec.md

For each in-scope story in the backlog index:

1. Confirm `{stories_dir}/{STORY_ID}/story-spec.md` includes a completed **Technical design annex** (not a separate `story-plan.md`). Default `stories_dir` is `nwob-docs/sdd/stories/`.
2. Confirm the baseline Overall row is not Not started without grep evidence from `repositories/{service-name}/`.
3. Confirm every annex subtask row has a `story-tasks.md` ID that `co-design-solution` copied unchanged into `story-tasks.md`.

If a row has no ID, the story is not buildable. Return to `co-design-solution` to fill the annex table and write `story-tasks.md`.

If annex Gherkin is tighter than product AC in `story-spec.md`, require product field update (PO `/backlog` or documented SA/LB/PB co-author with PO flag) before sign-off. Product Gherkin in `story-spec.md` wins until then.

Do not generate a Cursor execution plan under `~/.cursor/plans/` until this skill signs off.

### Step 6: Check constitution and iteration integrity

Confirm mandatory constitution rules appear in the design artifacts: stateless K8s, RFC 7807, coverage expectations.

Confirm effective stack and data lifecycle are documented in sources or ADRs, not assumed from defaults when overrides are active.

Confirm story sequencing, dependencies, and iteration scope are coherent.

### Step 7: Record the outcome

If the package is ready, persist design-approved for build to disk. Use one of:

1. The **Sign-off** section in the **Technical design annex** of `{stories_dir}/{STORY_ID}/story-spec.md` for each in-scope story.
2. `{stories_dir}/{STORY_ID}-design-validation.md` when sign-off is kept separate from the annex.

Record date, verdict (`Approved for build` or gap list), and validator notes. Do not leave sign-off only in chat.

Handoff to Builder `trigger-ai-build` (Session 2 plan mode).

If gaps remain, return to SA/LB `/orchestrate-design` for strategy or architecture gaps, or to `co-design-solution` for annex and `story-tasks.md` gaps, with a documented list. Pod Builder: never fill architecture gaps in this skill — route to SA/LB.

## Constitution compliance

Mandatory: SDD pre-gate (`epic-spec.md` with backlog index) plus in-scope `story-spec.md` + `story-tasks.md` (build gate). Story anatomy and Gherkin AC. Design package reflects mandatory rules before build handoff. System SoT twin acceptance for dual-persist paths.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Validation must confirm effective constraints are documented.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| `orchestrate-design` already validated everything | SA/LB orchestrates. `co-design-solution` writes annex + `story-tasks.md`. This skill independently signs off before build. |
| We can validate during build | Gaps found during build cause rework. |
| Missing ADRs are fine for this scope | Apply scope-appropriate checks. Document what was validated and what the user waived. |
| I will produce the missing contracts / architecture here | Route gaps to SA/LB `/orchestrate-design` and architecture commands. This skill validates. It does not produce. |
| Only `architecture.md` counts — fail if `masterplan.md` missing | Accept either system twin; writers dual-persist, validators accept either name. |
| Doubt-driven review replaces this sign-off | User-orchestrated doubt is optional. This gate stays mandatory. |
| `epic-tasks.md` index is enough | Retired — per-story `story-tasks.md` is required. Stop and route to `co-design-solution`. |
| Annex Overall is Not started. We will grep during build | Baseline audit requires grep evidence before sign-off. |
| Generate the Cursor plan now so we can start | Execution plans wait until this skill signs off. |
| Subtask rows without a `story-tasks.md` ID are fine | Return to Builder `co-design-solution` to fill the annex and write `story-tasks.md`. |
| Require separate `story-plan.md` | Retired — annex must live in `story-spec.md`. |

## Red flags

- Validation skipped because `orchestrate-design` already checked.
- `story-tasks.md` items not traceable to `epic-spec.md` backlog index stories.
- Full task bodies living only in retired epic-level indexes with no per-story `story-tasks.md`.
- Design package uses constitution defaults when sources specify overrides.
- Build started without this sign-off when this skill applies.
- Cursor execution plan generated before design-approved for build.
- In-scope story missing annex in `story-spec.md`, or `story-tasks.md` ID column still blank.
- Architecture produced inside this skill (especially under Pod Builder).
- Failed validation solely because one dual-persist system twin name was missing when the other exists.
- New `epic-tasks.md`, `epic-plan.md`, or `story-plan.md` expected or authored.

## Verification

- [ ] `epic-spec.md` with backlog index reviewed; in-scope `story-spec.md` + `story-tasks.md` present?
- [ ] Design package completeness validated for scope: ADRs, diagrams (either system twin), contracts, flat component plans when containers are in scope?
- [ ] Each in-scope `story-tasks.md` actionable, ordered, and traceable to backlog index?
- [ ] Each in-scope story has annex in `story-spec.md` with grep evidence and a `story-tasks.md` ID per subtask row matching bodies?
- [ ] No Cursor execution plan generated before this sign-off?
- [ ] Effective stack and data lifecycle documented?
- [ ] Sign-off persisted to annex Sign-off section or `{STORY_ID}-design-validation.md`?
- [ ] Design-approved for build, or gaps documented for SA/LB `/orchestrate-design` or `co-design-solution` (architecture produce → SA/LB only)?
