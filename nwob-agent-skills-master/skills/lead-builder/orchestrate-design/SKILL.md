---
name: orchestrate-design
description: >-
  Turns selected backlog items into a strategy plan, coordinates architecture
  derived from epic-spec, and consolidates the design package before build. Use
  when the user invokes /orchestrate-design, epics or stories are selected for
  an iteration, or design must be finished before AI-assisted implementation.
---

# Orchestrate design

Command: `/orchestrate-design` (available on **Solution Architect** and **Lead Builder** — co-equal).

Turn selected backlog items into a strategy plan and design package. Product Owner, Solution Architect, or Lead Builder own `epic-spec.md` (backlog index + HL US/TS) via `/define`, `/features`, or PO author skills. Builder `co-design-solution` is primary for the **technical annex in `story-spec.md`** and `{stories_dir}/{STORY_ID}/story-tasks.md` bodies; SA/LB may **co-author** annex, `story-tasks.md`, and product fields in `story-spec.md` from this skill (and nested `co-design-solution`) per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md).

SA and LB are **co-equal** for architecture: **dual-persist only** `architecture.md` ↔ `sdd/masterplan.md` (derived from `epic-spec.md`); flat per-container `nwob-docs/sdd/components/{component-name}-plan.md` (from [templates/sa/component-plan-template.md](../../../templates/sa/component-plan-template.md)). Both may author ADR bodies and OpenAPI. **Pod Builder MUST NOT** invoke this skill or author architecture/masterplan/components/ADRs/OpenAPI. **Do not** generate `epic-tasks.md`, `epic-plan.md`, `story-plan.md`, nested `sdd/components/{id}/`, or `component-spec.md` twins.

Boundaries: [lead-builder-skill-boundaries.md](../../../references/rules/lead-builder-skill-boundaries.md).

## When to use

- The user invokes `/orchestrate-design`.
- Selected epics and stories need strategy, sequencing, and architecture alignment before build.
- Architecture must be finished before AI-assisted implementation.
- Strategy and the design package must exist before (or alongside) Builder `co-design-solution` writing the annex and `story-tasks.md`.
- In-scope `story-tasks.md` files need confirmation against the design package.

## Workflow

### Step 1: Confirm SDD

Confirm that `nwob-docs/sdd/epic-spec.md` exists with a backlog index for selected stories.

Confirm that each selected story has `{stories_dir}/{STORY_ID}/story-spec.md` with constitution-compliant Gherkin AC and all six story fields from Planning and story anatomy in constitution-core (indexed from `epic-spec.md`).

If `epic-spec.md` is missing or has no backlog index for selected stories, stop. Route to the matching Product Owner skill: `business-problem-identification`, `feature-definition`, or `backlog-management-and-refinement` — or SA/LB `/define` / `/features` when architect-led.

If a selected story lacks `story-spec.md` or Gherkin AC, prefer routing to PO/SA/LB `/features` or PO `/backlog`. When design is blocked and the user accepts co-authoring, create or update `story-spec.md` here (Gherkin + six fields mandatory) and **flag material AC changes for PO**.

### Step 2: Resolve effective constraints

Per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints), check the user prompt, then `epic-spec.md`, and resolved `story-tasks.md` when present, then other sources. Mapping keys are **`spec`** and optional **`stories_dir` only** — no `plan` / `tasks` keys.

Record effective stack and effective data lifecycle. If sources conflict, flag them to the user. Do not pick one yourself.

### Step 3: Analyze scope

Map selected epics and stories to technical boundaries, service boundaries, and integration points.

Identify dependencies between stories. They must match chronological order in the `epic-spec.md` backlog index.

Name risks, unknowns, and decisions that need ADRs or ARC review.

### Step 4: Write the strategy plan

Define sequencing, milestones, and implementation approach for the selected scope.

Reference the `epic-spec.md` backlog index. Do not rewrite PO-owned product content unless the user directs it.

