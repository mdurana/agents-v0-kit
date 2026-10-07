# Builder Skill Boundaries

Shared segregation rules for Builder skills in `skills/builder/`. Persona: [agents/builder.md](../../agents/builder.md). Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md). Lead Builder handoffs: [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

**Reference skill mapping:** Patterns from `references/agent-skills-main` are embedded via supporting rule files — do not invoke reference skills directly when an nwob skill or embed covers the intent. Full mapping: [agent-skills-main-mapping.md](agent-skills-main-mapping.md).

---

## Model: Co-design → Build → Draft MR → Resolve

| Layer | Purpose | Skills |
|-------|---------|--------|
| **1 — Co-design** | Implementation annex and `story-tasks.md` bodies | `co-design-solution` |
| **2 — Build** | SDD gate, AI-assisted implementation, quality gates | `trigger-ai-build` |
| **3 — Draft MR** | Draft GitLab MR copy; do not audit | `raise-merge-request` |
| **4 — Resolve** | Address pasted GitLab review comments; do not audit | `resolve-review-comments` |

**Rule:** No Builder skill may **author** ADR bodies, OpenAPI, `architecture.md` ↔ `masterplan.md`, or `sdd/components/**` as primary owner (SA **or** LB author those — co-equal), **validate** design packages, **review** increments, **audit** MRs, or **replace** SA/LB `/orchestrate-design`, review, or audit gates. `co-design-solution` is primary author of technical annex in `story-spec.md` and `story-tasks.md`; SA/LB may also co-author those via `/orchestrate-design` / `co-design-solution`. Only SA **or** LB `/orchestrate-design` may **author** the design package. Prompt `tasks.md` **maps to** `story-tasks.md`. Builder `co-design-solution` may co-author `story-spec.md` when annex work requires complementary detail; do not author system architecture twins.

---

## SDD handoff chain

```
PO/SA/LB: /features          SA ∨ LB                              Builder
         │                              │                                 │
         ▼                              ▼                                 ▼
    epic-spec.md backlog index (stories)    /orchestrate-design → design package    co-design-solution
         │                    (design package + dual-persist arch)       (annex + story-tasks.md)
         │                    design package                  validate-design-package (SA/LB)
         │                              ▼                            ▼
         └────────────────── trigger-ai-build ←──────────────────────┘
                                        │
                         review-implementation (SA/LB, per story-tasks.md ID)
                                        │
                         raise-merge-request (draft)
                                        │
                         audit-and-approve-code (SA/LB /audit → QA)
                                        │
                         resolve-review-comments (Builder, if changes requested)
```

| Artifact | Owner | Builder role |
|----------|-------|--------------|
| `nwob-docs/sdd/epic-spec.md` | PO **or** SA **or** LB | Read only |
| `nwob-docs/sdd/epic-spec.md` (backlog index) | PO **or** SA **or** LB | Read only; trace Gherkin AC in annex and build |
| `{stories_dir}/{STORY_ID}/story-tasks.md` | Builder primary; SA/LB co-author | Author full task bodies; implement per item in `trigger-ai-build`; prompt `tasks.md` → this path |
| technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | Builder primary; SA/LB co-author | Write annex during design workshop; fill all five subtask columns including `story-tasks.md` ID |
| `{stories_dir}/{STORY_ID}/story-spec.md` | PO/SA/LB primary; Builder co-author | May update via `co-design-solution` when needed; Gherkin required; flag material AC changes for PO |
| Cursor execution plan (`~/.cursor/plans/`) | Builder — `trigger-ai-build` | Overlay after `validate-design-package`; not SDD |
| `nwob-docs/sdd/design-notes.md` | SA **or** LB — `/orchestrate-design` | Read for context during co-design |
| `nwob-docs/architecture/architecture.md` ↔ `sdd/masterplan.md`, `sdd/components/{component-name}-plan.md` | SA **or** LB | Read for constraints; do not author twins, ADRs, or OpenAPI |
| Application code | Builder — `trigger-ai-build` | Author and verify per increment; `resolve-review-comments` may edit **only** to address pasted MR comments |
| GitLab MR draft | Builder — `raise-merge-request` | After last increment; do not audit |

---

## Canonical source map

| Content pillar | Authoritative source | Author skill | Validated by |
|----------------|---------------------|--------------|--------------|
| Product stories / Gherkin AC | `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from `epic-spec.md` backlog index) | PO `/features`, `/backlog`; SA/LB `/features` | SA/LB `validate-design-package`, `review-implementation`, `audit-and-approve-code` |
| Task bodies / IDs | `{stories_dir}/{STORY_ID}/story-tasks.md` | `co-design-solution` | SA/LB `validate-design-package`, `review-implementation` |
| Co-design input / story annex | technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | `co-design-solution` | SA/LB `/orchestrate-design`, `validate-design-package` |
| Application code | Code repo roots | `trigger-ai-build` | SA/LB `review-implementation`, `audit-and-approve-code` |
| GitLab MR | Draft title, body, and branch names | `raise-merge-request` | SA/LB `audit-and-approve-code` |
| GitLab review replies | Pasted review text; reply draft | `resolve-review-comments` | SA/LB re-runs `/audit` |

---

## Builder vs Lead Builder / Solution Architect

| Builder | SA **or** LB (co-equal) |
|---------|-------------------------|
| Primary author of technical annex and `story-tasks.md` during design workshop | Orchestrates strategy via `/orchestrate-design`; design package; may co-author technical annex / `story-tasks.md` / `story-spec`; authors architecture ↔ masterplan, components, ADRs, OpenAPI |
| Executes AI-assisted implementation from `story-tasks.md` | Independently signs off design package before build |
| Drafts GitLab MR copy after all increments complete | Reviews each increment before advance |
| Resolves pasted GitLab review comments (`resolve-review-comments`) | Audits MR holistically before QA; does not implement |
| Does not invoke `/orchestrate-design`, `validate-design-package`, `review-implementation`, or `audit-and-approve-code` as owner | Does not invoke `trigger-ai-build`, `raise-merge-request`, or `resolve-review-comments` as owner |
| Does not author ADRs / OpenAPI / masterplan / components | Full author of those artifacts (co-equal SA ↔ LB) |

---

## Intent → skill routing

| Intent | Skill |
|--------|-------|
| Design workshop; implementation feasibility after `/orchestrate-design` | `co-design-solution` |
| Fill per-story annex and write `story-tasks.md` | `co-design-solution` |
| Design complete; user requests implementation | `trigger-ai-build` |
| Cursor execution plan after design sign-off | `trigger-ai-build` |
| Resume build from existing `story-tasks.md` | `trigger-ai-build` |
| Last increment approved; draft GitLab MR copy | `raise-merge-request` |
| Address pasted GitLab review comments after `/audit` | `resolve-review-comments` |

---

## Per-skill boundaries

| Skill | Writes | Must NOT |
|-------|--------|----------|
| `co-design-solution` | technical annex in `{stories_dir}/{STORY_ID}/story-spec.md`; `{stories_dir}/{STORY_ID}/story-tasks.md`; optional `story-spec.md` co-author | Author design package; produce ADRs/OpenAPI/masterplan/architecture/components; orchestrate SA commands; sign off design; leave `story-tasks.md` ID column blank on any subtask row |
| `trigger-ai-build` | Application code; Cursor plan in `~/.cursor/plans/` | Author `story-tasks.md` or per-story `story-tasks.md` (order from epic-spec); validate design package; review own increments; draft MR copy; audit |
| `raise-merge-request` | Draft title, body, and branch names | Approve, merge, or audit; commit, push, or GitLab APIs |
| `resolve-review-comments` | Clone code limited to pasted MR comments; reply draft; git after user yes | Approve, merge, or audit; author epic-level task index files or ADRs; expand beyond comments; implement unfinished `story-tasks.md` IDs; post to GitLab |

---

## Reference embed files

| Embed | Source reference skill | Used in |
|-------|------------------------|---------|
| [task-breakdown-patterns.md](task-breakdown-patterns.md) | `planning-and-task-breakdown` | `co-design-solution` |
| [build-execution-patterns.md](build-execution-patterns.md) | `incremental-implementation`, `test-driven-development`, `source-driven-development`, `frontend-ui-engineering` | `trigger-ai-build` |
| [merge-request-patterns.md](merge-request-patterns.md) | `git-workflow-and-versioning` | `raise-merge-request`, `resolve-review-comments` |
| [builder-quality-patterns.md](builder-quality-patterns.md) | `code-review-and-quality`, etc. | SA/LB `review-implementation`, `audit-and-approve-code` (Builder reads for context only) |

**Do not** load `references/agent-skills-main/skills/*/SKILL.md` directly during Builder engagement when an embed exists.

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "I'll validate the design package during co-design" | Co-design produces the annex and `story-tasks.md`; SA/LB `validate-design-package` is independent sign-off |
| "Increments passed — skip MR audit" | Holistic audit catches integration gaps; SA/LB runs `audit-and-approve-code` |
| "Builder can orchestrate SA commands" | Route to SA **or** LB `/orchestrate-design` for design coordination |
| "Fold MR draft into trigger-ai-build" | Use `raise-merge-request`; separate session |
| "Run /audit on own MR" | Session 5 is another developer as Lead Builder (or mirrored SA audit skill) |
| "Fix comments under /audit" | Author uses `resolve-review-comments`; auditor does not implement |
| "Invoke reference `test-driven-development` directly" | TDD is embedded in `trigger-ai-build` via build-execution-patterns |
| "I'll write architecture.md / ADRs during co-design" | Route to SA **or** LB — Builder does not author those |

---

## Material vs minor scope

| Change type | Required action |
|-------------|-----------------|
| **New iteration / epic slice** | Full chain: `co-design-solution` → SA/LB `/orchestrate-design` index refresh → SA/LB `validate-design-package` → `trigger-ai-build` → SA/LB `review-implementation` (per increment) → `raise-merge-request` → SA/LB `audit-and-approve-code` |
| **Co-design only** | `co-design-solution` only |
| **Resume mid-build** | `trigger-ai-build` only if SDD + design package still valid |
| **Draft MR only** | `raise-merge-request` only after last increment approved |
| **Pasted GitLab comments** | `resolve-review-comments` only; unfinished `story-tasks.md` IDs still use `trigger-ai-build` |
| **Design drift during build** | Stop build → route to SA **or** LB `/orchestrate-design` or architecture command/skill |
