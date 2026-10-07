# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, Copilot, etc.) when working with code in this repository.

## Repository Overview

A collection of Product Owner, Solution Architect, Lead Builder, Builder, and Observer skills for constitution-compliant spec-driven delivery. Skills are packaged instructions that extend agent capabilities for enterprise product, architecture, leader-facing presentation, AI-assisted build, pod co-design/audit, and pilot observation workflows aligned with the [Enterprise System Constitution](rules/constitution-core.mdc).

## Core Rules

- If a task matches a skill, you MUST invoke it
- Skills are located in `skills/<role>/<skill-name>/SKILL.md`
- Never implement directly if a skill applies
- Always follow the skill instructions exactly (do not partially apply them)
- **Artifact discovery and persistence:** On every engagement, run Phase 0 discovery per [references/rules/sdd-artifact-layout.md](references/rules/sdd-artifact-layout.md). Resolve SDD paths via `.nwob/artifact-paths.json` when present (`nwob init` writes `spec` required and optional `stories_dir`); otherwise use default `nwob-docs/sdd/` layout. Architecture, meetings, observations, and presentations use fixed `nwob-docs/` paths (not in the mapping). On brownfield with external SDD docs, use `nwob init --no-scaffold-docs` and edit the mapping — no mandatory copy into `nwob-docs/`. Meeting notes/transcripts upload to `nwob-docs/meetings/`; `/meeting` summaries write to `nwob-docs/observations/`. Per-story `story-spec.md` (product anatomy + technical annex) and `story-tasks.md` write under resolved `stories_dir/{STORY_ID}/`. Cursor execution plans from Builder `trigger-ai-build` live in `~/.cursor/plans/` only (not SDD). Never treat chat as the source of truth — persist to disk.
- **`*-spec.md` / `*-plan.md` / `*-tasks.md` write ACL:** Any persona may **read** these files. **Write** only via owning skills. Solution Architect and Lead Builder are **co-equal** for SA/LB artifacts. PO author skills (`/problem` … `/backlog`) or SA/LB (`/define`, `/features`, …) for `epic-spec.md` (problem, roadmap, HL US/TS, chronological backlog index) and `{STORY_ID}/story-spec.md` (product fields); Builder / Pod Builder `co-design-solution` primary for technical annex sections in `story-spec.md` and `story-tasks.md` (SA/LB may also write via `/orchestrate-design` / `co-design-solution`; prompt `tasks.md` → `story-tasks.md`). Pod Builder may co-author `story-spec.md` when blocking design (flag material AC for PO). Do not rewrite outside an owning skill, or during `/persona` / `/switch` / `nwob init`.
- **Architecture / masterplan write ACL:** SA **or** LB — `/c4` … `/ops`, `/architecture`, `/orchestrate-design` for `nwob-docs/architecture/architecture.md` **and** dual twin `nwob-docs/sdd/masterplan.md` (same body; derived from `epic-spec.md`). Flat per-container plans at `nwob-docs/sdd/components/{component-name}-plan.md` (derived from `epic-spec.md`). ADR bodies and OpenAPI — SA **or** LB (`/pattern`, `/adr`, `/contracts`). Pod Builder **MUST NOT** author masterplan, architecture, components, ADRs, or OpenAPI. Legacy nested `sdd/components/{id}/` and `architecture/components/` are read-only brownfield fallback.

## Default vs. Override Constraints

[rules/constitution-core.mdc](rules/constitution-core.mdc) defines enterprise standards. Most sections are **mandatory**. Two areas are **default-overridable** (override in [rules/constitution-custom.mdc](rules/constitution-custom.mdc) or higher-precedence sources):

### Overridable defaults

- **Technology stack** — Default technology stack in `constitution-core.mdc` (language, DB, broker, cache, observability tooling)
- **Data lifecycle** — Default data lifecycle in `constitution-core.mdc` (soft-delete, audit timestamps, DLM)

### Override sources (highest precedence first)

1. Explicit user prompt / session instruction
2. Project SDD artifacts (`nwob-docs/sdd/epic-spec.md`, per-story `story-spec.md` + `story-tasks.md` per [sdd-artifact-layout.md](references/rules/sdd-artifact-layout.md))
3. Other project sources (ADRs, `architecture.md`, README, interviews, etc.)
4. **Fallback:** constitution defaults

### Agent behavior

- **Resolve effective constraints** at skill start when stack or data lifecycle is in scope.
- **Apply overrides faithfully** — do not revert to constitution defaults when a higher-precedence source specifies otherwise.
- **Flag conflicts** only when sources contradict each other (e.g., spec says MongoDB, plan says PostgreSQL); do not flag constitution-default divergence when an override is active.
- **Document overrides** in ADRs or spec/plan when the choice is architectural (SA skills); present faithfully when depicting (Product Owner presentation skills).
- **All other constitution sections remain mandatory** — SDD gates, story anatomy, Gherkin AC, stateless K8s, 100% meaningful coverage, RFC 7807, etc. No override without treating this as a separate governance change.

