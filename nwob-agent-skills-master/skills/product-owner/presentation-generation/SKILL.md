---
name: presentation-generation
description: >-
  Renders the base HTML or Markdown presentation from a confirmed Content Record
  and intake-record.md. Audience-adapted, source-faithful. Use when Content Record
  is confirmed and SDD gate has passed.
---

# Presentation Generation

Command: `/present`

## Overview

Renders the leader-facing presentation artifact from a confirmed Content Record and Intake Record. Separates business narrative from architecture truth with audience-scaled depth and mandatory constitution rules on technical content.

Layer 3 — Present (render). See [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md) and [presentation-standards.md](../../../references/rules/presentation-standards.md).

## When to Use

- Content Record confirmed from `/collect`.
- Base presentation artifact needed before HTML enrichment.
- User requests Markdown narrative report instead of interactive HTML.
- `/deck` step after content extraction.

## Prerequisites

- **Tiered Presentation SDD Gate passed** (partial minimum; full when architecture pillar used).
- **Confirmed Content Record** from `presentation-content-extraction` (`/collect`) — required; no inline collection fallback.
- **`nwob-docs/presentations/intake-record.md`** for `audience`, `goal`, `output_format`, `output_path`.

If Content Record or Intake Record missing: stop; run `/collect` or `/problem` respectively.

## Inputs

- Content Record: `features`, `roadmap`, `architecture`, `constraint_flags`, `tier`
- Intake Record from `nwob-docs/presentations/intake-record.md`

## Outputs

Presentation artifact at `output_path` (default: `nwob-docs/presentations/{deck-slug}.html` or `.md`).

**Suggested next command:** `/enrich` if HTML; done if Markdown (no enrichment step).

## Standalone Invocation

Render-only. Requires prior `/collect`.

**Does:** Apply audience rules; separate business/architecture; enforce source fidelity; write artifact to `nwob-docs/presentations/`.

**Does NOT:** Re-extract from source docs; run intake interview; author SDD substance; add interactive polish (`/enrich`).

## Process

### Step 1: Verify Prerequisites

Confirm tiered SDD gate, Content Record, and `intake-record.md`. If any missing, stop and name prerequisite skill.

For **partial tier**: render Features and Roadmap tabs/sections only; omit or mark Architecture N/A.

### Step 2: Apply Audience Adaptation

Apply rules based on `audience` from Intake Record:

- **Non-technical:** Larger icons, plain-language text, no jargon. Architecture zone-level only.
- **Technical:** Compact cards, exact component names, full sub-component hierarchies.
- **Mixed:** Standard cards, plain summaries with technical detail; zones with sub-components.

### Step 3: Separate Business and Architecture Content

- **Features:** Capabilities grouped by capability layer from Content Record.
- **Roadmap:** Milestones and deliverables; preserve `epic-spec.md` backlog index story order (Planning and story anatomy in constitution-core).
- **Architecture:** Zones, services, data flows, effective stack from Content Record — no source drift.

Per Core execution and spec-driven development in constitution-core, show **stateless K8s** — state externalized to persistent stores (Architectural principles in constitution-core).

### Step 4: Generate Output Format

#### HTML Output

- HTML5 + Tailwind CSS (CDN) + Font Awesome (CDN) + Vanilla JS (tabs).
- Header: project name and mission statement from Intake Record.
- Tabs: Features (card grid), Roadmap (timeline), Architecture (zone diagram).

#### Markdown Output

- Executive Summary, Features, Roadmap, Architecture sections (depth scaled to audience).

### Step 5: Write Artifact

Write to `output_path` under `nwob-docs/presentations/`.

When APIs depicted: **RFC 7807** error shape (Contracts and quality in constitution-core). Data lifecycle: effective policy from sources (Default data lifecycle in constitution-core).

## Constitution Compliance

**Mandatory:** Stateless K8s depiction (Core execution and spec-driven development in constitution-core); RFC 7807 when APIs in scope (Contracts and quality in constitution-core); preserve `epic-spec.md` backlog index order when sourced (Planning and story anatomy in constitution-core); no softened coverage mandates (coverage gates in constitution-core).

**Default-overridable:** Effective stack and data lifecycle from sources (constitution sections 2 and 5).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Content Record missing—extract inline" | Run `/collect` first; render does not author or extract. |
| "Re-interview for audience" | Read `intake-record.md`; use `/intake` to update params. |
| "Simplify architecture contrary to sources" | Audience rules allow abstraction depth, not inventing stack. |

## Red Flags

- Rendering without confirmed Content Record.
- Re-extracting from `epic-spec.md` / `epic-spec.md` backlog index during render.
- Stack or lifecycle contradicting documented sources.
- Modals or interactive polish added here (belongs in `/enrich`).

## Verification

- [ ] SDD gate and Content Record confirmed before render?
- [ ] Artifact written to `nwob-docs/presentations/` path from intake record?
- [ ] Audience adaptation applied?
- [ ] Technical content source-faithful with mandatory constitution rules?
