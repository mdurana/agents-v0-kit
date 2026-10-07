---
name: backlog-management-and-refinement
description: >-
  Maintains a healthy, constitution-compliant product backlog with Fibonacci sizing,
  numbered Gherkin acceptance criteria, and Definition of Ready. Resolves parameterized
  Jira export constants and emits tickets.csv for manual import. Use when preparing for
  sprint planning, refining the backlog, or exporting stories to Jira.
---

# Backlog Management and Refinement

Command: `/backlog`

## Overview

Maintains a healthy, actionable product backlog via `nwob-docs/sdd/epic-spec.md` (backlog index) and `{stories_dir}/{STORY_ID}/story-spec.md` per [constitution-core.mdc](../../../rules/constitution-core.mdc). Ensures the backlog is DEEP (Detailed appropriately, Estimated, Emergent, Prioritized).

Layer 1 — Author. Refines `epic-spec.md` backlog index rows and linked `story-spec.md` files; owns Jira export params and `tickets.csv` emit. Does not author presentation content.

**Artifact model:** Each `story-spec.md` is the canonical SDD artifact for that story's anatomy. `epic-spec.md` backlog index is the chronological index and prioritization surface. The "backlog" is the prioritized, groomed **view** of those items ready for sprint commitment. `tickets.csv` is a **derived** Jira import artifact — always regenerated from `story-spec.md` files in `epic-spec.md` backlog index order using engagement-specific params.

**Boundary:** `/backlog` owns **refinement and grooming** of existing items plus **parameterized `tickets.csv` export**. Use `/features` (`feature-definition`) for **initial authoring** of epics, features, and new stories. CSV schema and story formats are defined in [feature-definition](../feature-definition/SKILL.md).

## When to Use

- Preparing for sprint planning, prioritizing bugs vs. features, or cleaning up stale tickets.
- Top-of-backlog items fail Definition of Ready or exceed sprint capacity.
- Backlog ordering no longer reflects `epic-spec.md` backlog index dependencies or business priority.
- **Refining** existing stories (DoR, sizing, decomposition, prioritization) — not net-new epics from roadmap.
- Emitting or refreshing `tickets.csv` for manual Jira import after stories are groomed.

## Prerequisites

- At least one story exists in the `epic-spec.md` backlog index with a linked `{stories_dir}/{STORY_ID}/story-spec.md`.
- If missing: **stop** → run `/features`.

For net-new capability from roadmap themes → `/features`. See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md#features-vs-backlog-decision-table).

**Do not use when:** New epics, features, or stories must be authored from scratch — use `/features` (`feature-definition`) instead.

## Process

