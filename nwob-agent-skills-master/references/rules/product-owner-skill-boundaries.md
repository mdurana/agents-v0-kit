# Product Owner Skill Boundaries

Shared segregation rules for Product Owner skills in `skills/product-owner/`. Persona: [agents/product-owner.md](../../agents/product-owner.md). Presentation handoffs: [presentation-standards.md](presentation-standards.md).

**Cross-persona note:** When the Solution Architect persona is active, bundled PO author skills (`/define`, `/problem` … `/features`, `/intake`) may be invoked by SA without switching persona. Skill procedures and artifact ownership rules below apply unchanged — only the invoking persona differs.

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

**Reference skill mapping:** Patterns from `interview-me` and `idea-refine` in [references/agent-skills-main](../agent-skills-main/) are embedded in `/problem` and `/ideate` — do not invoke reference skills directly. Full mapping: [agent-skills-main-mapping.md](agent-skills-main-mapping.md).

---

## Model: Author → Configure → Extract → Render

| Layer | Purpose | Skills |
|-------|---------|--------|
| **1 — Author** | Define authoritative SDD and process content | `business-problem-identification`, `product-ideation`, `product-roadmap-creation`, `feature-definition`, `backlog-management-and-refinement`, `value-stream-mapping` |
| **2 — Configure** | Update presentation delivery parameters only | `presentation-intake-update` |
| **3 — Present** | Read canonical sources → render → polish | `presentation-content-extraction`, `presentation-generation`, `presentation-enrichment` |

**Rule:** No skill may both **author** and **extract** the same content pillar (Features, Roadmap, Architecture).

---

## SDD author chain and gates

Author skills run in this order. Each skill stops if its prerequisite is missing and names the owning command.

```
/problem → /ideate → /roadmap → /features → /backlog
   ↓          ↓          ↓           ↓
epic-spec.md   Solutions   Roadmap    backlog index + HL US/TS
                                      + stories/{ID}/story-spec.md
```

| Skill | Prerequisite | Stop → redirect |
|-------|--------------|-----------------|
| `/ideate` | Problem/Context in `epic-spec.md` | → `/problem` |
| `/roadmap` | `## Solutions` (or `## Solutions / Hypotheses`) in `epic-spec.md` | → `/ideate` |
| `/features` | `## Roadmap` in `epic-spec.md` | → `/roadmap` |
| `/backlog` | At least one story in `epic-spec.md` backlog index with linked `story-spec.md` | → `/features` |

---

## Canonical source map

| Content pillar | Authoritative source | Author skill | Extracted by |
|----------------|---------------------|--------------|--------------|
| Problem, mission, metrics | `nwob-docs/sdd/epic-spec.md` | `/problem` | `presentation-content-extraction` |
| Solutions / hypotheses | `nwob-docs/sdd/epic-spec.md` | `/ideate` | — |
| Roadmap themes | `nwob-docs/sdd/epic-spec.md` ## Roadmap | `/roadmap` | `presentation-content-extraction` |
| Features / stories | `nwob-docs/sdd/epic-spec.md` (backlog index + HL US/TS) + `stories/{STORY_ID}/story-spec.md` | `/features`, `/backlog` | `presentation-content-extraction` |
| Jira export params / tickets CSV | `tickets-export-params.md`; `tickets.csv` at configured path | `/backlog` | — (not a presentation pillar) |
| Delivery scope | Per-story `story-tasks.md` (order from epic-spec backlog index) | Builder `co-design-solution`; SA/LB `/orchestrate-design` (design package) | `presentation-content-extraction` (full tier only) |
| Architecture | `nwob-docs/architecture/` | Solution Architect (`/c4` … `/architecture`) | `presentation-content-extraction` (full tier only) |
| Audience, goal, format | `nwob-docs/presentations/intake-record.md` | `/problem` (initial), `/intake` (update) | `presentation-generation` |
| Deck artifact | `nwob-docs/presentations/` | — | `presentation-generation`, `presentation-enrichment` |

`mission_statement` in `intake-record.md` is **derived from** the problem statement during `/problem` — not independently authored in `/intake`.

### Metrics lifecycle

- **Author:** `/problem` creates Metrics in `epic-spec.md`.
- **Refine:** `/ideate` and `/roadmap` may update success metrics when solutions or themes change how success is measured.
- **Re-author substance:** If mission or problem framing shifts → re-run `/problem` (not `/intake`).

