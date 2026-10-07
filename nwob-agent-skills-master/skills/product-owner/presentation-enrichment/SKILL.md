---
name: presentation-enrichment
description: >-
  Iteratively enhances HTML presentations with interactivity, modals, and diagrams
  based on user feedback. Use when enhancing an existing HTML presentation file
  with interactivity.
---

# Presentation Enrichment

Command: `/enrich`

## Overview

Extends a base HTML presentation with vanilla JS/CSS interactivity—modals, SVG diagrams, tooltips, and feature mockups—through an iterative feedback loop until the user declares the presentation complete.

Layer 3 — Present (polish). See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md) and [presentation-standards.md](../../../references/rules/presentation-standards.md).

## When to Use

- Base HTML exists (from `/present` or user-provided path).
- User wants click-to-detail modals, interactive diagrams, or visual refinements.
- Narrow-scope request to enhance `nwob-docs/presentations/*.html`.
- `/deck` final step (optional; **HTML only** — skip when `output_format` is Markdown).

## Prerequisites

- Path to existing HTML file.
- When used in `/deck` chain: prior `/present` in same engagement recommended for source fidelity.

## Inputs

- Path to HTML presentation (default: path from `intake-record.md` `output_path` under `nwob-docs/presentations/`)
- User feedback on what to add or improve

## Outputs

- Enriched HTML file at the same path (or user-specified path)
- User sign-off declaring presentation complete

**Suggested next command:** None

## Standalone Invocation

Primary standalone use case. No intake, collection, or generation required.

**Does:** Iterative polish with vanilla HTML/JS/CSS; verify `data-modal` attributes.

**Does NOT:** Run intake or content collection; change sourced business facts or architecture truth; apply to Markdown output (Markdown decks have no `/enrich` step in `/deck` chain).

## Process

### Step 1: Initiate Loop

After confirming the base HTML file path, ask the user: *"The base presentation is ready. What would you like to add or improve?"*

### Step 2: Implement Enrichments

Interpret the user's requests and implement them using vanilla HTML/JS/CSS. Common enrichment patterns include:

- **Click-to-Detail Modals:** Use a CDN parser like `marked.js` to render markdown inside modals triggered by clicking architecture components. Use shared modal wrappers to keep code DRY.
- **Interactive Diagrams:** Use inline `<svg>` diagrams inside modals with `viewBox` for responsiveness. Wire up floating tooltips and click-to-expand details using vanilla JS.
- **Feature-Specific UI:** Build CSS-only mockups (e.g., a phone mockup with a CSS scroll-snap carousel) and split-screen flow diagrams.

### Step 3: Iterate

After applying the requested changes, verify your work (e.g., ensure `data-modal` attributes match the JS node maps), and ask the user again until they state the presentation is complete.

**Output:** Enriched HTML file + explicit user sign-off.

## Constitution Compliance

- Modal and tooltip detail content must not introduce source drift (stack or lifecycle contrary to documented sources, or non-RFC 7807 error formats when APIs are detailed).
- Enrichment adds presentation layer only; it does not change sourced business facts or architecture truth from the base generation.
- Observability references in enriched content follow effective stack from sources (Datadog default when unspecified).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Skip enrichment—the base HTML is enough" | Valid when user confirms complete; enrichment is optional, not mandatory. |
| "Add technical detail in modals that wasn't in sources" | Enrichment clarifies existing content; inventing new architecture in modals violates source fidelity. |
| "One enrichment pass is always sufficient" | Iteration loop continues until user explicitly declares done. |
| "Enrich Markdown output" | `/enrich` is HTML only; Markdown has no enrichment loop. |

## Red Flags

- `data-modal` attributes do not match JS node maps (broken click-to-detail).
- Enriched modal content contradicts base presentation architecture or business narrative.
- Source-drifting stack or deletion semantics introduced in modal detail text.
- Intake or content collection started during enrichment.

## Verification

- [ ] All `data-modal` attributes match corresponding JS node maps.
- [ ] Enriched content consistent with base presentation (no contradictions).
- [ ] User explicitly declared the presentation complete.
- [ ] No source drift introduced in modal/tooltip technical detail.
