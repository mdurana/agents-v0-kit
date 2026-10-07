---
name: business-problem-identification
description: >-
  Extracts, analyzes, and clearly defines core business problems per the Enterprise
  System Constitution. Embeds intent-interview patterns for underspecified asks.
  Captures initial presentation delivery params and intake-record.md. Use when a
  stakeholder presents a vague request and the root cause needs defining before
  spec-driven delivery begins.
---

# Business Problem Identification

Command: `/problem`

## Overview

Extracts, analyzes, and clearly defines the core business problems that need solving. Prevents building the wrong product by ensuring root cause understanding. Output feeds directly into `epic-spec.md` and seeds `nwob-docs/presentations/intake-record.md` (sole initial writer).

Layer 1 — Author. See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md).

Intent interview patterns (embedded from reference `interview-me`): [intent-interview-patterns.md](../../../references/rules/intent-interview-patterns.md).

## When to Use

- A stakeholder presents a vague request or symptom, and the root cause needs defining.
- Spec-driven delivery has not yet started and no `epic-spec.md` Problem/Context section exists.
- Multiple stakeholders describe conflicting symptoms without a shared problem statement.
- Ask is framed as a feature request ("we need a dashboard") or missing who/why/success/constraint.

## Process

### Phase 0 — Intent extraction (conditional)

Run when ask is underspecified, convention-driven, or feature-framed. **Skip** when confidence ≥95% with defensible evidence.

Follow [intent-interview-patterns.md](../../../references/rules/intent-interview-patterns.md):

1. **Hypothesize** with confidence % (and reason if below ~70%).
2. **One question at a time** with GUESS attached — no batching.
3. **Want vs. should-want** probe when answers sound like best-practice talk.
4. **Restate** Outcome / User / Why now / Success / Constraint / **Out of scope**.
5. **Explicit yes** before proceeding — reject "sounds good" / "whatever you think".

**Non-interactive contexts:** flag blocker; do not guess.

### Standard problem analysis

6. **Gather Context:** Ask targeted questions to understand current state and pain points (after Phase 0 if run).
7. **Root Cause Analysis:** Use "5 Whys" or Fishbone diagrams.
8. **Quantify Impact:** Determine business cost (revenue, churn, tech debt).
9. **Define Problem Statement:** "[User] struggles with [Problem] because [Root Cause], resulting in [Business Impact]."
10. **Initiate SDD:** Draft the Problem/Context and Metrics sections of `nwob-docs/sdd/epic-spec.md`.
11. **Presentation delivery params (mandatory):** Read `.cursor/presentation.config.md` for pre-fill. Interview only for gaps: `audience`, `goal`, `output_format`, `output_path`. Derive `project_name` from initiative name and `mission_statement` from problem statement (user confirms).
12. **Persist Intake Record:** Write `nwob-docs/presentations/intake-record.md` with auto-populated `source_paths`:
    - `features`: `nwob-docs/sdd/epic-spec.md`
    - `roadmap`: `nwob-docs/sdd/epic-spec.md` (Roadmap section and backlog index when present)
    - `architecture`: `nwob-docs/architecture/architecture.md`
13. **Gate:** Do not proceed to `/ideate` until `epic-spec.md` Problem/Context exists and `intake-record.md` is on disk.

**Does NOT:** Ask for features, roadmap themes, or architecture content; extract presentation pillars; generate deck artifacts; persist to `docs/intent/`.

## Constitution Compliance

All problem definitions must comply with [constitution-core.mdc](../../../rules/constitution-core.mdc). No feature ideation proceeds without a `epic-spec.md` draft initiated.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "The request is clear enough to start building" | Unvalidated root cause → wrong product risk; `epic-spec.md` Problem section is mandatory before ideation. |
| "We can document the problem later in the spec" | Problem definition *is* the spec foundation; deferring it guarantees rework. |
| "Stakeholders already agree on the solution" | Solutions without validated problems optimize the wrong outcome. |
| "Skip intake—we'll set audience when we build the deck" | Delivery params captured during problem definition; `/intake` is update-only later. |
| "User said skip interview" | Confidence must be ≥95% with documented evidence; otherwise run Phase 0. |
| "Run reference interview-me as separate skill" | Phase 0 is embedded here; output goes to `epic-spec.md`, not `docs/intent/`. |

## Red Flags

- Problem statement framed as a feature request ("we need a dashboard") instead of a user struggle — **mandatory Phase 0**.
- Business impact described qualitatively with no quantified cost or metric.
- Multiple root causes identified but none prioritized or validated with stakeholders.
- `epic-spec.md` handoff skipped or Problem/Context section left empty.
- `intake-record.md` not persisted before `/ideate`.
- Three or more interview questions batched in one message.
- Proceeding to write `epic-spec.md` before explicit yes on intent restate.

## Verification

- [ ] Phase 0 run when ask was vague or feature-framed (or skip justified at ≥95% confidence)?
- [ ] Framed from the user/business perspective?
- [ ] Business impact clearly quantified?
- [ ] Stakeholder agreement on priority?
- [ ] `nwob-docs/sdd/epic-spec.md` draft initiated with Problem/Context and Metrics sections?
- [ ] `nwob-docs/presentations/intake-record.md` on disk with audience, goal, output_format, output_path?
- [ ] `mission_statement` derived from problem statement (not independently invented)?
