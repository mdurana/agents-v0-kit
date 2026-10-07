# Solution Architect Command Standards

Shared rules for Solution Architect slash commands (mirrored on Lead Builder for co-equal SA/LB authorship). Skills in `skills/solution-architect/` invoke this reference. Skill boundaries: [solution-architect-skill-boundaries.md](solution-architect-skill-boundaries.md). Persona: [agents/solution-architect.md](../../agents/solution-architect.md). LB mirror: [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

---

## Role Scope

Solution Architect commands (and the same commands when Lead Builder is active) produce **architecture truth** under dual-persist paths:

- **System SoT** — `nwob-docs/architecture/architecture.md` ↔ `nwob-docs/sdd/masterplan.md` (same body).
- **Per-container** — flat `nwob-docs/sdd/components/{component-name}-plan.md`.
- **C4 diagrams** — Context and Container views before platform commitment.
- **Pattern-selection ADR** — ≥2 architectural options before `/platform` and `/services`.
- **Platform, services, contracts, operations** — defaults to AWS/EKS and event-driven microservices unless ADR or sources override.

SA/LB commands **read** SDD artifacts for constraints when executing architecture work. SA **persona** may **author** `epic-spec.md` via `/define` or bundled PO author skills (`/problem` … `/features`). `/features` and `/orchestrate-design` are available on **both** SA and LB. SA/LB may consolidate design package via `/orchestrate-design`. ADR bodies and OpenAPI are **SA ∨ LB** (not exclusive). Prompt references to `tasks.md` **map to** `story-tasks.md`.

---

## SA Author Chain

```
/c4 → /pattern → /platform → /services → /contracts → /ops
```

Each command stops if prerequisites are missing and redirects to the owning command.

| Command | Skill | Prerequisite | Primary output |
|---------|-------|--------------|----------------|
| `/define` | `architect-led-sdd-intake` | Phase 0 complete | `epic-spec.md` + initial `intake-record.md` |
| `/problem` | `business-problem-identification` | Phase 0 complete | `epic-spec.md` Problem/Context + Metrics; initial `intake-record.md` |
| `/ideate` | `product-ideation` | Problem/Context in `epic-spec.md` | Solutions/Hypotheses in `epic-spec.md` |
| `/roadmap` | `product-roadmap-creation` | ## Solutions in `epic-spec.md` | ## Roadmap in `epic-spec.md` |
| `/features` | `feature-definition` | ## Roadmap in `epic-spec.md` | Backlog index + `story-spec.md` — also on LB |
| `/orchestrate-design` | `orchestrate-design` | Stories selected / design workshop | Design package; may dual-persist architecture — also on LB |
| `/intake` | `presentation-intake-update` | `intake-record.md` exists | Updated delivery params |
| `/c4` | `architecture-governance` | SDD tier met; Phase 0 complete | C4 L1+L2 in `architecture.md` ↔ `masterplan.md` |
| `/pattern` | `architecture-governance` | C4 Context + Container in system SoT | `ADR-NNN-architectural-pattern-selection.md` |
| `/platform` | `distributed-systems-architecture` | Pattern ADR **Accepted** or explicit user override | `architecture.md` ↔ `masterplan.md`, `network.md` |
| `/services` | `distributed-systems-architecture` | Pattern ADR **Accepted** | Services/integration in system SoT; flat `sdd/components/{component-name}-plan.md` |
| `/contracts` | `architecture-delivery-enablement` | `/services` or monolith pattern ADR | Contracts, fitness, catalogue, OpenAPI |
| `/ops` | `production-operations` | `/services` minimum | SLOs, observability, readiness |
| `/adr` | `architecture-governance` | Material decision | Any ADR (SA **or** LB) |
| `/arc` | `architecture-governance` | Problem statement + ADRs + diagrams | ARC package |
| `/architecture` | Full chain | SDD tier per mode | Complete `architecture/` tree + dual `masterplan.md` + `sdd/components/` |

**Narrow commands:** `/adr`, `/arc`, `/c4` do not require the full chain.

**Explicit override:** User may skip `/pattern` in the current thread with explicit instruction (e.g. "accept org defaults, proceed to platform"). Document override in `architecture.md` / `masterplan.md` Key Decisions.

---

## SDD Gate Tiers

| Tier | When | SDD requirement | Commands affected |
|------|------|-----------------|-------------------|
| **ARC intake** | `/arc` only | None | `/arc`, `/adr`, `/c4` (diagrams for ARC) |
| **Conceptual** | Workflow step 2 | `epic-spec.md` (Problem + Solutions/Roadmap preferred) | `/c4` through `/ops`; output provisional |
| **Design-package** | Steps 8–9 in `/orchestrate-design` (SA or LB) | `epic-spec.md` + draft in-scope `story-spec.md` / `story-tasks.md` | Reconcile/extend conceptual output |
| **Full SA** | Standalone `/architecture` | `epic-spec.md` + derived masterplan/components (+ in-scope `story-tasks.md` when in scope) | Full chain |

**Gate failure:** Stop; list missing artifacts and owning command (e.g. `epic-spec.md` → `/define` or `/problem`; backlog index → `/define` or `/features`).

---

## `/architecture` Orchestration

1. Phase 0 discovery per [sdd-artifact-layout.md](sdd-artifact-layout.md).
2. Evaluate SDD tier; stop if gate fails.
3. Run `/c4` → `/pattern` → `/platform` → `/services` → `/contracts` → `/ops` in sequence.
4. Confirm `architecture.md` / `masterplan.md` data sections populated by `/services` and `/ops`: **Data Flow Diagram**, **Data Models** (logical + physical `erDiagram` required), **State Machine**, **DB Maintenance & Operation** — or documented N/A with rationale.
5. `architecture-governance` runs continuously — raise material ADRs; schedule `/arc` before BRC when needed.
6. Persist all outputs under dual-persist system paths (`architecture.md` ↔ `masterplan.md`) and flat `sdd/components/{component-name}-plan.md`; chat is supplementary.

Stop at first failed prerequisite; name the redirect command.

---

## Command Details

### `/c4` → `architecture-governance`

**Purpose:** C4 Context + Container diagrams only (technology-agnostic first pass).

**Does:** Populate **System Context** and **Container View** in `architecture.md` with Mermaid C4-style flowcharts (`flowchart TB` + `subgraph`); dual-persist the same body to `nwob-docs/sdd/masterplan.md`.

**Does NOT:** Commit to EKS, Kafka, or specific stores (unless user explicitly requests in current thread).

**Suggested next:** `/pattern`

### `/pattern` → `architecture-governance`

**Purpose:** Architectural pattern-selection ADR with ≥2 options.

**Does:** Write `ADR-NNN-architectural-pattern-selection.md` with options table; link from `architecture.md` / `masterplan.md`. SA **or** LB may author.

**Does NOT:** Proceed to platform/service design without accepted ADR (unless explicit override).

**Suggested next:** `/platform` and `/services` (order: platform then services per author chain)

### `/platform` → `distributed-systems-architecture`

**Purpose:** Platform deep-dive per accepted pattern ADR.

**Does:** MVP, security, trade-offs, `network.md` (Mermaid `flowchart LR` topology); **defaults** AWS/EKS; dual-persist system SoT updates.

**Does NOT:** Run without C4 or pattern ADR (unless override).

**Suggested next:** `/services`

### `/services` → `distributed-systems-architecture`

**Purpose:** Service topology, integration, data, resilience.

**Does:** Update `architecture.md` ↔ `masterplan.md` with **Data Flow Diagram** (Container topology, payload edge labels), **Data Models** (Conceptual / Logical / Physical — logical + physical **mandatory** Mermaid `erDiagram`; physical includes per-field types), **State Machine**, design-time **DB Maintenance & Operation** subsections; lazy-create and fill flat `nwob-docs/sdd/components/{component-name}-plan.md` per in-scope container (same section set; complements system SoT); Mermaid `sequenceDiagram` at `nwob-docs/diagrams/sequences/`; **defaults** event-driven microservices/Kafka.

**Does NOT:** Decompose without pattern ADR justification. Write new component files under legacy `nwob-docs/architecture/components/` (read-only brownfield fallback for readers only).

**Co-equal authors:** Lead Builder may create/update the same paths via `/orchestrate-design` or mirrored SA commands. ADR bodies and OpenAPI are SA **or** LB.

**Suggested next:** `/contracts`

### `/contracts` → `architecture-delivery-enablement`

**Purpose:** Contracts, patterns, fitness functions, catalogue.

**Does:** Persist OpenAPI 3.0 specs to `repositories/{service-name}/src/main/resources/swagger/`; update `service-map.md` (link `sdd/components/`). SA **or** LB may author OpenAPI.

**Suggested next:** `/ops`

### `/ops` → `production-operations`

**Purpose:** SLOs, observability, production readiness for effective platform. Mermaid observability topology in `network.md` when non-trivial. Completes runtime **DB Maintenance & Operation** subsections (Backup & Recovery, Performance Maintenance, Monitoring & Runbooks) in `architecture.md` ↔ `masterplan.md` and in owning flat `{component-name}-plan.md` when a component owns a store.

### `/adr` → `architecture-governance`

**Purpose:** Any material ADR (not limited to pattern selection). SA **or** LB may author.

### `/arc` → `architecture-governance`

**Purpose:** ARC intake and review documentation. No full SDD required.

### `/features` → `feature-definition`

**Purpose:** Net-new stories + Gherkin AC. Available on SA and LB (and PO).

### `/orchestrate-design` → `orchestrate-design`

**Purpose:** Design workshop, design package, design package consolidation. Available on SA and LB. May dual-persist architecture/components when design requires.

---

## Artifact Paths

| Artifact | Path | Produced by |
|----------|------|-------------|
| Architecture overview | `nwob-docs/architecture/architecture.md` | `/c4`, `/platform`, `/services`, `/ops`, `/architecture`, `/orchestrate-design` (SA **or** LB) |
| Masterplan (dual twin) | `nwob-docs/sdd/masterplan.md` | Same commands — dual-persist with `architecture.md` |
| Component plan (flat) | `nwob-docs/sdd/components/{component-name}-plan.md` | `/services` (primary); `/ops` runtime DB; `/orchestrate-design` (SA **or** LB) |
| Legacy component path | `nwob-docs/architecture/components/` | **Read-only** brownfield fallback — do not write new files |
| Network topology | `nwob-docs/architecture/network.md` | `/platform`, `/ops` |
| Pattern-selection ADR | `nwob-docs/architecture/adr/ADR-NNN-architectural-pattern-selection.md` | `/pattern` (SA **or** LB) |
| Other ADRs | `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md` | `/adr`, `/pattern` (SA **or** LB) |
| Sequence diagrams (Mermaid) | `nwob-docs/diagrams/sequences/{service-name}.md` | `/services` |
| Service map | `nwob-docs/architecture/service-map.md` | `/services`, `/contracts` |
| OpenAPI specs | `repositories/{service-name}/src/main/resources/swagger/{spec-file}.yaml` | `/contracts` (SA **or** LB) |
| Code workspace | `repositories/` | Prompter (submodules); init + `nwob doctor` |

Scaffolds: `.nwob/templates/sa/architecture-outline.md`, `sa/component-plan-template.md`, `sa/adr-template.md`, `sa/service-map-template.md` when files missing (flat component plans are lazy-created under `sdd/components/` — not blank-scaffolded at init).

---

## Anti-Rationalizations

| Excuse | Correct action |
|--------|----------------|
| "Skip `/c4` — we know it's EKS" | Run `/c4`; technology-agnostic Context + Container first |
| "Skip `/pattern` — org defaults are obvious" | Run `/pattern`; document alternatives even when accepting defaults |
| "`/platform` before pattern ADR" | Stop; redirect to `/pattern` unless explicit override |
| "Store architecture in `docs/`" | Use `nwob-docs/architecture/` + dual `sdd/masterplan.md` |
| "ARC requires `epic-spec.md`" | ARC intake uses problem statement + ADRs + diagrams |
| "Implement auth middleware in `/platform`" | SA/LB defines boundaries; Builder implements |
| "Only SA may write OpenAPI or ADRs" | SA and LB are co-equal authors |
| "Write components under architecture/components/" | Write under `nwob-docs/sdd/components/`; dual-persist plan twin |
| "Update architecture.md without masterplan.md" | Dual-persist both twins on every write |

---

## Cross-References

- Engagement modes: [solution-architect-skill-boundaries.md#engagement-modes](solution-architect-skill-boundaries.md#engagement-modes)
- PO SDD chain: [product-owner-skill-boundaries.md](product-owner-skill-boundaries.md)
- Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md)