Optional output: `nwob-docs/sdd/design-notes.md` for strategy and sequencing. That file is not a rewrite of `epic-spec.md`.

### Step 5: Coordinate architecture skills (SA or LB) and dual-persist

Invoke SA/LB slash commands per [agents/solution-architect.md](../../../agents/solution-architect.md) and [solution-architect-command-standards.md](../../../references/rules/solution-architect-command-standards.md). SA and LB are co-equal authors — either persona may run the chain. **Initial SDD gate:** `epic-spec.md` only; masterplan and component plans are **derived from** `epic-spec.md`.

| Order | Command | Skill | When |
|-------|---------|-------|------|
| 1 | `/c4` | `architecture-governance` | C4 Context and Container first, technology-agnostic; dual-persist `masterplan.md` |
| 2 | `/pattern` | `architecture-governance` | Pattern-selection ADR with at least 2 options (SA **or** LB may author) |
| 3 | `/platform` | `distributed-systems-architecture` | Platform and MVP, `network.md`. Defaults AWS or EKS |
| 4 | `/services` | `distributed-systems-architecture` | Services, data, integration, resilience; flat `sdd/components/{component-name}-plan.md`. Defaults EDA |
| 5 | `/contracts` | `architecture-delivery-enablement` | Contracts, patterns, fitness functions, catalogue; OpenAPI (SA **or** LB) |
| 6 | `/ops` | `production-operations` | Observability, production readiness |
| Ongoing | | `architecture-governance` | Material ADRs, ARC, drift |

If the SDD tier is met and the request is full design-package scope, prefer `/architecture`. Skip or reorder for a narrow request. One SA/LB command is enough for a narrow request.

**Authoring architecture (SA or LB):**

- `nwob-docs/architecture/architecture.md` ↔ `nwob-docs/sdd/masterplan.md` (same body) using [templates/sa/architecture-outline.md](../../../templates/sa/architecture-outline.md)
- `nwob-docs/sdd/components/{component-name}-plan.md` per in-scope container using [templates/sa/component-plan-template.md](../../../templates/sa/component-plan-template.md)

SA **or** LB **may author** ADR bodies and OpenAPI when design requires. Component plans must complement and reference the system SoT. **MUST NOT** write new files under legacy `nwob-docs/architecture/components/` or nested `sdd/components/{id}/` (read-only brownfield fallback). **Pod Builder MUST NOT** author these artifacts.

**Co-authoring story annex and tasks:** Invoke or perform Builder `co-design-solution` for annex sections in `story-spec.md` and `story-tasks.md` bodies. Lead Builder (or SA) may write annex and `story-tasks.md` directly from this skill when Builder is not a separate persona (or always as co-author). Prefer nested `co-design-solution` for task-body structure.

### Step 6: Produce the design package

Consolidate ADRs, diagrams, `service-map.md`, OpenAPI under `repositories/`, flat component plans, and catalogue entries as they apply.

Store artifacts per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md):

- `nwob-docs/architecture/architecture.md` ↔ `nwob-docs/sdd/masterplan.md` (dual-persist)
- `nwob-docs/sdd/components/{component-name}-plan.md` (one flat file per in-scope container)
- `nwob-docs/architecture/network.md`
- `nwob-docs/architecture/service-map.md` (Component plan column links flat `sdd/components/*-plan.md`)
- `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md`
- `nwob-docs/diagrams/sequences/{service-name}.md`
- OpenAPI: `repositories/{service-name}/src/main/resources/swagger/`

If `repositories/` or `service-map.md` is missing, run `nwob doctor`.

Confirm the package matches effective stack and effective data lifecycle. Readers may use either system twin; writers always dual-persist `architecture.md` ↔ `masterplan.md`.

Confirm each in-scope story has annex content in `story-spec.md` and full bodies in `story-tasks.md` (via `co-design-solution` or co-authored here). Order task work by `epic-spec.md` backlog index chronology.

Do not load `references/agent-skills-main/skills/planning-and-task-breakdown` when the embed applies.

