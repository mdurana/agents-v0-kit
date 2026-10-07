---
name: product-ideation
description: >-
  Transforms validated business problems into viable, technically feasible product
  solutions per the Enterprise System Constitution. Embeds structured ideation frameworks.
  Use when a clear problem is defined and viable solutions are needed.
---

# Product Ideation

Command: `/ideate`

## Overview

Transforms validated business problems into viable, technically feasible product solutions in `nwob-docs/sdd/epic-spec.md`, balancing creativity with constitution constraints.

Layer 1 — Author. See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md).

Ideation frameworks (embedded from reference `idea-refine`): [ideation-frameworks.md](../../../references/rules/ideation-frameworks.md).

## When to Use

- A clear problem is defined and you need viable, technically sound solutions.
- Multiple solution approaches exist and trade-offs need evaluation before `epic-spec.md` commitment.
- Stakeholders request a specific feature but alternative approaches have not been explored.

## Prerequisites

- `nwob-docs/sdd/epic-spec.md` has non-empty **Problem/Context**.
- If missing: **stop** → run `/problem`.

## Process

1. **Divergent Thinking:**
   - Restate problem as HMW ("How might we…").
   - Generate 5–8 variations (inversion, audience shift, constraint removal, SCAMPER, JTBD).
   - See [ideation-frameworks.md](../../../references/rules/ideation-frameworks.md).
2. **Convergent Thinking:**
   - Cluster into 2–3 directions.
   - Apply mandatory constraints (SDD workflow, story standards) and **effective** stack/lifecycle per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).
   - Evaluate with painkiller vs. vitamin rubric and feasibility/differentiation matrix.
   - Run pre-mortem on top direction(s).
3. **Solution Hypothesis:** "We believe building [Solution] for [Persona] achieves [Outcome]. Success is [Metric]."
4. **Concept Validation:** Define minimal effort tests (prototype, painted-door).
5. **SDD Handoff:** Write approved solutions to `nwob-docs/sdd/epic-spec.md` section `## Solutions` (or `## Solutions / Hypotheses`). Each hypothesis includes:
   - **Key assumptions** (must be true / should be true / might be true)
   - **Not Doing** list (mandatory)
   - **Validation** approach
6. **Metrics refinement:** Update `epic-spec.md` Metrics if solution changes how success is measured.

**Does NOT:** Write one-pagers to `docs/ideas/`; format content for leader-facing decks (`presentation-generation`).

### Solutions section template

See [ideation-frameworks.md](../../../references/rules/ideation-frameworks.md#specmd-solutions-template).

## Constitution Compliance

**Mandatory:** Solutions feed into `epic-spec.md` before proceeding to `epic-spec.md` backlog index; SDD workflow enforced.

**Default-overridable:** Solutions must be feasible within **effective stack** and **effective data lifecycle** (defaults per constitution sections 2 and 5 unless overridden in prompt or sources). See [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "We already know the right solution" | Single-option ideation skips trade-off analysis and constitution feasibility checks. |
| "Constraints kill creativity" | Mandatory SDD and story rules prevent rework; effective stack/lifecycle bounds creativity within feasible choices. |
| "We can validate after building an MVP" | Painted-door and prototype tests cost less than building the wrong MVP. |
| "Output a one-pager to docs/ideas/" | All substance goes to `epic-spec.md` ## Solutions per nwob artifact layout. |
| "Use reference idea-refine skill directly" | Frameworks are embedded here via ideation-frameworks.md. |

## Red Flags

- Only one solution considered without documenting rejected alternatives.
- Solution specifies stack or lifecycle that conflicts with other sources without resolution.
- Data lifecycle in solution contradicts effective policy from sources.
- Solution hypothesis lacks a measurable success metric.
- Hypothesis missing Key Assumptions or Not Doing list.
- `/roadmap` started without Solutions section in `epic-spec.md`.

## Verification

- [ ] Prerequisite: Problem/Context exists in `epic-spec.md`?
- [ ] Multiple solutions considered (5–8 variations explored)?
- [ ] Technical feasibility evaluated against effective stack and data lifecycle?
- [ ] Painkiller vs. vitamin assessment documented for top direction(s)?
- [ ] Each hypothesis has Key Assumptions and Not Doing list?
- [ ] Clear hypothesis linking solution to outcome?
- [ ] `nwob-docs/sdd/epic-spec.md` ## Solutions section updated with approved hypotheses?
