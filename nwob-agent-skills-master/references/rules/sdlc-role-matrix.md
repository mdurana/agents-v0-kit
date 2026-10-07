# SDLC Role Matrix

Cross-persona standard for AI-augmented delivery with Cursor and nwob agent skills. Single reference for artifact ownership, workflow steps, intent routing, and phase gates.

Persona boundary docs:

- [product-owner-skill-boundaries.md](product-owner-skill-boundaries.md)
- [solution-architect-skill-boundaries.md](solution-architect-skill-boundaries.md)
- [solution-architect-command-standards.md](solution-architect-command-standards.md)
- [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md)
- [builder-skill-boundaries.md](builder-skill-boundaries.md)
- [pod-builder-skill-boundaries.md](pod-builder-skill-boundaries.md)
- [observer-skill-boundaries.md](observer-skill-boundaries.md)

Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md). Constitution: [constitution-core.mdc](../../rules/constitution-core.mdc).

**Co-equal SA ↔ LB:** Solution Architect and Lead Builder share a full skill mirror. Both may author every SA/LB artifact, including ADR bodies and OpenAPI. Dual-persist: `architecture.md` ↔ `masterplan.md`; flat `sdd/components/{component-name}-plan.md`. `/features` and `/orchestrate-design` are available on both. Prompt `tasks.md` maps to `story-tasks.md`.

---

## Personas and skills (27 total mirrored SA/LB capability)

| Persona | Agent | Skills | Slash commands |
|---------|-------|--------|----------------|
| Product Owner | [agents/product-owner.md](../../agents/product-owner.md) | 10 | `/problem` … `/deck` |
| Solution Architect | [agents/solution-architect.md](../../agents/solution-architect.md) | 14 | `/define`, `/problem` … `/features`, `/intake`, `/c4` … `/architecture`, `/orchestrate-design`, `/audit` |
| Lead Builder | [agents/lead-builder.md](../../agents/lead-builder.md) | 14 | `/features`, `/orchestrate-design`, `/c4` … `/architecture`, `/audit` |
| Builder | [agents/builder.md](../../agents/builder.md) | 4 | Intent only |
| Pod Builder | [agents/pod-builder.md](../../agents/pod-builder.md) | 7 | `/audit` (Session 5 peer) + intent-only build skills (**no** `orchestrate-design`) |
| Observer | [agents/observer.md](../../agents/observer.md) | 5 | `/summarize`, `/meeting`, `/handoff` |

Skill counts for SA and LB are **mirrored** (native SA skills + LB gate/orchestrate skills + shared `/features` / PO author skills as applicable). Pod Builder keeps: `co-design-solution`, `validate-design-package`, `trigger-ai-build`, `review-implementation`, `raise-merge-request`, `resolve-review-comments`, `/audit` — and **removes** `orchestrate-design`.

**Planned (stub only — do not simulate full role):** [solution-designer.md](../../agents/solution-designer.md), [quality-assurance.md](../../agents/quality-assurance.md), [scrum-master.md](../../agents/scrum-master.md).

**Composition rule:** User orchestrates personas. Personas do not invoke other personas. Personas invoke skills.

---

## Artifact ownership matrix

| Path | Owner | Skill / command |
|------|-------|-----------------|
| `nwob-docs/sdd/epic-spec.md` (problem, roadmap, backlog index, HL US/TS) | Product Owner **or** SA **or** LB | `/define`, `/problem` … `/roadmap`; `/features`; PO — `/backlog` |
| `stories/{STORY_ID}/story-spec.md` | PO/SA/LB primary; Builder/PB co-author | `/define`, `/features`, `/backlog`; SA/LB `/orchestrate-design`; PB `co-design-solution` |
| Technical annex in `{STORY_ID}/story-spec.md` | Builder / Pod Builder primary; SA/LB co-author | `co-design-solution`; SA/LB `/orchestrate-design` |
| `nwob-docs/sdd/tickets-export-params.md` | Product Owner | `/backlog` |
| `tickets.csv` (path from export params) | Product Owner | `/backlog` (derived; not SDD source of truth) |
| `{stories_dir}/{STORY_ID}/story-tasks.md` | Builder primary; SA/LB/PB co-author | `co-design-solution`; SA/LB `/orchestrate-design` (prompt `tasks.md` → this path) |
| `nwob-docs/sdd/design-notes.md` | SA **or** LB | `/orchestrate-design` (optional) |
| `nwob-docs/architecture/architecture.md` ↔ `nwob-docs/sdd/masterplan.md` | SA **or** LB (dual-persist) | `/c4` … `/ops`, `/architecture`, `/orchestrate-design` |
| flat `nwob-docs/sdd/components/{component-name}-plan.md` | SA **or** LB | `/services`, `/ops`, `/orchestrate-design` |
| Legacy `nwob-docs/architecture/components/` | — | **Read-only** brownfield fallback — do not write new files |
| `nwob-docs/architecture/adr/`, OpenAPI | SA **or** LB | `/pattern`, `/adr`, `/contracts` |
| `nwob-docs/diagrams/sequences/` | SA **or** LB | `/services`; design package |
| `nwob-docs/presentations/` | Product Owner (deck); SA/LB (intake only) | PO — `/present`, `/deck`; SA/PO/LB — `/define` or `/problem` (initial), `/intake` (update) |
| `nwob-docs/process/` | Product Owner | `/value` |
| `nwob-docs/meetings/` | Prompter upload | Observer `/meeting` reads |
| `nwob-docs/observations/` | Observer | Observer skills |
| Application code + pipeline YAML | Builder | `trigger-ai-build` |
| Code validation / MR approval | SA **or** LB | `review-implementation`, `audit-and-approve-code` |

