# Solution Architect Skill Boundaries

Shared segregation rules for Solution Architect skills in `skills/solution-architect/` and mirrored Lead Builder skills. Persona: [agents/solution-architect.md](../../agents/solution-architect.md). Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md). Command standards: [solution-architect-command-standards.md](solution-architect-command-standards.md). LB mirror: [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

**Reference skill mapping:** Patterns from `references/agent-skills-main` are embedded in nwob SA skills — do not invoke reference skills directly when an nwob SA skill covers the intent. Full mapping: [agent-skills-main-mapping.md](agent-skills-main-mapping.md).

**Co-equal with Lead Builder:** Solution Architect and Lead Builder are **co-equal** — full skill mirror. Both may author every SA/LB artifact, including ADR bodies and OpenAPI. `/features` and `/orchestrate-design` are available on both personas.

---

## SA author chain

```
/c4 → /pattern → /platform → /services → /contracts → /ops
```

| Command | Prerequisite |
|---------|--------------|
| `/c4` | SDD tier met; Phase 0 complete |
| `/pattern` | C4 Context + Container in `architecture.md` / `masterplan.md` |
| `/platform` | Pattern ADR **Accepted** or explicit user override |
| `/services` | Pattern ADR **Accepted** |
| `/contracts` | `/services` or monolith pattern ADR |
| `/ops` | `/services` minimum |

`/adr`, `/arc`, `/c4` alone do not require the full chain. `/architecture` runs the full chain per [solution-architect-command-standards.md](solution-architect-command-standards.md). `/orchestrate-design` and `/features` are also available on SA (mirrored with LB).

---

## Model: Design → Enable → Operate (+ mirrored LB)

| Layer | Purpose | Skills |
|-------|---------|--------|
| **0 — Product / design** | Stories; design workshop; design package | `/features`, `/orchestrate-design` (mirrored) |
| **1 — Design** | Conceptual architecture, platform, services, data, integration, resilience | `architecture-governance`, `distributed-systems-architecture` |
| **2 — Enable** | Contracts, patterns, fitness functions, catalogue | `architecture-delivery-enablement` |
| **3 — Operate** | Build-and-run, SLOs, observability, go-live | `production-operations` |
| **4 — Gate / review / audit (mirrored)** | Design-package sign-off; increment review; MR audit | `validate-design-package`, `review-implementation`, `audit-and-approve-code` |
| **Continuous** | ADRs, ARC, drift correction, deprecation decisions | `architecture-governance` |

**Rule:** SA native skills do **not** implement application code, pipeline YAML, or UI components. SA **persona** authors `epic-spec.md` by invoking bundled PO author skills or `/define` (`architect-led-sdd-intake`). SA **may consolidate** design package via `/orchestrate-design` (co-equal with LB). SA **may author** ADR bodies and OpenAPI (co-equal with LB — not exclusive). Dual-persist `architecture.md` ↔ `masterplan.md` only; flat `sdd/components/{component-name}-plan.md` derived from `epic-spec.md`.

---

## Engagement modes

SA work runs in one of two modes depending on workflow step. Step 2 output is **provisional** until design-package mode reconciles during steps 8–9.

| Mode | When (workflow step) | Prerequisites | Scope |
|------|---------------------|---------------|-------|
| **Conceptual** | Step 2 — after problem/roadmap defined | `nwob-docs/sdd/epic-spec.md` (Problem + Solutions/Roadmap preferred) | High-level `architecture.md` ↔ `masterplan.md`, platform direction, early ADRs; ARC intake when applicable |
| **Design-package** | Steps 8–9 — inside `/orchestrate-design` (SA or LB) | `epic-spec.md` + draft in-scope `story-spec.md` / `story-tasks.md` | Full contracts, sequence diagrams, fitness functions, go-live alignment; reconcile or extend step 2 output |

ARC intake may use problem statement + ADRs without full SDD. Design-package mode requires `epic-spec.md` and in-scope `story-spec.md` / `story-tasks.md`; conceptual mode requires `epic-spec.md` only.

---

## Orchestration

For full architecture engagements (`/architecture`), apply in this order within the active mode:

1. **`/c4`** (`architecture-governance`) — C4 Context + Container first (technology-agnostic); dual-persist `masterplan.md`
2. **`/pattern`** (`architecture-governance`) — pattern-selection ADR with ≥2 options
3. **`/platform`** (`distributed-systems-architecture`) — platform/MVP, `network.md`; **defaults** AWS/EKS
4. **`/services`** (`distributed-systems-architecture`) — services, data, integration; **defaults** EDA/Kafka; flat `sdd/components/{component-name}-plan.md`
5. **`/contracts`** (`architecture-delivery-enablement`) — contracts, patterns, fitness, catalogue (OpenAPI allowed)
6. **`/ops`** (`production-operations`) — SLAs, observability, production readiness
7. **`architecture-governance`** — **continuous** throughout (material ADRs, ARC, drift)

Skip or reorder based on task scope. A single command suffices for narrow requests (e.g. `/c4` only, `/adr` only). Design workshop and story indexing: `/orchestrate-design`. Net-new stories: `/features`.

---

## Canonical source map

| Content pillar | Authoritative source | Author command / skill | Read by |
|----------------|---------------------|------------------------|---------|
| C4 Context + Container | `architecture.md` ↔ `masterplan.md` (System Context, Container View) | `/c4` → `architecture-governance` | `/pattern`; PO `presentation-content-extraction` |
| Data Flow Diagram | `architecture.md` ↔ `masterplan.md` (derived from Container View) | `/services` → `distributed-systems-architecture` | PO `presentation-content-extraction` |
| Data Models | `architecture.md` ↔ `masterplan.md` (Conceptual, Logical, Physical) | `/services` → `distributed-systems-architecture` | `/orchestrate-design`; Builder build gates |
| Pattern-selection ADR | `adr/ADR-NNN-architectural-pattern-selection.md` | `/pattern` → `architecture-governance` (SA **or** LB) | `/platform`, `/services` |
| System architecture / masterplan | `architecture.md` ↔ `sdd/masterplan.md` | `/c4`, `/platform`, `/services`, `/orchestrate-design` (SA **or** LB) | Design package; PO presentation |
| Component spec / plan | flat `nwob-docs/sdd/components/{component-name}-plan.md` | `/services`, `/ops`, `/orchestrate-design` (SA **or** LB) | Design package; Builder |
| Network / infra | `nwob-docs/architecture/network.md` | `distributed-systems-architecture`, `production-operations` | Design package; PO presentation |
| ADRs | `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md` | `architecture-governance` (SA **or** LB) | All SA/LB skills; ARC register |
| Sequence diagrams | `nwob-docs/diagrams/sequences/{service-name}.md` | SA/LB skills | Design package |
| Service map | `nwob-docs/architecture/service-map.md` | `/services`, `/contracts` | Design package; Builder build gates |
| OpenAPI specs | `repositories/{service-name}/src/main/resources/swagger/` | `/contracts` (SA **or** LB) | Builder review/audit |
| Service catalogue | Rows in `service-map.md` + pattern library | `architecture-delivery-enablement` | `architecture-governance` (ARC register link) |
| Specification | `nwob-docs/sdd/epic-spec.md` | Product Owner **or** SA **or** LB — `/define`, `/problem` … `/roadmap` | SA/LB native skills read constraints |
| Backlog index / HL US/TS | `nwob-docs/sdd/epic-spec.md` | Product Owner **or** SA **or** LB — `/define`, `/features`, `/backlog` | SA/LB native skills read constraints |
| Story task bodies | `{stories_dir}/{STORY_ID}/story-tasks.md` (prompt `tasks.md` → this path) | Builder — `co-design-solution`; SA/LB co-author | SA/LB read; validate gates |

---

## Cross-persona boundaries

### SA vs Product Owner

| SA | PO |
|----|-----|
| SA native skills read `epic-spec.md` for constraints | Also authors `epic-spec.md` when PO persona active |
| SA persona authors `epic-spec.md` via `/define` or PO author skills | Primary owner for presentation chain (`/deck`) and `/backlog` |
| Writes `nwob-docs/architecture/` + dual `sdd/masterplan.md` + `sdd/components/` | Writes `nwob-docs/presentations/` (full deck chain) |
| `/features` also on SA (co-equal with LB) | Owns story anatomy via `feature-definition` (invoked by SA, LB, or PO) |

### SA vs Lead Builder (co-equal)

| Concern | Solution Architect | Lead Builder |
|---------|-------------------|--------------|
| Architecture, ADRs, OpenAPI, masterplan, components | Full author (co-equal) | Full author (co-equal) |
| `/features`, `/orchestrate-design` | Available | Available |
| Design package consolidation / design package | Via `/orchestrate-design` | Via `/orchestrate-design` |
| Increment review / MR audit | Mirrored skills available | Primary cadence for build gates |
| Application code | Must not implement | Must not implement (Builder owns) |

### SA vs Lead Builder vs Builder

| Concern | Solution Architect / Lead Builder | Builder |
|---------|-----------------------------------|---------|
| API contracts, security boundaries, SLO targets | Defines (either persona) | Verifies implementation matches |
| CI gate definitions (coverage, ArchUnit) | Specifies thresholds | Verifies gates pass in review/audit |
| Application code, handlers, UI | Must not implement | Directs AI via `trigger-ai-build` |
| Performance budgets and caching strategy | Sets budgets | Profiles and validates fixes at code level |
| Auth middleware, validation, parameterized queries | Defines auth boundary | Verifies controls in review/audit |

---

## Intent → command / skill routing

| Intent | Command / Skill |
|--------|-----------------|
| Architect-led SDD bootstrap | `/define` → `architect-led-sdd-intake` |
| Problem / solutions / roadmap / stories (incremental) | `/problem`, `/ideate`, `/roadmap`, `/features` → PO author skills |
| Design workshop; design package | `/orchestrate-design` → `orchestrate-design` |
| Update presentation delivery params | `/intake` → `presentation-intake-update` |
| C4 Context + Container diagrams | `/c4` → `architecture-governance` |
| Architectural pattern options ADR | `/pattern` → `architecture-governance` |
| Cloud platform / MVP / network | `/platform` → `distributed-systems-architecture` |
| Services / data / events / resilience | `/services` → `distributed-systems-architecture` |
| OpenAPI / patterns / fitness / catalogue | `/contracts` → `architecture-delivery-enablement` |
| SLOs / on-call / go-live / observability | `/ops` → `production-operations` |
| Material ADR (any topic) | `/adr` → `architecture-governance` |
| ARC submission | `/arc` → `architecture-governance` |
| Full architecture engagement | `/architecture` → full chain per command-standards |
| Design-package build-readiness | `validate-design-package` (mirrored) |
| Increment / MR audit | `review-implementation`, `/audit` (mirrored) |

---

## Per-skill boundaries

| Skill | Writes | Must NOT |
|-------|--------|----------|
| `architecture-governance` | `architecture.md` ↔ `masterplan.md` (C4), ADRs, ARC records | Implement application auth; write pipeline YAML; name tech in `/c4`; skip dual-persist |
| `distributed-systems-architecture` | `architecture.md` ↔ `masterplan.md` (Data Flow, Data Models, State Machine, platform/service/data sections), `sdd/components/` twins, `network.md`, store ADRs (via governance) | Define CI pipeline; frontend design; write new files under legacy `architecture/components/` |
| `architecture-delivery-enablement` | Pattern library, fitness definitions, catalogue entries, OpenAPI | Write pipeline implementation; frontend components |
| `production-operations` | SLOs, runbook outlines, observability config in `network.md`; runtime DB Maintenance in `architecture.md`/`masterplan.md` and owning component twins | Code-level performance fixes; incident postmortem authorship |
| `orchestrate-design` (mirrored) | Thin per-story `story-tasks.md` (order from epic-spec); design package; dual-persist architecture/components as needed | Author application code; skip dual-persist |

**Co-authors:** Lead Builder is **co-equal** (not secondary) for `architecture.md` ↔ `masterplan.md`, `sdd/components/**`, ADR bodies, and OpenAPI. Pod Builder **MUST NOT** author those architecture artifacts.

---

## `architecture.md` / `masterplan.md` section ownership

| Section / topic | Primary command / skill |
|-----------------|---------------------------|
| System Context, Container View (C4) | `/c4` → `architecture-governance` |
| Data Flow Diagram (Container topology, payload labels) | `/services` → `distributed-systems-architecture` |
| Data Models (Conceptual / Logical / Physical) | `/services` → `distributed-systems-architecture` |
| State Machine | `/services` → `distributed-systems-architecture` |
| DB Maintenance & Operation (design-time) | `/services` → `distributed-systems-architecture` |
| DB Maintenance & Operation (runtime) | `/ops` → `production-operations` |
| Platform, EKS/IAM, network isolation | `/platform` → `distributed-systems-architecture` |
| Service boundaries, events, data stores, resilience | `/services` → `distributed-systems-architecture` |
| API contracts, patterns, fitness function refs | `/contracts` → `architecture-delivery-enablement` |
| SLOs, observability, runbook links | `/ops` → `production-operations` |
| ADR references and decision log pointers | `/pattern`, `/adr` → `architecture-governance` |

### `{component-name}-plan.md` (component-scoped)

Path: flat `nwob-docs/sdd/components/{component-name}-plan.md`. Uses the same H2/H3 set as `architecture.md` / `masterplan.md`, scoped to one C4 container. Primary: `/services` (design-time) and `/ops` (runtime DB when the component owns a store). Authors: SA **or** LB. Must link and complement system SoT. Legacy `nwob-docs/architecture/components/` is **read-only brownfield fallback** — do not write new files there.

---

## Cross-skill content ownership

| Topic | Primary owner | Secondary |
|-------|---------------|-----------|
| ADR lifecycle (proposed → superseded) | `architecture-governance` (SA **or** LB) | distributed: raise ADR when material |
| API contract-first, RFC 7807, pagination | `architecture-delivery-enablement` | distributed: boundary triggers |
| Hyrum's Law, deprecation policy | `architecture-delivery-enablement` | governance: compulsory vs advisory ADR |
| Event schema versioning, strangler | `distributed-systems-architecture` | governance: migration ADRs |
| SLOs, error budgets, go-live | `production-operations` | delivery: latency fitness functions |
| IAM, network isolation, secrets | `distributed-systems-architecture` | — |
| Soft-delete entity baseline | `distributed-systems-architecture` | delivery: pattern library link |
| Fitness functions (ArchUnit, JaCoCo, Sonar) | `architecture-delivery-enablement` | production: latency/error regression |
| Service catalogue | `architecture-delivery-enablement` | governance: ARC register; production: runbook links |

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "Skip `/c4` because we know it's EKS" | Run `/c4` first; technology-agnostic Context + Container |
| "Skip `/pattern` — org defaults are obvious" | Run `/pattern`; document alternatives even when accepting defaults |
| "Use reference `spec-driven-development` for architecture" | SA persona runs `/define` or PO author skills; SA native skills read constraints |
| "Switch to PO persona when epic-spec.md missing" | Run `/define` or `/problem` under SA persona |
| "Use reference `documentation-and-adrs` directly" | Run `architecture-governance`; patterns embedded |
| "Use reference `api-and-interface-design` for REST design" | Run `architecture-delivery-enablement` + `distributed-systems-architecture` |
| "Implement helmet/JWT middleware in SA skill" | SA/LB defines auth boundary; Builder `trigger-ai-build` directs implementation |
| "Write GitHub Actions in SA skill" | SA/LB defines fitness thresholds; Builder `trigger-ai-build` authors pipeline |
| "Store ADRs in `docs/adr/`" | Use `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md` |
| "ARC requires `epic-spec.md`" | ARC intake uses problem statement + ADRs; full SDD via `/define` or PO chain |
| "Frontend patterns belong in SA" | Builder `trigger-ai-build`; SA/LB defines BFF/API contracts only |
| "Profile and fix React re-renders in SA" | SA/LB sets SLO/budget; Builder `trigger-ai-build` directs fixes |
| "Only SA may write ADRs or OpenAPI" | SA and LB are co-equal authors |
| "Write component-spec under architecture/components/" | Write flat `nwob-docs/sdd/components/{component-name}-plan.md` only |
| "Update architecture.md without masterplan.md" | Dual-persist both twins on every write |

---

## Material vs minor changes

| Change type | Required action |
|-------------|-----------------|
| **Material** — new service, store override, security boundary, breaking API | ADR + ARC before BRC |
| **Minor** — pattern library tweak, fitness threshold adjustment | Update pattern/changelog; no ARC unless drift detected |
