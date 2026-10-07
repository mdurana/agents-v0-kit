---
name: architect-led-sdd-intake
description: >-
  Orchestrates architect-led bootstrap of epic-spec.md (backlog index via /features) and initial
  intake-record.md in a single engagement. Invokes PO author skills sequentially
  with accelerated mode when source documentation is provided. Use when the user
  invokes /define, or when an architect arrives with problem/solution documentation
  and SDD artifacts do not yet exist.
---

# Architect-Led SDD Intake

Command: `/define`

## Overview

Single-invocation orchestrator for architect-led SDD bootstrap. Produces `nwob-docs/sdd/epic-spec.md` (including backlog index + HL US/TS after `/features`) and initial `nwob-docs/presentations/intake-record.md` by invoking Product Owner author skills in sequence — no procedural duplication. **Do not** generate `epic-plan.md`, `epic-tasks.md`, or `story-plan.md`.

SA native skills do **not** author SDD; this orchestrator loads PO skills from `.cursor/skills/` and follows each workflow exactly.

Boundaries: [solution-architect-skill-boundaries.md](../../../references/rules/solution-architect-skill-boundaries.md). SDD author chain: [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md).

## When to Use

- Architect-led engagement: problem and solution documentation come from Solution Architect, not Product Owner.
- `epic-spec.md` and/or `epic-spec.md` backlog index are missing and SA persona is active (no persona switch required).
- User invokes `/define` or asks to bootstrap SDD from architect-provided briefs, ADRs, meeting notes, or existing docs.
- Full PO author chain (`/problem` → `/ideate` → `/roadmap` → `/features`) is needed but should run in one session.

**Do not use when:**

- Only one section needs update — use individual commands (`/problem`, `/ideate`, `/roadmap`, `/features`).
- `epic-spec.md` + `epic-spec.md` backlog index already exist and only architecture is needed — use `/c4` or `/architecture`.
- Presentation deck generation is requested — switch to Product Owner persona for `/deck` (SA bundle includes `/intake` only).

## Prerequisites

- Phase 0 discovery complete per [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md).
- Artifact paths resolved (`.nwob/artifact-paths.json` or default `nwob-docs/` layout).

## Process

### 1. Source intake

1. Accept architect-provided material: briefs, ADRs, RFCs, meeting notes, diagrams, existing requirements.
2. Inventory what is present vs missing for each `epic-spec.md` section (Problem/Context, Metrics, Solutions, Roadmap) and `epic-spec.md` backlog index stories.
3. Record provenance in `epic-spec.md` under **Open Items** or a short **Sources** note (file paths, dates, authors).

### 2. Accelerated mode (when material is sufficient)

When confidence ≥95% that source docs cover problem, solutions, and sequencing:

1. Map source content to target sections — do not invent substance not supported by sources.
2. Ask **one consolidated confirmation** before writing:
   - Outcome / User / Why now / Success / Constraint / Out of scope
3. Skip full Phase 0 intent interview from `/problem` (see [intent-interview-patterns.md](../../../references/rules/intent-interview-patterns.md)).
4. Pass `accelerated_mode: true` context to each PO skill step below.

When material is thin (<95% confidence): run minimal targeted questions between steps; do not batch questions.

### 3. Sequential PO skill execution

Load and follow each skill **exactly** — do not improvise workflows from this orchestrator alone.

| Step | Load skill | Output |
|------|------------|--------|
| 3a | [business-problem-identification](../../product-owner/business-problem-identification/SKILL.md) | `epic-spec.md` Problem/Context + Metrics; **initial** `intake-record.md` |
| 3b | [product-ideation](../../product-owner/product-ideation/SKILL.md) | `epic-spec.md` Solutions/Hypotheses (+ Assumptions, Not Doing) |
| 3c | [product-roadmap-creation](../../product-owner/product-roadmap-creation/SKILL.md) | `epic-spec.md` ## Roadmap (Now/Next/Later) |
| 3d | [feature-definition](../../product-owner/feature-definition/SKILL.md) | `epic-spec.md` backlog index stories with numbered Gherkin AC |

**Stop gates between steps:** If a prerequisite section is missing after a step, stop and complete that step before continuing. Do not skip steps.

### 4. Post-orchestration gate

Before declaring done or suggesting architecture work:

- [ ] `epic-spec.md` on disk with Problem/Context, Metrics, Solutions, Roadmap
- [ ] `epic-spec.md` backlog index on disk with ≥1 US Readiness Rubric–ready story
- [ ] `intake-record.md` on disk (initial write from step 3a)
- [ ] Constitution story anatomy (all 6 fields) and numbered Gherkin AC per [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md)

If any gate fails: stop; name the failing step and re-run the owning PO skill.

### 5. Handoff

| Next need | Suggest |
|-----------|---------|
| Conceptual architecture | `/c4` → `/pattern` → … |
| Targeted SDD edit | Individual command (`/ideate`, `/features`, etc.) |
| Presentation delivery params | `/intake` |
| Backlog refinement / Jira export | Switch to Product Owner persona → `/backlog` |
| Design workshop / tasks | Lead Builder `orchestrate-design` (after sprint-ready backlog) |

## Constitution Compliance

**Mandatory:** SDD gate, story anatomy, Gherkin AC, Fibonacci sizing, 5-point cap, chronological `epic-spec.md` backlog index ordering — enforced via invoked PO skills.

**Default-overridable:** technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints) — resolve during ideation/roadmap steps when architect docs specify overrides.

## Rationalizations

| Excuse | Correct action |
|--------|----------------|
| "I'll write spec sections inline without loading PO skills" | Load each PO skill; follow its Process and Verification |
| "Architect docs are enough — skip epic-spec.md backlog index stories" | Run `feature-definition`; `/c4` design-package mode needs `epic-spec.md` backlog index |
| "Skip intake-record — we won't present" | Step 3a creates initial intake; `/intake` updates later |
| "One big interview replaces the chain" | Use accelerated mode + one confirmation; still run all four PO skills |
| "Switch to PO persona for /define" | SA persona owns `/define`; PO skills are bundled |

## Red Flags

- Proceeding to `/c4` without `epic-spec.md` (including backlog index after `/features`) on disk.
- Stories in `epic-spec.md` backlog index without numbered Gherkin AC or missing rubric rows.
- Authoring SDD content inside SA native skills (`architecture-governance`, etc.) instead of via PO skills.
- Creating `story-tasks.md` or technical annex in this orchestrator — Builder `co-design-solution` and SA/LB `/orchestrate-design` only.

## Verification

- [ ] Phase 0 complete and artifact paths resolved?
- [ ] Source provenance recorded in `epic-spec.md`?
- [ ] All four PO author skills loaded and followed in sequence?
- [ ] `epic-spec.md` contains Problem, Metrics, Solutions, Roadmap?
- [ ] `epic-spec.md` backlog index contains ≥1 rubric-ready story with numbered AC?
- [ ] `intake-record.md` exists with `source_paths` populated?
- [ ] User informed of next step (`/c4` or targeted command)?