## Slash Commands

User-facing entry points for Product Owner, Solution Architect, Lead Builder, and Observer skills. Builder skills activate by intent only. Solution Architect and Lead Builder share the same SA/LB command set (co-equal). Full catalog: [README.md](README.md#all-28-skills).

### Product Owner

| Command | Skill |
|---------|-------|
| `/problem` | `business-problem-identification` |
| `/ideate` | `product-ideation` |
| `/roadmap` | `product-roadmap-creation` |
| `/features` | `feature-definition` |
| `/backlog` | `backlog-management-and-refinement` |
| `/value` | `value-stream-mapping` |
| `/intake` | `presentation-intake-update` |
| `/collect` | `presentation-content-extraction` |
| `/present` | `presentation-generation` |
| `/enrich` | `presentation-enrichment` |
| `/deck` | Full present chain (orchestrator; see [presentation-standards.md](references/rules/presentation-standards.md)) |

Product Owner command boundaries: [product-owner-skill-boundaries.md](references/rules/product-owner-skill-boundaries.md). Presentation handoffs: [presentation-standards.md](references/rules/presentation-standards.md).

### Solution Architect and Lead Builder (co-equal)

| Command | Skill |
|---------|-------|
| `/define` | `architect-led-sdd-intake` |
| `/problem` | `business-problem-identification` |
| `/ideate` | `product-ideation` |
| `/roadmap` | `product-roadmap-creation` |
| `/features` | `feature-definition` |
| `/intake` | `presentation-intake-update` |
| `/c4` | `architecture-governance` |
| `/pattern` | `architecture-governance` |
| `/platform` | `distributed-systems-architecture` |
| `/services` | `distributed-systems-architecture` |
| `/contracts` | `architecture-delivery-enablement` |
| `/ops` | `production-operations` |
| `/adr` | `architecture-governance` |
| `/arc` | `architecture-governance` |
| `/architecture` | Full SA chain (orchestrator; see [solution-architect-command-standards.md](references/rules/solution-architect-command-standards.md)) |
| `/orchestrate-design` | `orchestrate-design` |
| `/audit` | `audit-and-approve-code` |

Both personas install the same SA + LB skill set. Do not deprecate Solution Architect. Command standards: [solution-architect-command-standards.md](references/rules/solution-architect-command-standards.md). Boundaries: [solution-architect-skill-boundaries.md](references/rules/solution-architect-skill-boundaries.md), [lead-builder-skill-boundaries.md](references/rules/lead-builder-skill-boundaries.md).

### Observer

| Command | Skill |
|---------|-------|
| `/summarize` | `summarize-chat-session` |
| `/meeting` | `summarize-meeting` |

Command boundary and output schema: [agents/observer.md](agents/observer.md), [summarize-chat-session/SKILL.md](skills/observer/summarize-chat-session/SKILL.md), and [summarize-meeting/SKILL.md](skills/observer/summarize-meeting/SKILL.md).

## Intent → Skill Mapping

The agent should automatically map user intent to skills.

### Product Owner

| Intent | Command / Skill |
|--------|-----------------|
| Vague stakeholder request / undefined root cause | `/problem` → `business-problem-identification` |
| Problem defined, need solutions | `/ideate` → `product-ideation` |
| Strategic planning / roadmap | `/roadmap` → `product-roadmap-creation` |
| Initiative approved, need stories in `epic-spec.md` backlog index | `/features` → `feature-definition` (net-new from roadmap) |
| Backlog grooming / sprint prep / Jira CSV | `/backlog` → `backlog-management-and-refinement` (refine existing items; parameterized `tickets.csv`) |
| Delivery process optimization | `/value` → `value-stream-mapping` |
| Update presentation delivery params (audience, goal, format) | `/intake` → `presentation-intake-update` |
| Extract deck content from canonical SDD sources | `/collect` → `presentation-content-extraction` |
| Render leader-facing HTML or Markdown deck | `/present` → `presentation-generation` |
| Polish HTML interactivity | `/enrich` → `presentation-enrichment` |
| End-to-end leader-facing deck (tiered SDD gate) | `/deck` → present chain in [presentation-standards.md](references/rules/presentation-standards.md) |

Skill segregation: [product-owner-skill-boundaries.md](references/rules/product-owner-skill-boundaries.md).

### Solution Architect

Hybrid — `/c4` … `/architecture` for architecture workflow; other skills by intent. See [agents/solution-architect.md](agents/solution-architect.md) for orchestration order. Skill boundaries: [solution-architect-skill-boundaries.md](references/rules/solution-architect-skill-boundaries.md). Command standards: [solution-architect-command-standards.md](references/rules/solution-architect-command-standards.md). Do not invoke `references/agent-skills-main` skills directly when an nwob SA skill covers the intent.

| Intent | Command / Skill |
|--------|-----------------|
| Architect-led SDD bootstrap | `/define` → `architect-led-sdd-intake` |
| Problem / solutions / roadmap / stories (incremental) | `/problem`, `/ideate`, `/roadmap`, `/features` → PO author skills |
| Update presentation delivery params | `/intake` → `presentation-intake-update` |
| C4 Context + Container diagrams | `/c4` → `architecture-governance` |
| Architectural pattern options ADR | `/pattern` → `architecture-governance` |
| Cloud platform / MVP / network | `/platform` → `distributed-systems-architecture` |
| Services, data, EDA, resilience, migration | `/services` → `distributed-systems-architecture` |
| OpenAPI, patterns, fitness functions, catalogue | `/contracts` → `architecture-delivery-enablement` |
| Observability, production readiness, go-live | `/ops` → `production-operations` |
| Material ADR (any topic) | `/adr` → `architecture-governance` |
| ARC submission | `/arc` → `architecture-governance` |
| Full architecture engagement | `/architecture` → SA chain in [solution-architect-command-standards.md](references/rules/solution-architect-command-standards.md) |
| Design workshop / design package | `/orchestrate-design` → `orchestrate-design` |
| Design package build-readiness sign-off | `validate-design-package` |
| Per-increment validation during `trigger-ai-build` | `review-implementation` |
| MR audit before QA handoff | `/audit` → `audit-and-approve-code` |

### Lead Builder

Co-equal with Solution Architect — same slash command set and skill mirror (see table above). Additional LB-native focus: design orchestration, validation, increment review, MR audit. See [agents/lead-builder.md](agents/lead-builder.md). Boundaries: [references/rules/lead-builder-skill-boundaries.md](references/rules/lead-builder-skill-boundaries.md).

| Intent | Command / Skill |
|--------|-----------------|
| Architect-led SDD / epic-spec from `requirements.md` | `/define`, `/problem` … `/roadmap` |
| Stories / `story-spec.md` | `/features` |
| Design workshop / strategy from selected stories | `/orchestrate-design` |
| Architecture / masterplan / components / ADR / OpenAPI | `/c4` … `/ops`, `/architecture` |
| Design package build-readiness sign-off | `validate-design-package` |
| Per-increment validation during `trigger-ai-build` | `review-implementation` |
| MR audit before QA handoff (`MR_BRANCH` or brownfield OK) | `/audit` → `audit-and-approve-code` |

### Builder

No slash commands — activate skills by intent. See [agents/builder.md](agents/builder.md) for orchestration order within the Lead Builder lifecycle. Skill boundaries: [references/rules/builder-skill-boundaries.md](references/rules/builder-skill-boundaries.md).

| Intent | Skill |
|--------|-------|
| Technical co-design / fill per-story annex and `story-tasks.md` | `co-design-solution` |
| Start AI-assisted implementation | `trigger-ai-build` |
| Cursor execution plan after `validate-design-package` | `trigger-ai-build` |
| Last increment approved; draft GitLab MR copy | `raise-merge-request` |
| Address pasted GitLab review comments after `/audit` | `resolve-review-comments` |

### Pod Builder

Hybrid — `/audit` for Session 5 peer MR gate; **seven** story-level design + implementation skills by intent. **No** `orchestrate-design`; **MUST NOT** author `epic-spec.md`, masterplan, architecture, components, ADRs, or OpenAPI. Assigned-story sessions: [docs/guides/assigned-story-workflow.md](docs/guides/assigned-story-workflow.md). See [agents/pod-builder.md](agents/pod-builder.md). Skill boundaries: [references/rules/pod-builder-skill-boundaries.md](references/rules/pod-builder-skill-boundaries.md).

| Intent | Command / Skill |
|--------|-----------------|
| Map story-implementation annex subtasks to `story-tasks.md` | `co-design-solution` |
| Technical co-design / fill per-story annex and `story-tasks.md` | `co-design-solution` |
| Design package build-readiness sign-off (story-level) | `validate-design-package` |
| Session 2 — execution plan and Locked research proposals | `trigger-ai-build` (Plan mode) |
| Session 3 — implement one todo | `trigger-ai-build` (Build mode) |
| Per-increment validation during build | `review-implementation` |
| Last increment approved; draft GitLab MR copy | `raise-merge-request` |
| Address pasted GitLab review comments after `/audit` | `resolve-review-comments` |
| MR audit before QA handoff (Session 5 peer; brownfield OK) | `/audit` → `audit-and-approve-code` |

When **pod-builder** persona is active, story design + build map to the unified workflow in [agents/pod-builder.md](agents/pod-builder.md) — gate skills require separate invocation (skill-hat discipline). Prerequisite: SA/LB already produced `epic-spec.md` (backlog index), masterplan/architecture, and flat component plans when in scope.

### Observer

Hybrid — `/summarize` for chat capture, `/meeting` for meeting notes and transcripts; other skills by intent. See [agents/observer.md](agents/observer.md) for orchestration order. Skill boundaries: [observer-skill-boundaries.md](references/rules/observer-skill-boundaries.md).

| Intent | Command / Skill |
|--------|-----------------|
| Summarize current chat window (prompts, responses, tokens, credit cost) | `/summarize` → `summarize-chat-session` |
| Process meeting notes or transcript from file | `/meeting` → `summarize-meeting` |
| Ongoing AI technique and blocker capture | `document-ai-techniques` |
| Sprint-end or friction-driven playbook feedback | `provide-workflow-feedback` |
| End-of-pilot mentor seed package | `/handoff` → `prepare-mentor-handoff` |

## Cross-Agent Orchestration

Full user-facing workflow: [README.md — Agent Orchestration Workflow](README.md#agent-orchestration-workflow). Cross-persona reference: [references/rules/sdlc-role-matrix.md](references/rules/sdlc-role-matrix.md). Artifact layout: [references/rules/sdd-artifact-layout.md](references/rules/sdd-artifact-layout.md).

The user (or slash command) orchestrates personas. Personas do not invoke other personas. Personas may invoke skills.

### Phase 0: Project discovery (mandatory)

Before workflow step 1, **resolve SDD artifact paths** per [sdd-artifact-layout.md](references/rules/sdd-artifact-layout.md) (`.nwob/artifact-paths.json` or default `nwob-docs/sdd/` paths). Ask the prompter when not discoverable.

| Check | Resolved via | If present | If absent |
|-------|--------------|------------|-----------|
| SDD artifacts | key `spec` (required); `stories_dir` (optional) | Load, validate; write only via owning skills | Create at resolved paths when an owning skill runs |
| Architecture | fixed `nwob-docs/architecture/` + `sdd/masterplan.md` + flat `sdd/components/{component-name}-plan.md` | SA/LB commands review/extend; dual-persist masterplan only; derive from `epic-spec.md` | SA/LB produce; legacy nested components / `architecture/components/` read-only |
| Code workspace | `repositories/` + `nwob-docs/architecture/service-map.md` | Load submodules; resolve paths from service-map | Run `nwob doctor` to repair; greenfield assumes future submodules |
| Meeting inbox | fixed `nwob-docs/meetings/` | `/meeting` reads date subfolders; list pending files | Create meetings tree when uploads expected |
| Docs scaffold | `.nwob/init-options.json` → `scaffold_nwob_docs` | Default `nwob-docs/` tree when `true` | External mapping when `false` |

**Brownfield prompter contract:** If SDD artifacts exist outside default paths, edit `.nwob/artifact-paths.json` (written on `nwob init`) and map `spec` (and optionally `stories_dir`). Remove obsolete `plan` / `tasks` keys. Agents proceed **in place** at mapped paths — no mandatory copy into `nwob-docs/`. Offer migration only when the prompter explicitly requests it.

**Brownfield branch matrix:**

| Resolved SDD / architecture | Also present | Enter at step |
|-----------------------------|--------------|---------------|
| `spec` only | No `architecture` | 2 (SA conceptual) or 3 (Product Owner `/features`) |
| `spec` only | `architecture` | 3 (Product Owner `/features`) |
| `spec` with backlog index | Stories not sprint-ready | 4 (interim: Product Owner `/backlog`) |
| `spec` with backlog index | Stories sprint-ready | 8 (`orchestrate-design`) |
| `spec` + in-scope `story-spec.md` / `story-tasks.md` | `repositories/` + service-map populated | 10 (`trigger-ai-build`) |
| Code only | No SDD at resolved paths | **Stop** — configure mapping or run Product Owner `/problem` and `/features` |

### End-to-end workflow (13 steps)

| Step | Action | Agent | Invoke | Read/write under `nwob-docs/` |
|------|--------|-------|--------|-------------------------------|
| 1 | Define problem, epics, metrics | Product Owner **or** SA/LB (architect-led) | PO: `/problem` → `/ideate` → `/roadmap`; SA/LB: `/define` | Write `sdd/epic-spec.md`, `presentations/intake-record.md` |
| 2 | Technical solution (conceptual) | Solution Architect **or** Lead Builder | `/c4` → `/pattern` → `/platform` → `/services` or `/architecture` — **conceptual mode** | Write provisional `architecture/` + dual `sdd/masterplan.md`; `sdd/components/` |
| 3 | User/technical stories | Product Owner **or** SA/LB | `/features` (or included in `/define`) | Extend `sdd/epic-spec.md` backlog index + HL US/TS; write `story-spec.md` |
| 4 | Backlog + delivery artifacts | Solution Designer *(planned)* | Interim: Product Owner `/backlog` + SA/LB `architecture-delivery-enablement` | Refine `sdd/epic-spec.md` backlog index; optional `tickets.csv` |
| 5 | Story readiness | Quality Assurance *(planned)* | Interim: Product Owner Gherkin self-check on `story-spec.md` / backlog index | Readiness gate |
| 6 | Adjust stories | Product Owner | `/backlog` | Update `sdd/epic-spec.md` backlog index; optional parameterized `tickets.csv` |
| 7 | Start sprint | Scrum Master *(planned)* | Interim: user-led ceremony | — |
| 8 | Design workshop; derive `story-tasks.md` + technical annex | SA/LB + Builder — or Pod Builder (story annex only) | SA/LB `/orchestrate-design` + design-package mode; Builder/PB `co-design-solution` writes annex in `story-spec.md` + `story-tasks.md` | Write `story-spec.md` annex, `story-tasks.md`, design package; PB does not run `/orchestrate-design` |
| 9 | Design sign-off | SA/LB — or Pod Builder (Session 1 story gate) | `validate-design-package` — **sequential after** step 8 draft | Validated in-scope `story-spec.md` + `story-tasks.md` |
| 10 | Build, close tickets | Builder + SA/LB — or Pod Builder | `trigger-ai-build`; `review-implementation` (per increment); `raise-merge-request` (draft copy; human opens MR); `/audit` (peer on `MR_BRANCH`); `resolve-review-comments` if REQUEST CHANGES | Code + MR sign-offs |
| 11 | Observations | Observer | `document-ai-techniques`; `/summarize`; `/meeting` | Read `meetings/{YYYY-MM-DD}/`; write `observations/{YYYY-MM-DD}-{slug}-summary.md` |
| 12 | PO acceptance | Product Owner | `/backlog` (Gherkin AC) | Sign-off |
| 13 | Close sprint | Scrum Master *(planned)* | Interim: user-led ceremony | — |

**Planned personas:** Do not simulate full Solution Designer, Quality Assurance, or Scrum Master engagements — stub agents define interim delegation only. See [agents/solution-designer.md](agents/solution-designer.md), [agents/quality-assurance.md](agents/quality-assurance.md), [agents/scrum-master.md](agents/scrum-master.md), and [README — Planned Personas](README.md#planned-personas).

**Product Owner `/deck`:** **Tiered** presentation gate — partial deck after `epic-spec.md` + `intake-record.md` (Features/Roadmap only); full deck adds `masterplan.md` / `architecture.md` (+ flat component plans when present) — typically after step 9. `/collect` reads canonical `nwob-docs/`; `/present` writes `nwob-docs/presentations/`. See [presentation-standards.md](references/rules/presentation-standards.md).

### SDD phase gates

| Gate | When | Requirement |
|------|------|-------------|
| A | After step 3 | `nwob-docs/sdd/epic-spec.md` on disk (backlog index + HL US/TS) |
| B | After step 6 | Backlog DEEP and sprint-ready |
| C | After step 9 | In-scope `story-spec.md` + `story-tasks.md` via `co-design-solution` + `orchestrate-design` + `validate-design-package` |
| D | After step 10 | `audit-and-approve-code` before external QA |
| E | After step 12 | PO acceptance against Gherkin AC |

### Parallelism rules

- **Observer:** Activate `document-ai-techniques` when Lead Builder or Builder skills run; do not block build.
- **Builder / Pod Builder `co-design-solution`:** Writes technical annex in `story-spec.md` and `story-tasks.md` bodies. SA/LB `/orchestrate-design` consolidates design package and may dual-persist architecture (Pod Builder does not run `/orchestrate-design`).
- **SA/LB commands:** Conceptual mode at step 2 (`/c4` … `/services`); design-package mode during step 8 inside `/orchestrate-design` (`/architecture` or reconcile). Dual-persist `architecture.md` ↔ `sdd/masterplan.md` only. Not invoked by PO persona during build.
- **Step 8 → 9:** `validate-design-package` runs **after** draft in-scope `story-spec.md` + `story-tasks.md` exist — not in parallel with step 8.

### Spec-Driven Development (mandatory)

No implementation handoff without finalized artifacts on disk under `nwob-docs/sdd/`:

1. **DEFINE** → `business-problem-identification` → `nwob-docs/sdd/epic-spec.md`
2. **IDEATE** → `product-ideation` → refine `epic-spec.md`
3. **PLAN** → `product-roadmap-creation` + `feature-definition` → extend `nwob-docs/sdd/epic-spec.md` (roadmap, HL US/TS, backlog index) + `{STORY_ID}/story-spec.md`
4. **TASK** → Builder / Pod Builder `co-design-solution` writes technical annex in `story-spec.md` and `{stories_dir}/{STORY_ID}/story-tasks.md` bodies; SA/LB `/orchestrate-design` consolidates design package
5. **BUILD** → implementation only after `epic-spec.md`, in-scope `story-spec.md`, and `story-tasks.md` exist (story order from epic-spec backlog index)

Zero vibe-coding: ad-hoc implementation bypassing spec → plan → task workflow is strictly prohibited.

## Lifecycle Mapping (per-role)

### Solution Architect Orchestration

For full architecture engagements, apply skills per **engagement mode** (see [solution-architect-skill-boundaries.md](references/rules/solution-architect-skill-boundaries.md#engagement-modes)):

- **Conceptual mode** (workflow step 2): `epic-spec.md` prerequisite
- **Design-package mode** (steps 8–9 inside `orchestrate-design`): `epic-spec.md` backlog index + draft in-scope `story-spec.md` / `story-tasks.md`

**SDD gate tiers** (apply based on engagement context):

| Tier | When | SDD requirement |
| --- | --- | --- |
| ARC intake | Pre-ARC / governance-only (`architecture-governance`) | None |
| Design-phase SA coordination | Inside Lead Builder `orchestrate-design` | `epic-spec.md` + draft in-scope `story-spec.md` / `story-tasks.md` |
| Full SA orchestration | Standalone architecture engagement | `epic-spec.md` + derived masterplan/components (+ in-scope `story-spec.md` / `story-tasks.md` when in scope) |

0. **SDD gate** — Apply the tier above before the command chain (ARC intake and narrow single-command requests exempt the full gate)
Within the active mode (or `/architecture` orchestrator):
1. `/c4` (`architecture-governance`) — C4 Context + Container first (technology-agnostic)
2. `/pattern` (`architecture-governance`) — pattern-selection ADR with ≥2 options
3. `/platform` (`distributed-systems-architecture`) — platform/MVP, `network.md`; defaults AWS/EKS
4. `/services` (`distributed-systems-architecture`) — services, data, integration; defaults EDA/Kafka
5. `/contracts` (`architecture-delivery-enablement`) — contracts, patterns, fitness functions, catalogue
6. `/ops` (`production-operations`) — SLAs, observability (Datadog default; OTel optional), production readiness
7. `architecture-governance` — **continuous** throughout (ADRs, ARC, drift correction)

Skip or reorder based on task scope. A single command suffices for narrow requests (e.g. `/c4` only, `/adr` only).

### Product Owner Orchestration

See [agents/product-owner.md](agents/product-owner.md) and [product-owner-skill-boundaries.md](references/rules/product-owner-skill-boundaries.md).

**SDD author chain:** `/problem` → `/ideate` → `/roadmap` → `/features` → `/backlog` with prerequisite gates per [product-owner-skill-boundaries.md](references/rules/product-owner-skill-boundaries.md). Initial `intake-record.md` created in `/problem`. Reference `interview-me` and `idea-refine` patterns embedded in `/problem` and `/ideate` — see [agent-skills-main-mapping.md](references/rules/agent-skills-main-mapping.md).

**Presentation chain (`/deck`):** Tiered SDD gate → read `intake-record.md` → `presentation-content-extraction` → `presentation-generation` → `presentation-enrichment` (optional, HTML only). See [presentation-standards.md](references/rules/presentation-standards.md).

### Lead Builder Orchestration

Co-equal with SA — may also run `/define`, `/c4` … `/architecture`, `/features`. For full build engagements (see [agents/lead-builder.md](agents/lead-builder.md); boundaries: [references/rules/lead-builder-skill-boundaries.md](references/rules/lead-builder-skill-boundaries.md)):

1. **SDD artifacts ready** — `nwob-docs/sdd/epic-spec.md` exists with backlog index (PO, SA, or LB)
2. `/orchestrate-design` — Strategy plan, architecture/masterplan/flat component plans, design package
3. `validate-design-package` — Independent sign-off before build
4. `trigger-ai-build` (Builder) — SDD gate; Cursor execution overlay in `~/.cursor/plans/` only; quality gates

Skip or reorder based on task scope. A single skill suffices for narrow requests (e.g. validate design package → Lead Builder `validate-design-package` only).

Builder skills integrate within this lifecycle (see [agents/builder.md](agents/builder.md)):

1. `co-design-solution` — after `orchestrate-design`; persist annex and `story-tasks.md` under `stories_dir`
2. `trigger-ai-build` — SDD gate; Cursor execution overlay in `~/.cursor/plans/`
3. `raise-merge-request` — after last increment Approved
4. `resolve-review-comments` — after `/audit` REQUEST CHANGES with pasted GitLab comments

Lead Builder gates in the same chain: `validate-design-package`, `review-implementation` (per increment), `/audit`.

### Pod Builder Orchestration

Story-level design + implementation only (**seven** skills; **no** `orchestrate-design`). Apply assigned-story sessions in [agents/pod-builder.md](agents/pod-builder.md) (boundaries: [references/rules/pod-builder-skill-boundaries.md](references/rules/pod-builder-skill-boundaries.md)):

1. **Prerequisite** — SA/LB produced `epic-spec.md` (backlog index), masterplan/architecture, and flat component plans when in scope
2. **Session 1** — **`co-design-solution`** then **`validate-design-package`** (**STOP** gate; skill-hat discipline)
3. **Session 2** — **`trigger-ai-build`** (Plan mode): execution overlay; Locked research proposals; stop before Implementation todos
4. **Session 3** — **`trigger-ai-build`** (Build mode) with **`review-implementation`** after each increment (**STOP** gate)
5. **Session 4** — **`raise-merge-request`** — author **STOP** (do not self-audit)
6. **Session 5** — **`audit-and-approve-code`** (`/audit`) — **peer developer** before external QA
7. **Session 6** — **`resolve-review-comments`** if REQUEST CHANGES; loop to Session 5

Skip or reorder based on task scope. Split personas (`lead-builder` + `builder`) remain valid for separation-of-duties engagements.

### Observer Orchestration

For full Observer engagements, apply skills in this order (see [agents/observer.md](agents/observer.md)):

1. `document-ai-techniques` — ongoing during Builder Pod design and build
2. `provide-workflow-feedback` — at sprint end or when workflow friction is encountered
3. `/summarize` (`summarize-chat-session`) — on demand for current chat-window capture
4. `/meeting` (`summarize-meeting`) — on demand for meeting notes and transcript files
5. `prepare-mentor-handoff` — at end of pilot rotation (30–60 days)

Skip or reorder based on task scope. A single skill suffices for narrow requests (e.g. `/summarize` only, `/meeting` only).

## Execution Model

For every request:

1. Determine if any skill applies (even 1% chance)
2. Load the appropriate skill from `skills/<role>/<skill-name>/SKILL.md`
3. Follow the skill workflow strictly
4. Only proceed to implementation after required steps (spec, plan, tasks) are complete
5. Verify against the skill's Verification checklist before declaring done

## Anti-Rationalization

The following thoughts are incorrect and must be ignored:

- "This is too small for a skill"
- "I can just quickly implement this"
- "I'll gather context first"
- "Gherkin AC can wait until dev starts"
- "We'll write the ADR after shipping"
- "Constitution stack is always mandatory" — incorrect when user prompt, spec, or other sources explicitly define an override per [Default vs. Override Constraints](#default-vs-override-constraints)

Correct behavior:

- Always check for and use skills first

## Orchestration: Personas, Skills, and Commands

This repo has three composable layers. They have different jobs and should not be confused:

- **Skills** (`skills/<role>/<skill-name>/SKILL.md`) — workflows with steps and exit criteria. The *how*. Mandatory hops when an intent matches.
- **Personas** (`agents/<role>.md`) — roles with a perspective and an output format. The *who*.
- **Slash commands** — user-facing entry points for Product Owner, Solution Architect, Builder, and Observer skills. The *when*. The orchestration layer.

Composition rule: **the user (or a slash command) is the orchestrator. Personas do not invoke other personas.** A persona may invoke skills.

| Persona | Location | Skills |
|---------|----------|--------|
| Product Owner | [agents/product-owner.md](agents/product-owner.md) | 10 skills via `/problem` … `/value`, `/intake`, `/collect`, `/present`, `/enrich`, `/deck` |
| Solution Architect | [agents/solution-architect.md](agents/solution-architect.md) | 14 skills — co-equal with LB (`/define`, PO SDD, `/c4` … `/architecture`, `/orchestrate-design`, `/audit`) |
| Lead Builder | [agents/lead-builder.md](agents/lead-builder.md) | 14 skills — co-equal with SA (same command/skill mirror) |
| Builder | [agents/builder.md](agents/builder.md) | 4 Builder skills via orchestration workflow (intent-only) |
| Pod Builder | [agents/pod-builder.md](agents/pod-builder.md) | 7 story-cycle skills (`co-design` … `/audit`; no `orchestrate-design`) |
| Observer | [agents/observer.md](agents/observer.md) | 3 Observer skills by intent + `/summarize` + `/meeting` |

## Creating a New Skill

### Directory Structure

```
skills/
  <role>/
    <skill-name>/           # kebab-case directory name
      SKILL.md              # Required: skill definition
```

### Naming Conventions

- **Role directory**: `product-owner`, `solution-architect`, `lead-builder`, `builder`, or `observer`
- **Skill directory**: `kebab-case` (e.g. `feature-definition`)
- **SKILL.md**: Always uppercase, always this exact filename

### SKILL.md Format

```markdown
---
name: {skill-name}
description: {One sentence}. Use when {trigger conditions}.
---

# {Skill Title}

## Overview
## When to Use
## Process
## Constitution Compliance
Label which rules are **mandatory** vs **default-overridable** (technology stack — Default technology stack in constitution-core, data lifecycle — Default data lifecycle in constitution-core) per [Default vs. Override Constraints](#default-vs-override-constraints).
## Rationalizations
## Red Flags
## Verification
```

### Best Practices for Context Efficiency

- **Keep SKILL.md under 500 lines** — put detailed reference material in separate files
- **Write specific descriptions** — helps the agent know exactly when to activate the skill
- **Use progressive disclosure** — reference supporting files that get read only when needed
- **File references work one level deep** — link directly from SKILL.md to supporting files

All new skills must comply with mandatory constitution rules and follow the anatomy defined in [README.md](README.md#how-skills-work). Treat technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) as defaults overridable per [Default vs. Override Constraints](#default-vs-override-constraints).

<!-- nwob:managed — do not remove this block without `nwob init` -->

# NWOB Agent Skills (Project)

This project uses [NWOB Agent Skills](https://github.com/nwob-agent-skills) for constitution-compliant spec-driven delivery.

## Core Rules

- If a task matches a skill, load it from `.cursor/skills/<skill-name>/SKILL.md` and follow exactly.
- Constitution: [`.cursor/rules/constitution-core.mdc`](.cursor/rules/constitution-core.mdc) and [`.cursor/rules/constitution-custom.mdc`](.cursor/rules/constitution-custom.mdc) (meta-repo sources: [`rules/constitution-core.mdc`](rules/constitution-core.mdc), [`rules/constitution-custom.mdc`](rules/constitution-custom.mdc))
- Rules: [`references/rules/`](references/rules/)
- SDD gate: no implementation without `nwob-docs/sdd/epic-spec.md`, in-scope `story-spec.md`, and `story-tasks.md`.
- Switch persona: `/persona` or `/switch` (see `.cursor/skills/switch-persona/SKILL.md`).
- One active persona in `.cursor/` at a time; shared `references/` and `constitution-core.mdc` / `constitution-custom.mdc` persist.

<!-- nwob:active-persona:start -->
**Active persona:** `product-owner`
**Installed personas:** `product-owner`

Persona file: [`agents/product-owner.md`](agents/product-owner.md)
Persona rule: [`.cursor/rules/nwob-product-owner.mdc`](.cursor/rules/nwob-product-owner.mdc)

### Available commands (installed personas)

- **product-owner:** /problem /ideate /roadmap /features /backlog /value /intake /collect /present /enrich /deck

Switch persona: `/persona` or `/switch` (swaps `.cursor/skills` and `.cursor/rules`)
<!-- nwob:active-persona:end -->

## SDD Artifacts (`nwob-docs/sdd/`)

| Artifact | Purpose |
|----------|---------|
| `nwob-docs/sdd/epic-spec.md` | Problem, vision, roadmap, HL US/TS, chronological backlog index (PO or SA/LB) |
| `nwob-docs/sdd/masterplan.md` | Dual twin of `architecture/architecture.md` (SA or LB; derived from epic-spec) |
| `nwob-docs/sdd/components/{component-name}-plan.md` | Per-container plan (flat; SA or LB; derived from epic-spec) |
| `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md` | Product anatomy + technical annex (PO or SA/LB; annex by Builder / PB co-design) |
| `nwob-docs/sdd/stories/{STORY_ID}/story-tasks.md` | Per-story full task bodies (Builder / PB primary; SA/LB co-author) |
| `nwob-docs/architecture/architecture.md` | System architecture (SA or LB; dual with `sdd/masterplan.md`) |