### Write ACL for `*-spec.md` / `*-plan.md` / `*-tasks.md`

Applies **regardless of active persona**. Any persona may **read** these files. **Write** only when a primary owning skill or documented co-author skill is active:

| Files | May write | Must not write |
|-------|-----------|----------------|
| `epic-spec.md` | PO author skills; SA **or** LB when invoking those skills / `/define` | Builder, Pod Builder, Observer, persona switch/init |
| `story-spec.md` | PO/SA/LB `/features`, `/backlog`, `/orchestrate-design`; Builder/PB `co-design-solution` (co-author; flag material AC for PO) | Observer, persona switch/init |
| technical annex in `story-spec.md`, `story-tasks.md` | Builder / Pod Builder `co-design-solution` (primary); SA/LB `/orchestrate-design` / `co-design-solution` (co-author) | PO (product-only skills), Observer, persona switch/init |
| `story-tasks.md` (full bodies per story) | Builder / Pod Builder `co-design-solution` (primary); SA/LB co-author | PO product-only skills; thin epic-level task indexes |
| `architecture.md`, `masterplan.md` | SA **or** LB (dual-persist both) | Pod Builder, Builder (primary), Observer, persona switch/init |
| `sdd/components/**` | SA **or** LB (flat `{component-name}-plan.md` only (no component-spec twin)) | Pod Builder, Observer, persona switch/init; new writes under legacy `architecture/components/` |
| ADR bodies, OpenAPI | SA **or** LB `/pattern`, `/adr`, `/contracts` | Pod Builder, Observer, persona switch/init |

**MUST NOT** rewrite or “improve” these files outside an owning or co-author skill, or during `/persona` / `/switch` / `nwob init`. Route index gaps to `/orchestrate-design` (SA or LB).

---

## 13-step workflow

| Step | Agent | Invoke | Mode |
|------|-------|--------|------|
| 1 | Product Owner **or** SA **or** LB (architect-/LB-led) | PO: `/problem` → `/ideate` → `/roadmap`; SA/LB: `/define` | Sequential |
| 2 | Solution Architect **or** Lead Builder | `/c4` → `/pattern` → `/platform` → `/services` — **conceptual mode** (or `/architecture`) | Sequential |
| 3 | Product Owner **or** SA **or** LB | `/features` (or included in `/define`) | Sequential |
| 4 | Solution Designer *(planned)* | Interim: PO `/backlog` + SA/LB `architecture-delivery-enablement` | Interim |
| 5 | Quality Assurance *(planned)* | Interim: PO Gherkin self-check | Interim |
| 6 | Product Owner | `/backlog` | Sequential |
| 7 | Scrum Master *(planned)* | Interim: user-led ceremony | Interim |
| 8 | SA **or** LB + Builder — or Pod Builder (co-design only) | SA/LB `/orchestrate-design` + **design-package mode** (`/architecture` or `/contracts`/`/ops` reconcile); Builder/PB `co-design-solution` | After step 7 |
| 9 | SA **or** LB — or Pod Builder (Session 1 validate) | `validate-design-package` | **Sequential after** step 8 |
| 10 | Builder + SA/LB — or Pod Builder | `trigger-ai-build`; `review-implementation`; `raise-merge-request` (draft copy; human opens MR); `/audit` (peer); `resolve-review-comments` if REQUEST CHANGES | Parallel with Observer |
| 11 | Observer | `document-ai-techniques`; `/summarize`; `/meeting` | Parallel with 8–10 |
| 12 | Product Owner | `/backlog` (Gherkin acceptance) | After step 10 |
| 13 | Scrum Master *(planned)* | Interim: user-led ceremony | Interim |

