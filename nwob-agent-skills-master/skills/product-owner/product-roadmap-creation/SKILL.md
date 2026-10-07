---
name: product-roadmap-creation
description: >-
  Creates strategic Now/Next/Later roadmap themes in epic-spec.md per the Enterprise
  System Constitution. Use when planning strategic direction and sequencing work
  over multiple horizons.
---

# Product Roadmap Creation

Command: `/roadmap`

## Overview

Authors strategic roadmap themes (Now/Next/Later) in `nwob-docs/sdd/epic-spec.md`, aligned with spec-driven delivery and chronological `epic-spec.md` backlog index ordering.

Layer 1 — Author. See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md).

## When to Use

- Planning the strategic direction and sequence of work over multiple horizons.
- Engineering needs a shared view of initiative sequencing tied to SDD.
- Approved themes must land in `epic-spec.md` and align with chronological `epic-spec.md` backlog index ordering.

## Prerequisites

- `nwob-docs/sdd/epic-spec.md` has `## Solutions` (or `## Solutions / Hypotheses`).
- If missing: **stop** → run `/ideate`.

## Process

1. **Vision Alignment:** Tie roadmap to company goals and `epic-spec.md` Problem/Context.
2. **Establish Horizons:** Use Now / Next / Later instead of hard dates.
3. **Identify Themes:** Group initiatives into strategic themes with outcome metrics per theme.
4. **Sequence Themes:** Foundation and infrastructure themes precede UI/feature themes (aligns with chronological `epic-spec.md` backlog index ordering).
5. **Prioritize:** Use RICE or WSJF to sequence work.
6. **SDD Handoff:** Write approved themes to `nwob-docs/sdd/epic-spec.md` section `## Roadmap` (Now/Next/Later with outcome metrics per theme).
7. **Metrics refinement:** Update `epic-spec.md` Metrics if themes change how success is measured.
8. **Plan alignment (read-only):** If `epic-spec.md` backlog index exists, verify theme order is compatible with foundation-first sequencing. If contradictions exist, **flag for `/features` or `/backlog`** — do **not** edit `epic-spec.md` backlog index.

**Does NOT:** Edit `epic-spec.md` backlog index; format content for leader-facing decks; run `/collect` or presentation skills; optimize prose for executives (that is `presentation-generation`).

### `epic-spec.md` Roadmap section template

```markdown
## Roadmap

### Now
- **Theme:** <name> — **Outcome:** <metric or result>

### Next
- **Theme:** <name> — **Outcome:** <metric or result>

### Later
- **Theme:** <name> — **Outcome:** <metric or result>
```

## Constitution Compliance

Per [constitution-core.mdc](../../../rules/constitution-core.mdc) Planning and story anatomy, `epic-spec.md` backlog index must list stories in strict chronological execution order. Roadmap sequencing must reflect this — infrastructure and foundation work before UI/features.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Hard dates make the roadmap more actionable" | Date-driven roadmaps create false certainty; Now/Next/Later preserves adaptability while sequencing dependencies. |
| "UI features should lead to show progress early" | Foundation-first sequencing prevents blocked teams and rework per Planning and story anatomy in constitution-core. |
| "Roadmap themes don't need epic-spec.md linkage" | Unlinked themes become orphan initiatives that bypass SDD gates. |
| "Format for executives now—we'll present later" | Author in `epic-spec.md`; presentation skills extract and render. |

## Red Flags

- Roadmap is output/feature-driven with no outcome metrics per theme.
- UI/feature themes scheduled before infrastructure or foundation dependencies.
- Technical dependencies between themes not documented.
- Roadmap written only in chat or presentation format, not `epic-spec.md` ## Roadmap.
- Leader-facing deck formatting attempted in this skill.

## Verification

- [ ] Prerequisite: ## Solutions exists in `epic-spec.md`?
- [ ] Outcome-driven rather than purely output/feature-driven?
- [ ] Foundation/infrastructure themes precede UI/feature themes?
- [ ] Technical dependencies considered?
- [ ] Aligned with business strategy?
- [ ] `nwob-docs/sdd/epic-spec.md` ## Roadmap section written with Now/Next/Later themes?