---

## `/features` vs `/backlog` decision table

Both extend `nwob-docs/sdd/epic-spec.md` (backlog index) and write `{stories_dir}/{STORY_ID}/story-spec.md`. `/backlog` also owns Jira export params and `tickets.csv`. Use this table to choose the command.

| Situation | Owner | Examples |
|-----------|-------|----------|
| Net-new epic/story from roadmap theme | `/features` | First story for a Now theme |
| Re-prioritize (MoSCoW, cost of delay, Kano) | `/backlog` | Reorder top 10 items |
| Fix DoR gaps on existing story (AC, size, deps) | `/backlog` | Numbered AC rewrite, 8→3 SP split |
| Decompose oversized story already in plan | `/backlog` | 8 SP → two 3 SP stories |
| New story from grooming — new capability | `/features` | Emergent feature not in roadmap |
| New story from grooming — defect/tech-debt | `/backlog` | Bug fix, tech-debt item |
| Prune/archive stale items | `/backlog` only | — |
| Emit / refresh Jira `tickets.csv` | `/backlog` only | Ask or load `tickets-export-params.md`; write CSV |

### Shared story standards (both `/features` and `/backlog`)

- **Fibonacci sizing** only (1, 2, 3, 5, 8…).
- **5-point cap:** stories ≥ 5 SP must be decomposed into 2/3 SP increments where logically possible.
- **Numbered Gherkin AC:** `1. **Scenario:**` with `a.` Given / `b.` When / `c.` Then — no vague bullet points.
- **Description bullet list:** Scope In/Out, Pre-conditions, Dependencies, Size, Risks, Environment, Automation, Desk check (+ conditional API/UI/UX) per feature-definition.
- **US Readiness Rubric:** applicable rows must pass before READY / export.
- **Chronological order:** foundation/infra before UI/features in `epic-spec.md` backlog index.
- **All 6 story fields** per Planning and story anatomy in constitution-core: Type, Summary, Description, AC, Dependencies, Size.
- **Jira CSV:** schema in feature-definition; emit only via `/backlog` using `tickets-export-params.md` (never hardcode import constants in skills).

---

## Per-skill boundaries

### Layer 1 — Author

| Skill | Command | Writes | Must NOT |
|-------|---------|--------|----------|
| `business-problem-identification` | `/problem` | `epic-spec.md` Problem/Context + Metrics; **initial** `intake-record.md` | Extract pillars; generate deck |
| `product-ideation` | `/ideate` | `epic-spec.md` Solutions/Hypotheses (+ Assumptions, Not Doing per hypothesis) | `docs/ideas/` one-pagers; presentation formatting |
| `product-roadmap-creation` | `/roadmap` | `epic-spec.md` ## Roadmap | Edit backlog index outside `/features`/`/backlog`; leader-facing deck layout |
| `feature-definition` | `/features` | `epic-spec.md` backlog index + HL US/TS; net-new `story-spec.md`; documents CSV export contract | Implementation tasks (`story-tasks.md`); capability-layer deck grouping; `tickets.csv` emit; Jira constants |
| `backlog-management-and-refinement` | `/backlog` | `epic-spec.md` backlog index refinements; `tickets-export-params.md`; `tickets.csv` (at configured path) | Net-new epics from roadmap (→ `/features`); presentation content |
| `value-stream-mapping` | `/value` | `nwob-docs/process/{YYYY-MM-DD}-value-stream-{slug}.md` | SDD or presentation content; `observations/` |

### Layer 2 — Configure

| Skill | Command | Writes | Must NOT |
|-------|---------|--------|----------|
| `presentation-intake-update` | `/intake` | `intake-record.md` delivery param updates | Initial intake; problem analysis; content extraction |

### Layer 3 — Present

| Skill | Command | Reads | Must NOT |
|-------|---------|-------|----------|
| `presentation-content-extraction` | `/collect` | Canonical `nwob-docs/` → Content Record | Interview authoring; write SDD; set audience/format |
| `presentation-generation` | `/present` | Content Record + Intake Record → artifact | Re-extract; change SDD substance |
| `presentation-enrichment` | `/enrich` | Existing HTML | Change sourced facts; intake or extraction |