**SA/LB engagement modes:** Conceptual (step 2, `epic-spec.md`) vs design-package (steps 8–9, `epic-spec.md` + draft in-scope `story-spec.md` / `story-tasks.md`). Step 2 architecture is provisional until reconciled in step 8. Pod Builder Session 1 is `co-design-solution` → `validate-design-package` (**no** `orchestrate-design`).

---

## SDD phase gates

| Gate | When | Requirement | Owner |
|------|------|-------------|-------|
| A | After step 3 | `epic-spec.md` on disk (backlog index + HL US/TS) | Product Owner **or** SA **or** LB |
| B | After step 6 | Backlog DEEP and sprint-ready | Product Owner |
| C | After step 9 | In-scope `story-spec.md` + `story-tasks.md` via `co-design-solution` + SA/LB `/orchestrate-design` + `validate-design-package` | SA/LB + Builder |
| D | After step 10 | `audit-and-approve-code` before external QA (peer; not MR author) | SA **or** LB |
| E | After step 12 | PO acceptance against Gherkin AC | Product Owner |

**Build gate:** No `trigger-ai-build` without `epic-spec.md`, in-scope `story-spec.md`, and `story-tasks.md` + SA/LB `validate-design-package` sign-off (or documented user waiver).

---

## Intent → persona → skill routing

### Product Owner

| Intent | Command / skill |
|--------|-----------------|
| Vague request / undefined root cause | `/problem` |
| Problem defined; need solutions | `/ideate` |
| Strategic sequencing | `/roadmap` |
| Net-new stories from roadmap | `/features` |
| Refine / prioritize existing stories | `/backlog` |
| Emit / refresh Jira `tickets.csv` | `/backlog` (params in `tickets-export-params.md`) |
| Delivery process optimization | `/value` |
| Leader-facing deck | `/deck` (or `/collect` → `/present` → `/enrich`) |

### Solution Architect

| Intent | Command / skill |
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
| SLOs / observability / go-live | `/ops` → `production-operations` |
| Material ADR | `/adr` → `architecture-governance` |
| ARC submission | `/arc` → `architecture-governance` |
| Full architecture engagement | `/architecture` → full chain per [solution-architect-command-standards.md](solution-architect-command-standards.md) |
| Design-package build-readiness | `validate-design-package` |
| Increment / MR audit | `review-implementation`, `/audit` |

### Lead Builder

| Intent | Command / skill |
|--------|-----------------|
| Net-new stories from roadmap | `/features` → `feature-definition` |
| Design workshop; strategy and architecture; per-story `story-tasks.md` (order from epic-spec) | `/orchestrate-design` |
| C4 / pattern / platform / services / contracts / ops | `/c4` … `/ops` (mirrored SA commands) |
| Material ADR or OpenAPI | `/adr`, `/pattern`, `/contracts` |
| Design package build-readiness | `validate-design-package` |
| Increment complete during build | `review-implementation` |
| MR ready for formal QC (peer; not MR author) | `/audit` → `audit-and-approve-code` |

### Builder

| Intent | Skill |
|--------|-------|
| Technical co-design; annex and `story-tasks.md` | `co-design-solution` |
| Design complete; implementation | `trigger-ai-build` |
| Last increment approved; draft MR copy | `raise-merge-request` |
| Pasted GitLab comments after `/audit` | `resolve-review-comments` |

### Pod Builder

| Intent | Skill |
|--------|-------|
| Technical co-design; annex and `story-tasks.md` | `co-design-solution` |
| Design package build-readiness | `validate-design-package` |
| Session 2 — execution plan and proposals | `trigger-ai-build` (Plan mode) |
| Session 3 — implement one todo | `trigger-ai-build` (Build mode) |
| Increment complete during build | `review-implementation` |
| Last increment approved; draft MR copy | `raise-merge-request` |
| Pasted GitLab comments after `/audit` | `resolve-review-comments` |
| MR ready for QA (Session 5 peer) | `audit-and-approve-code` |
| Design orchestration / architecture authorship | Route to SA **or** LB — **not** Pod Builder |

Assigned-story sessions and skill-hat gates: [pod-builder-skill-boundaries.md](pod-builder-skill-boundaries.md), [docs/guides/assigned-story-workflow.md](../../docs/guides/assigned-story-workflow.md).

### Observer

| Intent | Command / skill |
|--------|-----------------|
| Ongoing pilot capture | `document-ai-techniques` |
| Chat window summary | `/summarize` |
| Meeting notes / transcript | `/meeting` |
| Playbook feedback | `provide-workflow-feedback` |
| Pilot rotation end | `prepare-mentor-handoff` |

---

## Code ownership (authoritative)

