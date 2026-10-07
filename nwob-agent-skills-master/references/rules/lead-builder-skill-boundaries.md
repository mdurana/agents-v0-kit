# Lead Builder Skill Boundaries

Shared segregation rules for Lead Builder skills in `skills/lead-builder/` and mirrored Solution Architect skills. Persona: [agents/lead-builder.md](../../agents/lead-builder.md). Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md). Builder handoffs: [agents/builder.md](../../agents/builder.md). Builder boundaries: [builder-skill-boundaries.md](builder-skill-boundaries.md). SA mirror: [solution-architect-skill-boundaries.md](solution-architect-skill-boundaries.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

**Reference skill mapping:** Patterns from `references/agent-skills-main` are embedded via supporting rule files — do not invoke reference skills directly when an nwob skill or embed covers the intent. Full mapping: [agent-skills-main-mapping.md](agent-skills-main-mapping.md).

**Co-equal with Solution Architect:** Lead Builder and Solution Architect are **co-equal** — full skill mirror. Both may author every SA/LB artifact, including ADR bodies and OpenAPI. `/features` and `/orchestrate-design` are available on both personas.

---

## Model: Orchestrate → Gate → Review → Audit (+ mirrored SA)

| Layer | Purpose | Skills / commands |
|-------|---------|-------------------|
| **0 — Product / features** | Stories and Gherkin AC (mirrored) | `/features` → `feature-definition`; `/define` and PO author skills when architect-/LB-led |
| **1 — Orchestrate** | Strategy plan, design package, design package; architecture dual-persist | `/orchestrate-design` → `orchestrate-design` |
| **1b — Architecture (mirrored)** | C4, pattern ADR, platform, services, contracts, ops | `/c4` … `/ops`, `/adr`, `/arc`, `/architecture` (same as SA) |
| **2 — Gate** | Independent design-package build-readiness sign-off | `validate-design-package` |
| **3 — Review** | Per-increment validation during AI-assisted build | `review-implementation` |
| **4 — Audit** | Holistic MR QC before external QA handoff (`/audit`) | `audit-and-approve-code` |

**Rule:** No Lead Builder skill may **execute** application builds as owner, **open** GitLab MRs, or **resolve** review comments as owner (Builder owns those). Lead Builder **may author** `epic-spec.md` via `/define` or PO author skills / `/features`; **may author** `architecture.md` ↔ `masterplan.md`, `sdd/components/**`, ADR bodies, and OpenAPI (co-equal with SA); **may author** thin per-story `story-tasks.md` (order from epic-spec) via `/orchestrate-design`; **may co-author** `story-spec.md`, technical annex in `story-spec.md`, and `story-tasks.md` via `/orchestrate-design` / `co-design-solution` per [sdd-artifact-layout.md](sdd-artifact-layout.md).

---

## SDD handoff chain

```
PO/SA/LB: /features          Lead Builder (∨ SA)                 Builder
         │                              │                            │
         ▼                              ▼                            ▼
    epic-spec.md backlog index (stories)    /orchestrate-design → design package    co-design-solution → story-tasks.md
         │                              │                            │
         │                    design package + dual-persist arch      │
         │                              ▼                            ▼
         │                    validate-design-package          trigger-ai-build
         │                              │                            │
         └────────────────── review-implementation (per increment) ──┘
                                        │
                         raise-merge-request (Builder)
                                        │
                         audit-and-approve-code (/audit → QA)
                                        │
                         resolve-review-comments (Builder, if changes requested)
```

| Artifact | Owner | Lead Builder role |
|----------|-------|-------------------|
| `nwob-docs/sdd/epic-spec.md` | PO **or** SA **or** LB | May author via `/define` / PO author skills |
| `nwob-docs/sdd/epic-spec.md` (backlog index) | PO **or** SA **or** LB | May author via `/define`, `/features`; PO owns `/backlog` |
| `{stories_dir}/{STORY_ID}/story-spec.md` | PO/SA/LB; Builder/PB co-author | May create/update via `/features`, `/orchestrate-design` / `co-design-solution`; Gherkin required; flag material AC changes for PO when co-authoring mid-design |
| technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | Builder primary; SA/LB co-author | May write annex via `/orchestrate-design` / `co-design-solution`; fill `story-tasks.md` ID column |
| `{stories_dir}/{STORY_ID}/story-tasks.md` | Builder primary; SA/LB co-author | May author full task bodies via design skills; prompt `tasks.md` **maps to** `story-tasks.md` |
| Cursor execution plan (`~/.cursor/plans/`) | Builder — `trigger-ai-build` | Do not generate |
| `nwob-docs/observations/audit-report.md` | Lead Builder — `/audit` | Holistic MR audit report |
| `nwob-docs/sdd/design-notes.md` | SA **or** LB — `/orchestrate-design` | Optional strategy/sequencing notes |
| `nwob-docs/architecture/architecture.md` ↔ `nwob-docs/sdd/masterplan.md` | SA **or** LB (dual-persist) | Author via `/c4` … `/ops`, `/architecture`, `/orchestrate-design` — write **both** twins |
| flat `nwob-docs/sdd/components/{component-name}-plan.md` | SA **or** LB (dual-persist) | Author under `sdd/components/` only; legacy `architecture/components/` is read-only brownfield fallback |
| `nwob-docs/architecture/adr/`, OpenAPI | SA **or** LB | May author ADR body and OpenAPI (co-equal; not exclusive) |
| Application code | Builder — `trigger-ai-build` | Review per increment; audit MR holistically — do not author (Builder `resolve-review-comments` may edit comments only) |
| GitLab MR draft | Builder — `raise-merge-request` | Audit only after the human opens the MR |

---

## Canonical source map

| Content pillar | Authoritative source | Author skill | Validated by |
|----------------|---------------------|--------------|--------------|
| Product stories / Gherkin AC | `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from `epic-spec.md` backlog index) | PO `/features`, `/backlog` (primary); SA/LB `/define`, `/features`, `/orchestrate-design` | `/orchestrate-design` pre-gate; `validate-design-package` |
| Story task bodies | `{stories_dir}/{STORY_ID}/story-tasks.md` (prompt `tasks.md` → this path) | Builder `co-design-solution` (primary); SA/LB co-author | `validate-design-package`, `review-implementation` |
| Technical annex | technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | `co-design-solution` (primary); SA/LB co-author | `/orchestrate-design`, `validate-design-package` |
| System architecture / masterplan | `architecture.md` ↔ `sdd/masterplan.md` | SA **or** LB `/c4` … `/ops`, `/architecture`, `/orchestrate-design` | `validate-design-package` |
| Component spec / plan | `sdd/components/{component-name}-plan.md` (dual twins) | SA **or** LB `/services`, `/ops`, `/orchestrate-design` | `validate-design-package` |
| ADRs / OpenAPI | `architecture/adr/`, swagger paths | SA **or** LB `/pattern`, `/adr`, `/contracts` | `validate-design-package` |
| Application code | Code repo roots | `trigger-ai-build` | `review-implementation`, `audit-and-approve-code` |
| GitLab MR | Draft title, body, and branch names | `raise-merge-request` | `audit-and-approve-code` |
| GitLab review replies | Pasted review text; reply draft | `resolve-review-comments` | Re-run `/audit` |
| MR audit report | `nwob-docs/observations/audit-report.md` | `audit-and-approve-code` | — |

---

## Builder handoffs

| Phase | Builder skill | When | Lead Builder action |
|-------|---------------|------|---------------------|
| Design workshop | `co-design-solution` | After `/orchestrate-design` | Invite annex and `story-tasks.md`; SA/LB retains orchestration + design package |
| Pre-build gate | `validate-design-package` | After design package + `story-spec.md` + `story-tasks.md` draft | **Stop** Builder `trigger-ai-build` until signed off (or user documents waiver) |
| Per increment | `review-implementation` | After each `story-tasks.md` item during `trigger-ai-build` | **Stop** — Builder advances only on increment approval |
| MR draft | `raise-merge-request` | After last increment Approved | Builder drafts copy; human opens the MR; LB does not draft or open MR |
| MR / QA handoff | `audit-and-approve-code` | After human opens MR on `MR_BRANCH` | **Stop** — no external QA until audit passes; typically another developer in Session 5 |
| Resolve comments | `resolve-review-comments` | After `/audit` REQUEST CHANGES with pasted GitLab comments | Author as Builder; LB does not implement; re-run `/audit` after push |

Separation of duties: Builder **co-designs, builds, drafts MR copy, and resolves review comments**; Lead Builder **orchestrates design (co-equal with SA on architecture), validates, reviews increments, and audits** the MR. The human opens, approves, and merges in GitLab.

---

## Intent → skill routing

| Intent | Command / Skill |
|--------|-----------------|
| Net-new stories from roadmap | `/features` → `feature-definition` |
| Epics/stories selected; design workshop; design package needed | `/orchestrate-design` → `orchestrate-design` |
| Refresh design package from `story-tasks.md` IDs | `/orchestrate-design` |
| C4 / pattern / platform / services / contracts / ops | `/c4` … `/ops` (mirrored SA commands) |
| Material ADR or OpenAPI | `/adr`, `/pattern`, `/contracts` (LB may author) |
| Design package draft ready for build sign-off | `validate-design-package` |
| Task or increment complete during `trigger-ai-build` | `review-implementation` |
| MR ready for formal QC before QA, or peer named an MR branch | `/audit` → `audit-and-approve-code` |

---

## Per-skill boundaries

| Skill | Writes | Must NOT |
|-------|--------|----------|
| `orchestrate-design` | Design package; design package; optional `design-notes.md`; dual-persist `architecture.md` ↔ `masterplan.md` and `sdd/components/**`; co-author `story-spec.md`, technical annex in `story-spec.md`, `story-tasks.md`; may author ADR/OpenAPI when design requires | Author application code; run `trigger-ai-build`; write new files under legacy `architecture/components/` |
| Mirrored SA skills (`architecture-governance`, etc.) | Same paths as SA command standards; dual-persist twins | Implement application code; skip dual-persist on architecture/component writes |
| `validate-design-package` | Sign-off or gap list | Produce architecture or story bodies; run `/orchestrate-design` as owner; start build |
| `review-implementation` | Per-increment approval or rework request | Holistic MR audit; skip to next task without approval; implement code |
| `audit-and-approve-code` | `audit-report.md`; GitLab review draft | Per-increment review only; implement fixes; post to GitLab; approve/merge MR via agent |

---

## Reference embed files

| Embed | Source reference skill | Used in |
|-------|------------------------|---------|
| [task-breakdown-patterns.md](task-breakdown-patterns.md) | `planning-and-task-breakdown` | Builder `co-design-solution` |
| [builder-quality-patterns.md](builder-quality-patterns.md) | `code-review-and-quality`, `debugging-and-error-recovery`, `code-simplification`, `git-workflow-and-versioning`, `browser-testing-with-devtools` | `review-implementation`, `audit-and-approve-code` |

**Do not** load `references/agent-skills-main/skills/*/SKILL.md` directly during Lead Builder engagement when an embed exists.

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "epic-spec.md backlog index is enough — skip task artifacts" | Derive `story-tasks.md` via `co-design-solution` and design package via `/orchestrate-design`; constitution requires spec, plan, and tasks |
| "Skip `validate-design-package` — LB already checked" | Independent sign-off required before `trigger-ai-build` |
| "Fold MR draft into orchestrate-design" | Builder `raise-merge-request` after build; separate session |
| "Run /audit on own MR" | Session 5 is another developer as Lead Builder |
| "Implement fixes during /audit" | Author uses Builder `resolve-review-comments`; `/audit` does not implement |
| "Post GitLab review from the agent" | Print GitLab Output Format. The human posts in GitLab. |
| "GitLab draft differs from audit report" | Dual-render from one finding set per builder-quality-patterns |
| "Title the MR with the epic-spec.md backlog index story id" | Builder `raise-merge-request` uses `[<JIRA-PROJECT>-<JIRA-Ticket-Number>]` (key from `constitution-custom.mdc`); story id belongs in Technical Context |
| "ADRs / OpenAPI are SA-only" | SA and LB are co-equal; LB may author ADR bodies and OpenAPI |
| "Write components under architecture/components/" | New writes go to `nwob-docs/sdd/components/`; legacy path is read-only brownfield fallback |
| "Update architecture.md without masterplan.md" | Dual-persist both twins on every write |

---

## Material vs minor scope

| Change type | Required action |
|-------------|-----------------|
| **New iteration / epic slice** | Full `/orchestrate-design` → Builder `co-design-solution` → `validate-design-package` → Builder `trigger-ai-build` → `review-implementation` (per increment) → Builder `raise-merge-request` → `audit-and-approve-code` |
| **Design-only review** | `validate-design-package` only (requires `story-tasks.md` + per-story `story-tasks.md` (order from epic-spec) draft) |
| **Audit existing MR** | `audit-and-approve-code` only if upstream gates documented or re-verified |
| **Pasted GitLab comments** | Author: Builder `resolve-review-comments`; unfinished `story-tasks.md` IDs: Builder `trigger-ai-build` |
| **Single increment rework** | `review-implementation` on current task after Builder rework |
| **Design drift during build** | Stop review approval → route to `/orchestrate-design` or mirrored SA command/skill |