---

## Tiered presentation SDD gate

Required before `/deck`, `/collect`, or `/present` (not `/enrich`).

### Partial tier (product narrative)

| File | Minimum bar |
|------|-------------|
| `nwob-docs/sdd/epic-spec.md` | Non-empty Problem/Context + `## Roadmap` + at least one backlog index row |
| `nwob-docs/presentations/intake-record.md` | Exists (from `/problem`) |

**Pillars:** Features, Roadmap. Architecture = N/A (`constraint_flags.architecture = N/A`).

**Use when:** Early stakeholder alignment; pre–Lead Builder; masterplan/architecture not yet available.

### Full tier (leader + architecture)

Partial tier **plus:**

| File | Minimum bar |
|------|-------------|
| `nwob-docs/sdd/masterplan.md` and/or `nwob-docs/architecture/architecture.md` | Exists when architecture pillar is requested |
| Flat `nwob-docs/sdd/components/{component-name}-plan.md` | When component pillar is requested |

**Pillars:** Features, Roadmap, Architecture (all three).

**Use when:** Leader-facing technical deck; default for `/deck` when SA artifacts exist.

### Gate failure behavior

- Stop; list missing artifacts and owning step (e.g. `story-tasks.md` → `co-design-solution`; architecture → SA `/c4` … `/architecture`).
- `/deck`: attempt full tier first; if masterplan/architecture missing, offer partial tier with **explicit user confirmation**.
- Never interview in `/collect` to fill gaps.

---

## Content Record handoff

| Mode | Path | When |
|------|------|------|
| Default | In-memory between `/collect` and `/present` | Same session |
| Optional persist | `nwob-docs/presentations/content-record.md` | User requests persistence across sessions |

---

## `/deck` chain

1. Evaluate presentation tier (full first; offer partial if incomplete)
2. Read `intake-record.md` (no interview)
3. `presentation-content-extraction` (`/collect`)
4. `presentation-generation` (`/present`)
5. `presentation-enrichment` (`/enrich`, optional — **HTML only**; skip when `output_format` is Markdown)

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "Spec is thin—interview in `/collect` for roadmap" | Run `/roadmap` to author `epic-spec.md` ## Roadmap |
| "No architecture—describe zones in `/collect`" | Run SA commands (`/c4` … `/architecture`), or use partial tier |
| "Skip `/problem` intake—run `/intake` first" | `/problem` is sole initial writer of `intake-record.md` |
| "Render without `/collect`—paste content inline" | Run `/collect` to extract from canonical sources |
| "Update mission in `/intake`" | Substance change → `/problem`; `/intake` updates delivery params only |
| "Format roadmap for executives in `/roadmap`" | Author themes in `epic-spec.md`; `/present` renders for audience |
| "Use reference `idea-refine` for ideation" | Run `/ideate`; frameworks in [ideation-frameworks.md](ideation-frameworks.md) |
| "Use reference `interview-me` as separate skill" | Phase 0 in `/problem`; patterns in [intent-interview-patterns.md](intent-interview-patterns.md) |
| "Write implementation tasks in `/features`" | Product stories in `epic-spec.md` backlog index; tasks → `co-design-solution` / SA/LB `/orchestrate-design` |
| "New epic during grooming—use `/backlog`" | New capability → `/features`; defect/tech-debt → `/backlog` |
| "Emit tickets.csv from `/features` with hardcoded GBox/TRIBE" | `/backlog` asks or loads `tickets-export-params.md`, then emits CSV |

---

## `epic-spec.md` section contract

| Section | Owner command | Notes |
|---------|---------------|-------|
| Problem/Context | `/problem` | |
| Metrics | `/problem` (refine in `/ideate`, `/roadmap`) | |
| Solutions / Hypotheses | `/ideate` | Include Key Assumptions + Not Doing per hypothesis |
| Roadmap (Now/Next/Later) | `/roadmap` | |
| High-level US/TS + chronological backlog index | `/features`, `/backlog` | Links to `{stories_dir}/{STORY_ID}/story-spec.md` |

Detailed stories: backlog index in `epic-spec.md` + `{stories_dir}/{STORY_ID}/story-spec.md` via `/features` and `/backlog`. Jira import: `tickets-export-params.md` + `tickets.csv` via `/backlog` only.