| Concern | Author | Validator |
|---------|--------|-----------|
| Product stories / Gherkin AC | Product Owner **or** SA **or** LB (via `/features` / PO skills) | Builder gates |
| Implementation tasks (`story-tasks.md`) | Builder `co-design-solution` | SA/LB `validate-design-package` |
| Architecture / masterplan / components / ADRs / OpenAPI | Solution Architect **or** Lead Builder (co-equal; dual-persist) | `validate-design-package` |
| Application code | Builder `trigger-ai-build` | SA/LB `review-implementation`, `audit-and-approve-code` |
| Pipeline YAML | Builder `trigger-ai-build` | SA/LB `audit-and-approve-code` |

---

## Interim delegation (planned personas)

| Step | Planned persona | Interim coverage |
|------|-----------------|------------------|
| 4 | Solution Designer | Product Owner `/backlog` + SA/LB `architecture-delivery-enablement` |
| 5 | Quality Assurance | Product Owner Gherkin self-check on `epic-spec.md` (backlog index) |
| 7, 13 | Scrum Master | User-led sprint ceremonies |
| 12 | Quality Assurance | Product Owner `/backlog` acceptance (interim) |

---

## Greenfield happy path

**PO-led:**

```
Phase 0 discovery
  → PO: /problem → /ideate → /roadmap (epic-spec.md)
  → SA or LB: conceptual mode (provisional architecture.md ↔ masterplan.md)
  → PO/SA/LB: /features → PO /backlog (epic-spec.md backlog index) — gates A, B
  → User-led sprint start (step 7)
  → SA or LB: /orchestrate-design + design-package + Builder co-design-solution (annex + story-tasks.md)
  → SA or LB: validate-design-package — gate C
  → Builder: trigger-ai-build → raise-merge-request (draft; human opens MR)
  → SA or LB: review-implementation (per task) → audit-and-approve-code (/audit, peer) — gate D
  → Observer: parallel capture throughout 8–10
  → PO: /backlog acceptance — gate E
```

**Architect-led (SA persona) or LB-led:**

```
Phase 0 discovery
  → SA or LB: /define (epic-spec.md + epic-spec.md backlog index + intake-record.md)
  → SA or LB: /c4 → /pattern → … conceptual mode (dual-persist architecture ↔ masterplan)
  → PO persona or user-led: /backlog refinement — gate B
  → User-led sprint start (step 7)
  → (same steps 8–13 as PO-led path)
```

**Pod Builder (single persona, steps 8–10; author Sessions 1–4, peer Session 5):**

```
  → (Upstream) SA or LB: /orchestrate-design → design package + architecture dual-persist
  → Pod Builder: co-design-solution → validate-design-package — gate C
  → Pod Builder: trigger-ai-build (plan → build) + review-implementation (per task)
  → Pod Builder: raise-merge-request (Session 4 — draft copy; human opens MR)
  → Peer Pod Builder: audit-and-approve-code (/audit) — gate D
  → (resolve-review-comments if REQUEST CHANGES; same steps 11–13 as PO-led path)
```

---

## Anti-patterns

| Anti-pattern | Correct routing |
|--------------|-----------------|
| Implementation without `story-tasks.md` / per-story `story-tasks.md` (order from epic-spec) | Builder `co-design-solution` after SA/LB `/orchestrate-design` |
| Other Builder skills author `story-tasks.md` | Primary: `co-design-solution`; SA/LB may co-author via `/orchestrate-design` / `co-design-solution`; only `/orchestrate-design` writes design package |
| Pod Builder authors ADR, OpenAPI, masterplan, architecture, or components | Route to SA **or** LB `/pattern`, `/adr`, `/contracts`, `/orchestrate-design` |
| Treat ADR / OpenAPI as SA-exclusive | SA and LB are co-equal authors |
| Write new component files under `architecture/components/` | Write under `nwob-docs/sdd/components/`; dual-persist plan twin; legacy path is read-only |
| Update `architecture.md` without `masterplan.md` | Dual-persist both twins on every write |
| Pod Builder runs `orchestrate-design` | Session 1 is `co-design-solution` → `validate-design-package` |
| SA authors user stories in SA native skills only | Use `/define` or `/features` (also on LB) |
| Missing epic-spec.md — switch to PO persona | Run `/define` or `/problem` under SA (or LB) persona |
| PO writes to `observations/` for value stream | `/value` → `process/` |
| Observer orchestrates build | Document only; route to SA/LB |
| Skip `validate-design-package` | Mandatory before `trigger-ai-build` |
| Invoke `references/agent-skills-main` skills directly | Use nwob skills + embed rule files |
| Prompt says `tasks.md` — invent a separate file | Map to `story-tasks.md` |