### Step 7: Hand off to the design gate

Handoff package: strategy notes, design package (dual-persist system SoT + flat component plans), and in-scope `story-spec.md` (with annex) / `story-tasks.md` files whose IDs match one to one.

Route to `validate-design-package` before Builder `trigger-ai-build`. Do not start implementation until design sign-off, or until the user records an explicit waiver and its risk.

## Constitution compliance

Mandatory: SDD pre-gate (`epic-spec.md` with backlog index). Story anatomy and Gherkin AC in `story-spec.md`. Build gate: in-scope `story-spec.md` + `story-tasks.md`. Stateless K8s. 100% coverage gates. RFC 7807. Dual-persist **only** architecture ↔ masterplan on every system SoT write.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Design artifacts must show effective constraints, not constitution defaults, when overrides are active.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| We can design as we build | Constitution requires finalized SDD and design before implementation. |
| `epic-spec.md` index is enough. Skip architecture skills | Complex scope needs SA/LB skills for contracts, resilience, and governance. |
| Task bodies can wait until build starts | `trigger-ai-build` needs itemized `story-tasks.md`. |
| Refresh `epic-tasks.md` from here | Retired — do not generate `epic-tasks.md`. Task bodies live only in per-story `story-tasks.md`. |
| Confluence SDD replaces spec and tasks | Repo files under resolved `spec` / `stories_dir` are mandatory. External docs supplement them. |
| Reference `planning-and-task-breakdown` replaces this skill | Task body breakdown is embedded in Builder `co-design-solution`. |
| Skip `validate-design-package`. We already reviewed | Independent design sign-off is required before build. |
| ADRs / OpenAPI are SA-only | SA and LB are co-equal; either may author ADR bodies and OpenAPI. |
| Write nested component-spec twins | Use flat `{component-name}-plan.md` only; legacy nested paths are read-only. |
| Update `architecture.md` without `masterplan.md` | Dual-persist both twins on every write. |
| Pod Builder will run `/orchestrate-design` | `/orchestrate-design` is SA/LB only; Pod Builder starts at `co-design-solution`. |

## Red flags

- Design orchestration started without `epic-spec.md` backlog index.
- Selected stories missing Gherkin AC or the six mandatory story fields.
- Architecture artifacts absent for non-trivial scope.
- `architecture.md` updated without dual `sdd/masterplan.md` (or the reverse).
- New component files under nested `sdd/components/{id}/` or legacy `architecture/components/`.
- `epic-tasks.md`, `epic-plan.md`, or `story-plan.md` generated or refreshed.
- Design package uses constitution defaults when sources specify overrides, or the reverse.
- Implementation tasks or file paths written into product fields of `story-spec.md` (annex is the right place).
- Annex subtask IDs that do not match `story-tasks.md` rows.
- Annex or `story-tasks.md` missing for an in-scope story.
- Pod Builder invoked this skill or authored architecture/masterplan/components.

## Verification

- [ ] `nwob-docs/sdd/epic-spec.md` exists with backlog index, and selected stories have Gherkin AC?
- [ ] Effective stack and data lifecycle resolved and documented?
- [ ] Strategy in `design-notes.md` or equivalent, with no unauthorized rewrite of `epic-spec.md` product content?
- [ ] Applicable SA/LB commands invoked, and system SoT dual-persisted (`architecture.md` ↔ `masterplan.md`) as scope requires?
- [ ] In-scope containers have flat `sdd/components/{component-name}-plan.md` linked from `service-map.md` and complementary to system SoT?
- [ ] No new writes under legacy nested components or `architecture/components/`?
- [ ] Each in-scope `story-spec.md` has technical annex; `story-tasks.md` exists; annex IDs match bodies one to one?
- [ ] No `epic-tasks.md` / `epic-plan.md` / `story-plan.md` authored?
- [ ] Handoff routed to `validate-design-package` before Builder `trigger-ai-build`?
