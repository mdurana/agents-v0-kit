# Presentation Standards

Shared rules for Product Owner presentation skills (Layer 3 — Present). Skills in `skills/product-owner/` invoke this reference. Skill boundaries: [product-owner-skill-boundaries.md](product-owner-skill-boundaries.md). Persona: [agents/product-owner.md](../../agents/product-owner.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

---

## Role Scope

Product Owner presentation skills communicate **both**:

- **Business product narrative** — problem context, value proposition, capabilities, roadmap milestones, and outcomes for leaders and mixed audiences.
- **Architecture truth** — platform zones, services, data flows, stack choices, and technical constraints as documented in canonical `nwob-docs/` sources.

Presentation skills **extract, render, and polish** — they do not author product strategy (author skills) or architecture design (Solution Architect).

---

## Tiered Presentation SDD Gate

Required before `/deck`, `/collect`, or `/present` (not `/enrich`).

### Partial tier (product narrative)

| File | Minimum bar |
|------|-------------|
| `nwob-docs/sdd/epic-spec.md` | Non-empty Problem/Context + `## Roadmap` + at least one backlog index row |
| `nwob-docs/presentations/intake-record.md` | Exists (created by `/problem`) |

**Pillars:** Features, Roadmap. Architecture = N/A.

**Use when:** Early stakeholder alignment; pre–Lead Builder; masterplan/architecture not yet available.

### Full tier (leader + architecture)

Partial tier **plus:**

| File | Minimum bar |
|------|-------------|
| `nwob-docs/sdd/masterplan.md` and/or `nwob-docs/architecture/architecture.md` | Required when architecture pillar is requested |
| Flat `nwob-docs/sdd/components/{component-name}-plan.md` | When component detail is requested |

**Pillars:** Features, Roadmap, Architecture (all three).

**Use when:** Leader-facing technical deck; default for `/deck` when SA artifacts exist.

### Gate behavior

- **Gate failure:** Stop; list missing artifacts and owning workflow step (e.g. `story-tasks.md` → `co-design-solution`; architecture → SA `/c4` … `/architecture`; `intake-record.md` → `/problem`).
- **`/deck`:** Attempt full tier first; if masterplan/architecture missing, offer partial tier with **explicit user confirmation**.
- **`/collect`:** Evaluate tier; set `constraint_flags.architecture = N/A` for partial tier; never interview to fill gaps.

---

## Slash Commands

User-facing entry points. Skills load from `skills/product-owner/<skill-name>/SKILL.md`.

### Command summary

| Command | Skill | Question answered | Gate | Typical next |
|---------|-------|-------------------|------|--------------|
| `/intake` | `presentation-intake-update` | *Update* delivery params | None (requires existing intake record) | `/deck` when SDD gate passes |
| `/collect` | `presentation-content-extraction` | *Extract* deck content from canonical sources | Tiered SDD gate + intake record | `/present` |
| `/present` | `presentation-generation` | *Render* the deck artifact | Tiered SDD gate + Content Record | `/enrich` (HTML only) |
| `/enrich` | `presentation-enrichment` | *Polish* interactivity | Existing HTML only | — |
| `/deck` | Full present chain | *End-to-end* leader-facing deck | SDD gate + intake record | — |

Initial intake is **not** `/intake` — it runs during `/problem` (`business-problem-identification`).

### `/intake` → `presentation-intake-update`

**Purpose:** Update presentation **delivery parameters** when they change mid-engagement.

**Does:** Update `audience`, `goal`, `output_format`, `output_path`, optional overrides in `intake-record.md`.

**Does NOT:** Create initial intake record; perform problem analysis; extract content; generate artifacts.

**Prerequisites:** `nwob-docs/presentations/intake-record.md` from `/problem`. If absent → direct user to `/problem`.

### `/collect` → `presentation-content-extraction`

**Purpose:** **Extract** presentation substance from canonical `nwob-docs/` paths into a Content Record.

**Does:** Read `epic-spec.md`, per-story `story-spec.md` / `story-tasks.md` when delivery scope is in scope, `masterplan.md` / `architecture/` per `intake-record.md` `source_paths`; structure pillars; flag conflicts; confirm extraction accuracy.

**Does NOT:** Interview to author features/roadmap/architecture; set audience/format; write SDD; use non-canonical paths.

**Prerequisites:** Tiered Presentation SDD Gate + `intake-record.md`. Partial tier omits architecture; full tier requires masterplan/architecture when architecture pillar is used.

### `/present` → `presentation-generation`

**Purpose:** **Render** artifact from confirmed Content Record and Intake Record.

**Does:** Audience adaptation; separate business/architecture; source fidelity; write to `nwob-docs/presentations/`.

**Does NOT:** Re-extract sources; inline collection fallback; intake interview; HTML polish (`/enrich`).

**Prerequisites:** Tiered SDD gate + confirmed Content Record + `intake-record.md`.

### `/enrich` → `presentation-enrichment`

**Purpose:** Iteratively polish existing HTML with vanilla JS/CSS interactivity.

**Prerequisites:** Path to existing HTML only. No SDD gate.

### `/deck` → Full present chain

**Purpose:** Orchestrate gated end-to-end deck creation.

**Steps:**

1. **Evaluate tier** — attempt full gate; if masterplan/architecture missing, offer partial tier with explicit user confirmation.
2. **Read** `intake-record.md` (no intake interview).
3. **`presentation-content-extraction`** (`/collect`).
4. **`presentation-generation`** (`/present`).
5. **`presentation-enrichment`** (`/enrich`, optional — **HTML only**; skip when `output_format` is Markdown).

**Does NOT:** Run initial intake; author SDD content; proceed without minimum partial gate.

---

## Skill Chain

Equivalent to `/deck`:

1. Evaluate tier + read `intake-record.md`
2. `presentation-content-extraction`
3. `presentation-generation`
4. `presentation-enrichment` (optional; HTML only)

---

## Handoff Schemas

### Intake Record

**Initial write:** `/problem` only. **Updates:** `/intake`. Path: `nwob-docs/presentations/intake-record.md`.

| Field | Values / notes |
|-------|----------------|
| `project_name` | Derived from initiative name in `/problem` |
| `mission_statement` | Derived from problem statement in `/problem` |
| `audience` | `Technical` \| `Non-technical` \| `Mixed` |
| `goal` | `Status update` \| `New initiative kickoff` \| `Architecture review` \| `Roadmap review` |
| `output_format` | `HTML` \| `Markdown` |
| `output_path` | Default: `nwob-docs/presentations/{deck-slug}.html` or `.md` |
| `source_paths` | Canonical hints (auto-populated in `/problem`) |
| `stack_override` | Optional; else resolved from sources |
| `lifecycle_override` | Optional; else default soft-delete (Default data lifecycle in constitution-core) |

### Content Record

Produced by `/collect`. Consumed by `/present`.

| Field | Values / notes |
|-------|----------------|
| `features` | Grouped by capability layer (from `epic-spec.md` backlog index + HL US/TS) |
| `roadmap` | From `epic-spec.md` ## Roadmap |
| `architecture` | From `architecture/` (full tier only; N/A for partial) |
| `sources` | Canonical path traceability only |
| `constraint_flags` | Source conflicts; `architecture: N/A` for partial tier |
| `tier` | `partial` \| `full` |

**Optional persist:** `nwob-docs/presentations/content-record.md` when user requests cross-session handoff.

---

## Content Sources

Presentations read **canonical `nwob-docs/` only** — no interview-mode authoring:

| Source | Path | Pillar |
|--------|------|--------|
| Specification | `nwob-docs/sdd/epic-spec.md` | Problem, Roadmap, metrics, backlog index, HL US/TS |
| Story delivery | `{stories_dir}/{STORY_ID}/story-tasks.md` | Delivery scope summary (full tier; when in scope) |
| Architecture | `nwob-docs/architecture/` + `nwob-docs/sdd/masterplan.md` (+ flat component plans) | Architecture truth |
| Intake | `nwob-docs/presentations/intake-record.md` | Audience, format, goal |

If sources are insufficient: stop and route to **author skill** (`/roadmap`, `/features`, SA `/c4` … `/architecture`) — not interview in `/collect`.

---

## Config File

Copy [samples/presentation.config.md](../samples/presentation.config.md) to `.cursor/presentation.config.md`. `/problem` reads it to pre-fill delivery params when creating `intake-record.md`. `/intake` may use it when updating fields.

---

## Constitution Presentation Fidelity

| Constitution Section | Presentation Behavior |
| --- | --- |
| Constitution section 1 SDD | **Required** for `/deck`, `/collect`, `/present` via tiered Presentation SDD Gate |
| Constitution section 1 Stateless K8s | State externalized to persistent stores in diagrams |
| Constitution section 2 Stack | Depict effective stack from sources |
| Constitution section 3 Coverage / Testcontainers | Reference accurately when in scope |
| Constitution section 4 Story anatomy / order | Preserve when sourced from `epic-spec.md` backlog index and `story-spec.md` |
| Constitution section 5 Data lifecycle | Reflect effective policy from sources |
| Constitution section 6 RFC 7807 | Show standard error shape when APIs in scope |

---

## Operating Rules

1. **Author vs present:** Author skills write SDD truth; present skills read and render only ([product-owner-skill-boundaries.md](product-owner-skill-boundaries.md)).
2. **Tiered SDD gate:** `/deck`, `/collect`, `/present` require partial tier minimum + `intake-record.md`; full tier for architecture pillar.
3. **Initial intake in `/problem`:** `/intake` is update-only.
4. **Dual communicator:** Distinct business narrative and architecture truth.
5. **Source fidelity:** No invention or drift from canonical sources.
6. **Audience adaptation:** Per `presentation-generation` skill.
7. **Skills over persona:** Load `SKILL.md`; do not improvise steps.
8. **Iterative polish:** `/enrich` loop for HTML until user confirms done.
