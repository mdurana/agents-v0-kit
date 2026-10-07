---
name: presentation-intake-update
description: >-
  Updates presentation delivery parameters in intake-record.md when audience, goal,
  or format change mid-engagement. Use only after /problem has created the initial
  intake record. Does not perform problem analysis or initial intake.
---

# Presentation Intake Update

Command: `/intake`

## Overview

Updates **delivery parameters only** in `nwob-docs/presentations/intake-record.md`. Initial intake is exclusively owned by `/problem` (`business-problem-identification`).

Layer 2 — Configure. See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md) and [presentation-standards.md](../../../references/rules/presentation-standards.md).

## When to Use

- Audience, goal, output format, or output path changed after `/problem`.
- Optional `stack_override` or `lifecycle_override` needs updating before `/deck`.
- User requests parameter changes without changing problem or SDD substance.

## Prerequisites

- **`nwob-docs/presentations/intake-record.md` must exist** (created by `/problem`).
- If absent: **stop** and direct user to run `/problem` first.

## Inputs

- Existing `nwob-docs/presentations/intake-record.md`
- `.cursor/presentation.config.md` (optional pre-fill for fields being updated)
- User responses for fields to change

## Outputs

Updated **Intake Record** at `nwob-docs/presentations/intake-record.md`.

**Updatable fields:** `audience`, `goal`, `output_format`, `output_path`, `stack_override`, `lifecycle_override`.

**Suggested next command:** `/deck` (when SDD gate passes) or `/collect`

## Standalone Invocation

Update-only. Not a chain entry point for new engagements.

**Does:** Read existing intake record; update requested delivery params; persist to disk.

**Does NOT:** Perform problem analysis; create initial intake record; derive or change `mission_statement` or `project_name`; extract Features/Roadmap/Architecture; generate presentation artifacts.

## Process

### Step 1: Verify Intake Record Exists

Read `nwob-docs/presentations/intake-record.md`.

- If missing: stop with message — *"Run `/problem` first to create the initial intake record."*
- If present: load current values.

### Step 2: Identify Fields to Update

Ask which delivery parameters changed, or accept explicit user instruction. Optionally read `.cursor/presentation.config.md` for pre-fill.

Updatable only:

1. **Audience:** Technical, Non-technical, or Mixed.
2. **Presentation goal:** Status update, New initiative kickoff, Architecture review, or Roadmap review.
3. **Output format:** HTML or Markdown.
4. **Output path:** Default `nwob-docs/presentations/{deck-slug}.html` or `.md`.
5. **stack_override** / **lifecycle_override** (optional).

For substance changes:

- Problem or mission → direct user to `/problem`.
- Roadmap themes → `/roadmap`.
- Stories → `/features` or `/backlog`.
- Architecture → Solution Architect skills.

### Step 3: Persist Updates

Write updated fields to `intake-record.md`. Do not modify `source_paths` unless canonical paths changed (rare; user must confirm).

## Constitution Compliance

- Optional `stack_override` and `lifecycle_override` feed effective constraint resolution per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).
- Audience and goal drive depth scaling in `presentation-generation`.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Intake record missing—run full interview here" | Initial intake belongs in `/problem`; this skill is update-only. |
| "Update mission_statement while we're here" | Mission is derived from problem statement in `/problem`; substance changes go to author skills. |
| "Record paths and extract content in intake" | `/intake` updates delivery params only; `/collect` extracts content. |

## Red Flags

- Running without prior `/problem` intake record.
- Re-interviewing for project name or mission statement.
- Features or architecture content extracted during intake.
- Creating `intake-record.md` from scratch (belongs in `/problem`).

## Verification

- [ ] `intake-record.md` existed before this skill ran?
- [ ] Only delivery params updated (not SDD substance)?
- [ ] Updated record persisted to `nwob-docs/presentations/intake-record.md`?
- [ ] User directed to `/problem` or author skills if substance change requested?
