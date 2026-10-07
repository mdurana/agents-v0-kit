---
name: value-stream-mapping
description: >-
  Maps the sequence of activities from concept to customer delivery per the Enterprise
  System Constitution, including SDD artifact handoffs. Use when optimizing delivery
  process, reducing waste, or improving time-to-market.
---

# Value Stream Mapping

Command: `/value`

## Overview

Maps the sequence of activities to design, produce, and deliver a feature to identify bottlenecks and waste, including spec-driven development artifact handoffs.

Layer 1 — Author. Process optimization only; does not write SDD or presentation content.

## When to Use

- Looking to optimize the delivery process, reduce waste, or improve time-to-market.
- Lead time is growing but the bottleneck step is unclear.
- Teams bypass SDD artifacts and vibe-code directly to implementation.

## Process

1. **Identify Stream:** Select the specific lifecycle to map.
2. **Map Current State:** Document steps, delays, handoffs, Lead Time. Include SDD artifact handoffs as explicit steps: `epic-spec.md` (backlog index) → per-story `story-spec.md` + `story-tasks.md` → implementation.
3. **Identify Waste (Muda):** Look for overproduction, waiting, transport, etc. Flag **vibe-coding** (implementation without spec/plan/tasks) as prohibited waste per Core execution and spec-driven development in constitution-core.
4. **Map Future State:** Design optimized flow eliminating non-value steps while preserving mandatory SDD gates.
5. **Implementation Plan:** Define actionable process changes.
6. **Persist (recommended):** Write process map to `nwob-docs/process/{YYYY-MM-DD}-value-stream-{slug}.md`.

## Outputs

- **Primary:** `nwob-docs/process/{YYYY-MM-DD}-value-stream-{slug}.md`
- **Fallback:** Process map in chat when user declines persistence

## Constitution Compliance

Per [constitution-core.mdc](../../../rules/constitution-core.mdc) Core execution and spec-driven development:
- Spec-Driven Development is mandatory — no code without `epic-spec.md` and in-scope `story-spec.md` + `story-tasks.md`.
- Zero vibe-coding: ad-hoc implementation bypassing epic-spec → story-spec → story-tasks workflow is strictly prohibited.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "SDD gates slow us down — skip them for small changes" | Small changes accumulate tech debt; SDD gates are value-add steps, not waste. |
| "The current process works fine without mapping" | Unmapped processes hide invisible queue time and handoff delays. |
| "We can optimize by parallelizing spec and implementation" | Parallelizing spec and code produces rework when requirements change. |

## Red Flags

- Current-state map based on ideal process rather than observed reality.
- SDD artifact handoffs (`epic-spec.md` → `story-spec.md` + `story-tasks.md`) omitted from the value stream.
- Vibe-coding not identified as waste in the current state.
- Future state removes SDD gates to reduce lead time.

## Verification

- [ ] Based on observed reality?
- [ ] Output persisted to `observations/` (or user declined)?
- [ ] SDD artifact handoffs (`epic-spec.md` → `story-spec.md` + `story-tasks.md`) mapped as explicit value-stream steps?
- [ ] Vibe-coding identified as waste in current state?
- [ ] Handoffs and queue times quantified?
- [ ] Future state demonstrably reduces lead time/waste while preserving SDD gates?