1. **Grooming/Refinement:** Review items at the top of the backlog (`epic-spec.md` backlog index order). Ensure each linked `story-spec.md` meets Definition of Ready (DoR), including US Readiness Rubric fields from `/features`. Update index rows when Summary, Size, or Dependencies change.
2. **Prioritization Framework Application:** Apply cost of delay, MoSCoW, or Kano model to rank items based on value and risk; reorder `epic-spec.md` backlog index index accordingly.
3. **Sizing:** Per [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md#shared-story-standards-both-features-and-backlog). Persist Size in `story-spec.md` and the index row.
4. **Defect vs. Feature Balancing:** Allocate appropriate capacity for tech debt, bugs, and new features.
5. **Pruning:** Archive stale backlog items that have sat too long without action. **Note:** "delete/archive backlog items" applies to backlog artifacts only — application data lifecycle follows **effective policy** (default: soft-delete per Default data lifecycle in constitution-core).
6. **Jira CSV export (when requested or after grooming for import):** Resolve export params → persist → write `tickets.csv` (see below). Skip entirely when the prompter says groom-only / skip export.

### Definition of Ready (DoR)

A backlog item is "ready" only when:

- Constitution story fields are present: Type, Summary, Description, Acceptance Criteria, Dependencies, Size (Fibonacci)
- Acceptance Criteria use **numbered scenarios** with `a.` Given / `b.` When / `c.` Then (Planning and story anatomy in constitution-core BDD)
- Description uses the mandatory bullet list from [feature-definition](../feature-definition/SKILL.md) (Scope In/Out, Pre-conditions, Dependencies, Size, Risks, Environment, Automation, Desk check; conditional API/UI/UX)
- Applicable **US Readiness Rubric** rows pass (see feature-definition)

### Jira export params and `tickets.csv`

Export constants are **not** hardcoded. They are engagement parameters asked or confirmed on `/backlog`, then persisted.

**Param fields:**

| Field | Purpose |
|-------|---------|
| `output_path` | Where to write `tickets.csv` (e.g. `nwob-docs/sdd/tickets.csv` or project-root `tickets.csv`) |
| `issue_type` | Value for every row's Issue type column |
| `parent_id` | Value for every row's Parent ID column |
| `summary_prefix` | Prepended to every Summary (empty string allowed) |
| `assignee` | Value for every row's Assignee column |
| `product` | Value for every row's Product column |

**Canonical params file:** `nwob-docs/sdd/tickets-export-params.md`  
**Template (copy shape):** [tickets-export-params.template.md](../../../templates/po/tickets-export-params.template.md)

#### When to resolve params

| Situation | Behavior |
|-----------|----------|
| Session will emit or refresh `tickets.csv` and params file **missing** | First-run intake — ask before export |
| Params file **exists** | Load; confirm or allow override |
| Prompter said groom-only / skip export | Skip ask + skip CSV |
| Prompter already passed all values in the `/backlog` prompt | Accept; persist; skip re-ask |

Do **not** block ordinary grooming on missing params. Ask only when the session will **emit or refresh** `tickets.csv`.

#### How to ask (first run)

One message (structured config confirm — not Phase 0 intent interview). Present a **proposed params block** with *illustrative* suggestions only (not locked skill defaults), then wait for explicit confirmation:

```text
Jira export params needed before tickets.csv.

Proposed (edit any line, or reply "accept"):

| Field | Proposed | Notes |
|-------|----------|--------|
| output_path | nwob-docs/sdd/tickets.csv | Or project-root tickets.csv |
| issue_type | Technical story | Exact string Jira import expects |
| parent_id | PROJ-XXXXX | Replace with real epic key if known |
| summary_prefix | [GBox]  | Empty string allowed |
| assignee | @gcash.com | Applied to every row |
| product | GBox | Product / project field |

Reply "accept", paste an edited table, or list overrides
(e.g. parent_id=PROJ-12345, summary_prefix=).
```

**Gate:** Do not write `tickets.csv` until the prompter explicitly confirms (`accept`, `yes`, or a clear override list). Reject vague “whatever” / “sure” for binding export params.

#### How to ask (params already on disk)

```text
Loaded nwob-docs/sdd/tickets-export-params.md:

  output_path: …
  issue_type: …
  parent_id: …
  summary_prefix: …
  assignee: …
  product: …

Use these for tickets.csv? Reply "use" | "override: …" | "skip export"
```

#### Persist then export

1. Write confirmed values to `nwob-docs/sdd/tickets-export-params.md`.
2. Map READY stories from each linked `story-spec.md` (in `epic-spec.md` chronological backlog index order) through the [feature-definition export contract](../feature-definition/SKILL.md#ticketscsv-export-contract-for-backlog).
3. Write UTF-8 `tickets.csv` at `output_path` with exactly **11** headers in order: Issue type, Parent ID, Summary, Description, Acceptance Criteria, Priority, Product, Capability, Tags, Story Points, Assignee.
4. Apply params to every row: `issue_type`, `parent_id`, `summary_prefix` + Summary, `product`, `assignee`. Map Size → Story Points (integer). Dependency/chronological row order. Quote fields with commas or newlines.
5. Do not export stories that fail applicable US Readiness Rubric criteria.

## Constitution Compliance

**Mandatory:** Fibonacci sizing; 5-point cap decomposition; top of backlog respects `epic-spec.md` backlog index chronological dependencies; numbered Given/When/Then AC in DoR; when CSV is emitted — params confirmed and persisted, 11-column schema per feature-definition contract.

**Default-overridable:** Backlog pruning ≠ application data deletion — data lifecycle follows effective policy (default: soft-delete per Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Export param *values* are always engagement-specific.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "We'll refine stories during the sprint" | Unready items block sprint commitment and violate DoR; refinement is pre-sprint work. |
| "8-point stories are fine if the team is experienced" | Constitution 5-point cap forces decomposition; large stories hide risk and block incremental delivery. |
| "Bullet-point AC is faster than Gherkin" | Vague bullets produce ambiguous acceptance; numbered Given/When/Then is mandatory per Planning and story anatomy in constitution-core. |
| "Add new epic from roadmap theme" | Net-new capability → `/features`; `/backlog` refines existing items. |
| "Hardcode GBox / TRIBE / assignee in the skill" | Export constants are params — ask or load from `tickets-export-params.md`. |
| "CSV from /features is enough" | `/features` authors `epic-spec.md` backlog index index + `story-spec.md`; `/backlog` owns params + CSV emit after grooming. |
| "Skip confirm when params file exists" | Re-confirm or allow override before overwrite; skip only when user says skip export. |

## Red Flags

- Top backlog items exceed single-sprint capacity without decomposition plan.
- Ready items missing constitution fields or rubric evidence.
- Acceptance criteria written as vague bullet points instead of numbered Given/When/Then.
- Backlog ordering contradicts `epic-spec.md` backlog index dependency chain.
- `tickets.csv` written without confirmed params or with hardcoded skill-level GBox/TRIBE literals.
- Export columns or headers deviate from the 11-column schema.
- CSV rows out of sync with groomed `story-spec.md` / `epic-spec.md` backlog index stories.

## Verification

- [ ] Prerequisite: at least one story in `epic-spec.md` backlog index with linked `story-spec.md`?
- [ ] Are the top items in the backlog small enough to fit in a single sprint?
- [ ] Do all "ready" items meet DoR (fields + numbered AC + applicable rubric) in `story-spec.md`?
- [ ] No ready item ≥ 5 SP without decomposition justification?
- [ ] Is there a clear logical ordering based on `epic-spec.md` backlog index dependencies and business value?
- [ ] If CSV export ran: params confirmed (or accepted from prompt) and persisted to `tickets-export-params.md`?
- [ ] If CSV export ran: file at `output_path` has 11 headers; rows match story-spec content; param columns applied consistently?
