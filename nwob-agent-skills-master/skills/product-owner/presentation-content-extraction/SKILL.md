---
name: presentation-content-extraction
description: >-
  Extracts Features, Roadmap, and Architecture from canonical nwob-docs paths into
  a Content Record for presentation generation. Read-only; never authors SDD or
  architecture substance. Use when SDD gate passes and content must be structured
  before /present.
---

# Presentation Content Extraction

Command: `/collect`

## Overview

Extracts the three presentation pillars—**Features**, **Roadmap**, and **Architecture**—from canonical `nwob-docs/` sources only. Produces a Content Record for `/present`. Never authors product or architecture substance.

Layer 3 — Present (extract). See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md) and [presentation-standards.md](../../../references/rules/presentation-standards.md).

## When to Use

- SDD gate passed; Features, Roadmap, and/or Architecture must be structured before `/present`.
- `/deck` step after reading `intake-record.md`.
- User requests content extraction for an existing SDD package.

## Prerequisites

- **Tiered Presentation SDD Gate** — minimum **partial** tier: `epic-spec.md` (Problem + Roadmap + backlog index), `intake-record.md`.
- **Full tier** (when architecture pillar requested): partial + `architecture/architecture.md` (or dual twin `sdd/masterplan.md`) and flat `sdd/components/*-plan.md` when present.
- **`nwob-docs/presentations/intake-record.md` exists** (from `/problem`).
- If partial gate fails: stop and name remediation. If user requests full deck but full tier incomplete: stop or offer partial tier with explicit confirmation.

## Inputs

- `intake-record.md` `source_paths` (defaults per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md))
- Canonical files:
  - `nwob-docs/sdd/epic-spec.md` — Problem, Metrics, Roadmap, chronological backlog index
  - `{stories_dir}/{STORY_ID}/story-spec.md` — per-story Gherkin (via index links)
  - `nwob-docs/architecture/architecture.md` or `nwob-docs/sdd/masterplan.md`, ADRs, flat component plans

## Outputs

**Content Record** — handoff to `/present`:

| Field | Description |
|-------|-------------|
| `features` | Grouped by capability layer (from `epic-spec.md` backlog index + linked `story-spec.md`) |
| `roadmap` | Milestones, timeframes, deliverables (from `epic-spec.md` ## Roadmap + backlog index order) |
| `architecture` | Zones and sub-components (from `architecture/` and flat component plans) |
| `sources` | Traceability list (canonical paths only) |
| `constraint_flags` | Source conflicts; `architecture: N/A` for partial tier |
| `tier` | `partial` \| `full` |

**Optional persist:** `nwob-docs/presentations/content-record.md` when user requests cross-session handoff.

**Suggested next command:** `/present`

## Standalone Invocation

Extract-only from canonical paths. No interview mode. No inline intake.

**Does:** Read canonical sources; extract and structure pillars; flag conflicts; confirm extraction accuracy with user.

**Does NOT:** Interview to author features, roadmap, or architecture; set audience/format; write SDD; generate presentation artifacts; discover non-canonical paths.

## Process

### Step 1: Verify Prerequisites and Tier

1. Verify **partial tier**: `epic-spec.md` (Problem + Roadmap + backlog index), `intake-record.md`.
2. If partial fails: stop; list missing artifacts and owning step.
3. If partial passes: determine tier:
   - **Full:** `architecture/architecture.md` (or `sdd/masterplan.md`) present → all pillars.
   - **Partial:** architecture missing → Features + Roadmap only; `constraint_flags.architecture = N/A`.
4. If user requests architecture but full tier incomplete: stop and name SA / Lead Builder remediation, or offer partial tier with explicit confirmation.

### Step 2: Read Canonical Sources

Read paths from `intake-record.md` `source_paths` (or defaults):

| Pillar | Primary sources |
|--------|-----------------|
| Features | `epic-spec.md` backlog index, `{stories_dir}/*/story-spec.md` |
| Roadmap | `epic-spec.md` (## Roadmap + backlog index sequencing) |
| Architecture | `architecture/architecture.md` or `sdd/masterplan.md`, `sdd/components/*-plan.md`, ADRs |

### Step 3: Extract and Structure

1. Extract **Features** from backlog index order and linked `story-spec.md` files; group by capability layer for presentation layout.
2. Extract **Roadmap** from `epic-spec.md` ## Roadmap and backlog index sequencing.
3. Extract **Architecture** zones and sub-components from architecture docs (full tier only; skip for partial).
4. Summarize extraction; ask user to confirm **accuracy** (not substance authoring).

### Step 4: Handle Insufficient Sources

If a pillar cannot be populated from canonical sources:

- **Stop** and name the **author skill** to run:
  - Missing Roadmap section → `/roadmap`
  - Missing stories / backlog index → `/features`
  - Missing architecture → Solution Architect skills
- Do **not** interview to fill gaps.

### Step 5: Flag Conflicts

- Mark pillars explicitly N/A if out of scope.
- Flag contradictory sources (e.g., spec vs. architecture stack mismatch).
- When sourced from backlog index / `story-spec.md`, preserve story execution order per Planning and story anatomy in constitution-core.

## Constitution Compliance

**Mandatory:** Preserve chronological story order and Gherkin AC when sourced from `story-spec.md` (via `epic-spec.md` backlog index).

**Source fidelity:** Do not invent capabilities. Flag source conflicts per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Spec is thin—interview for roadmap content" | Author substance in `/roadmap`; extraction reads only. |
| "No architecture.md—describe zones in collect" | Architecture is SA-authored via `/c4` … `/architecture`; run SA commands first. |
| "Skip confirmation—sources are authoritative" | User confirms extraction accuracy, not substance. |
| "Run abbreviated intake for audience" | Audience lives in `intake-record.md`; use `/intake` to update. |
| "Need epic-tasks for full tier" | Retired — full tier uses architecture/masterplan (+ component plans when present). |

## Red Flags

- Interview mode used to author features, roadmap, or architecture.
- Features invented not present in canonical sources.
- Abbreviated inline intake for audience/goal.
- Non-canonical path discovery when SDD exists in `nwob-docs/`.
- Backlog index stories reordered or Gherkin paraphrased into vague bullets.
- Requiring retired `epic-plan.md` or `epic-tasks.md` for extraction.

## Verification

- [ ] Partial or full tier evaluated and documented in Content Record?
- [ ] SDD gate passed before extraction?
- [ ] `intake-record.md` existed?
- [ ] All pillars read from canonical `nwob-docs/` paths only?
- [ ] User confirmed extraction accuracy?
- [ ] Insufficient sources routed to author skills (not interview)?
- [ ] Content Record complete and ready for `/present`?
