# Pod Builder Skill Boundaries

Shared segregation rules for the unified build pod persona. Skills span `skills/lead-builder/` and `skills/builder/` (**seven** skills total — **no** `orchestrate-design`). Persona: [agents/pod-builder.md](../../agents/pod-builder.md). Assigned-story sessions: [docs/guides/assigned-story-workflow.md](../../docs/guides/assigned-story-workflow.md). Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

**Reference skill mapping:** Patterns from `references/agent-skills-main` are embedded via supporting rule files — do not invoke reference skills directly when an nwob skill or embed covers the intent. Full mapping: [agent-skills-main-mapping.md](agent-skills-main-mapping.md).

For split-persona engagements, see [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md) and [builder-skill-boundaries.md](builder-skill-boundaries.md). Design orchestration (`/orchestrate-design`) belongs to **SA or LB** — not Pod Builder.

---

## Model: Co-design → Validate → Build → Review → Draft MR → Audit → Resolve

| Layer | Purpose | Skills |
|-------|---------|--------|
| **1 — Co-design** | Annexes and `story-tasks.md` bodies (no design orchestration) | `co-design-solution` |
| **2 — Validate** | Independent design-package build-readiness sign-off | `validate-design-package` |
| **3 — Build** | SDD gate; Session 2 plan overlay; Session 3 incremental implementation | `trigger-ai-build` |
| **4 — Review** | Per-increment validation during build | `review-implementation` |
| **5 — Draft MR** | Draft GitLab MR copy; no git mutate | `raise-merge-request` |
| **6 — Audit** | Holistic MR QC before external QA (Session 5 peer) | `audit-and-approve-code` |
| **7 — Resolve** | Address pasted GitLab comments after REQUEST CHANGES | `resolve-review-comments` |

**Rule:** Pod Builder **MUST NOT** author `epic-spec.md`, `masterplan.md`, `architecture.md`, `sdd/components/**`, ADR bodies, or OpenAPI. Pod Builder **MUST NOT** invoke `orchestrate-design`. Gate skills must run as **separate invocations** with persisted sign-off output. Prompt `tasks.md` **maps to** `story-tasks.md`.

---

## Skill-hat discipline

The pod-builder persona owns seven skills but **must not collapse producer and validator roles** into a single pass.

| Gate skill | Required behavior |
|------------|-------------------|
| `validate-design-package` | Load skill after `co-design-solution` completes; persist sign-off to annex Sign-off or `{STORY_ID}-design-validation.md` — do not proceed to `trigger-ai-build` on self-assessment alone |
| `review-implementation` | Load skill after each `story-tasks.md` increment; output approval or rework request before next task |
| `raise-merge-request` | Load after last increment Approved; draft title, body, and branches; author stops — do not audit |
| `audit-and-approve-code` | Session 5 **peer** loads after the human opens the MR on `MR_BRANCH`; co-load `builder-quality-patterns.md`; inspect branch with git; print GitLab review draft; do not post |
| `resolve-review-comments` | Session 6 author after REQUEST CHANGES; co-load `merge-request-patterns.md`; pasted comments; git after user yes; unfinished `story-tasks.md` IDs → `trigger-ai-build` |

**Author vs peer:** Sessions 1–4 (+ Session 6) author must not self-audit. Session 5 is a different developer.

**Audit rework:** When audit requests changes, author uses `resolve-review-comments` for pasted comments; unfinished `story-tasks.md` IDs use `trigger-ai-build` (Session 3). Peer re-runs `/audit` after push.

---

## Unified workflow (assigned-story sessions)

```
Session 0  Phase 0 readiness
Session 1  co-design-solution → validate-design-package
Session 2  trigger-ai-build (Plan mode — proposals, stop)
Session 3  trigger-ai-build (Build mode) → review-implementation  (repeat per todo)
Session 4  raise-merge-request  (author stops)
Session 5  audit-and-approve-code /audit  (peer)
Session 6  resolve-review-comments  → loop to Session 5
```

| Session | Skill | Pod Builder action |
|---------|-------|-------------------|
| 1 — Co-design | `co-design-solution` | Annex with `story-tasks.md` IDs; write `story-tasks.md` bodies; do **not** run `orchestrate-design` or author architecture/masterplan/components/ADRs/OpenAPI |
| 1 — Validate | `validate-design-package` | **Stop** — persist sign-off before Session 2 |
| 2 — Plan | `trigger-ai-build` (Plan) | Execution plan + Locked research proposals; stop |
| 3 — Build | `trigger-ai-build` (Build) + `review-implementation` | One todo per turn; **Stop** per increment |
| 4 — Draft MR | `raise-merge-request` | Draft only; **Stop** — no audit |
| 5 — Audit | `audit-and-approve-code` | **Peer only** — no external QA until audit passes |
| 6 — Resolve | `resolve-review-comments` | Pasted comments only; ask before git; loop to Session 5 |

**Upstream design index:** Thin per-story `story-tasks.md` (order from epic-spec) and system architecture dual-persist are produced by **SA or LB** `/orchestrate-design` (and SA/LB architecture commands) before or beside Session 1 — not by Pod Builder.

---

## SDD handoff chain

```
PO/SA/LB: /features          SA ∨ LB                         Pod Builder
         │                      │                                  │
         ▼                      ▼                                  ▼
    epic-spec.md backlog index (stories)  /orchestrate-design → design package   co-design-solution → story-tasks.md
         │                  design package + dual-persist arch            │
         │                              │                                  ▼
         │                              └──────────► validate-design-package (GATE)
         │                                                  │
         └────────────────── trigger-ai-build (plan → build)┘
                                        │
                         review-implementation (per increment, GATE)
                                        │
                         raise-merge-request (Session 4)
                                        │
                         audit-and-approve-code (Session 5 peer, GATE)
                                        │
                         resolve-review-comments (Session 6, if REQUEST CHANGES)
```

| Artifact | Owner | Pod Builder role |
|----------|-------|------------------|
| `nwob-docs/sdd/epic-spec.md` | PO **or** SA **or** LB | Read only — **MUST NOT** author |
| `nwob-docs/sdd/epic-spec.md` (backlog index) | PO **or** SA **or** LB | Read only — **MUST NOT** author |
| `{stories_dir}/{STORY_ID}/story-spec.md` | PO/SA/LB primary; PB co-author | May create/update via `co-design-solution` when blocking design; Gherkin required; flag material AC changes for PO |
| technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | `co-design-solution` | Write annex; fill subtask `story-tasks.md` ID column |
| `{stories_dir}/{STORY_ID}/story-tasks.md` | `co-design-solution` | Author full task bodies; prompt `tasks.md` → this path |
| Design sign-off | `validate-design-package` | Annex Sign-off section or `{STORY_ID}-design-validation.md` |
| Cursor execution plan (`~/.cursor/plans/`) | `trigger-ai-build` | Overlay after validate sign-off; not SDD |
| `nwob-docs/sdd/design-notes.md` | SA **or** LB — `/orchestrate-design` | Read only |
| `nwob-docs/architecture/architecture.md` ↔ `sdd/masterplan.md` | SA **or** LB | Read only — **MUST NOT** author |
| `nwob-docs/sdd/components/{component-name}-plan.md` | SA **or** LB | Read only — **MUST NOT** author |
| `nwob-docs/architecture/adr/`, OpenAPI | SA **or** LB | Read only — **MUST NOT** author |
| `nwob-docs/diagrams/sequences/` | SA / LB | Reference in design package |
| Application code | `trigger-ai-build` | Review per increment; peer audits MR holistically |
| GitLab MR | `raise-merge-request` | Author drafts copy; human opens the MR; peer verifies in audit |

---

## Canonical source map

| Content pillar | Authoritative source | Author skill | Validated by |
|----------------|---------------------|--------------|--------------|
| Product stories / Gherkin AC | `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from `epic-spec.md` backlog index) | PO `/features`, `/backlog` (primary); SA/LB `/features`; PB `co-design-solution` (co-author only) | `validate-design-package`, `review-implementation`, `audit-and-approve-code` |
| Story task bodies | `{stories_dir}/{STORY_ID}/story-tasks.md` | `co-design-solution` | `validate-design-package`, `review-implementation` |
| Technical annex | technical annex in `{stories_dir}/{STORY_ID}/story-spec.md` | `co-design-solution` | `validate-design-package` |
| Execution overlay | `~/.cursor/plans/` | `trigger-ai-build` | `review-implementation` (per todo / `story-tasks.md` ID) |
| Architecture / masterplan | `architecture.md` ↔ `masterplan.md` | SA **or** LB only | `validate-design-package`, `audit-and-approve-code` |
| Component spec / plan | `sdd/components/{component-name}-plan.md` | SA **or** LB only | `validate-design-package` |
| Application code | Code repo roots | `trigger-ai-build` | `review-implementation`, `audit-and-approve-code` |
| Pipeline YAML | Code repo CI roots | `trigger-ai-build` (primary) | `audit-and-approve-code` (verify gates) |

---

## PO vs Pod Builder decision table

| Situation | Owner | Examples |
|-----------|-------|----------|
| Net-new user story with Gherkin AC | PO `/features` (or SA/LB `/features`) | First story for a roadmap theme |
| Re-prioritize or refine existing story | PO `/backlog` | Gherkin rewrite, story split |
| Missing Gherkin or six story fields | Prefer PO `/features` or `/backlog`; PB may co-author `story-spec.md` in Session 1 when blocking design (flag for PO) | Stop only when epic-spec backlog row or story-spec missing |
| Implementation task with file paths and verify command | `co-design-solution` → `story-tasks.md` | "Add Flyway V003 + repository method" |
| Vertical slice at product level | PO `/features` | One user-visible path per story |
| Vertical slice at implementation level | `co-design-solution` | Task completes one story path through stack |
| Architecture decision (ADR, contract, masterplan, components) | SA **or** LB `/pattern`, `/adr`, `/contracts`, `/orchestrate-design` | Pod Builder does **not** author |
| OpenAPI / service boundary design | SA **or** LB `architecture-delivery-enablement` | Route to SA/LB; do not duplicate OpenAPI |

**Never** put file paths, verify commands, or implementation sequencing in `epic-spec.md` (backlog index). **Never** put product Gherkin AC only in `story-tasks.md` without traceability to `epic-spec.md` (backlog index).

---

## SA / LB vs Pod Builder

| SA **or** LB (co-equal) | Pod Builder |
|-------------------------|-------------|
| Authors ADRs, OpenAPI, `architecture.md` ↔ `masterplan.md`, `sdd/components/**` | Reads only — **MUST NOT** author |
| `/orchestrate-design` → thin per-story `story-tasks.md` (order from epic-spec) + design package | Session 1 starts at `co-design-solution` — no `orchestrate-design` |
| `/features` available | Does not own `/features` |
| Does not implement application code | Directs AI implementation during `trigger-ai-build` |

---

## Pod Builder vs Product Owner

| Pod Builder | PO |
|-------------|-----|
| Reads `epic-spec.md` and `epic-spec.md` (backlog index) for traceability | Authors `epic-spec.md` and `epic-spec.md` (backlog index) (also SA/LB) |
| Verifies Gherkin AC satisfaction in code; may co-author `story-spec.md` when blocking design | Owns story anatomy and acceptance criteria (primary) |
| Does not rewrite `epic-spec.md` (backlog index) | Does not author `story-tasks.md` or validate MRs |

---

## Pod Builder vs Solution Architect / Lead Builder (validation role)

| SA **or** LB | Pod Builder (gate skills) |
|--------------|---------------------------|
| Defines API contracts, security boundaries, SLO targets | Verifies implementation matches contracts and boundaries |
| Authors ADRs and deprecation policy | Routes ADR gaps to SA/LB — does not author ADRs |
| Sets performance budgets and caching strategy | Validates N+1 and pagination fixes in review/audit |
| Specifies CI gate definitions (coverage, ArchUnit) | Verifies gates pass in `audit-and-approve-code` |

---

## Topic ownership

| Topic | SA / LB skills | Gate / validation skills |
|-------|----------------|--------------------------|
| Performance SLOs and budgets | SA/LB `production-operations` | Validates code-level fixes in `review-implementation`, `audit-and-approve-code` |
| Caching strategy and N+1 design | SA/LB `distributed-systems-architecture` | Validates N+1 and pagination fixes |
| Platform IAM, network, secrets | SA/LB `distributed-systems-architecture` | Verifies authz, validation, log sanitization |
| Application code, handlers, UI | `trigger-ai-build` | `review-implementation`, `audit-and-approve-code` |
| Pipeline YAML | `trigger-ai-build` (primary) | Verifies gates pass in `audit-and-approve-code` |
| Security policy patterns | SA/LB `architecture-delivery-enablement` | Verify controls in handlers and middleware |
| Deprecation decision and ADR | SA/LB `architecture-governance` | Execute migration per `story-tasks.md`; validate in review/audit |
| Frontend component patterns | `trigger-ai-build` via [build-execution-patterns.md](build-execution-patterns.md) | Co-design shapes test/UI strategy; review verifies UI AC |
| E2E / browser verification | — | Optional smoke during `review-implementation`; optional E2E before QA after audit (MCP required) |
| Git MR hygiene | `raise-merge-request` drafts MR copy | `audit-and-approve-code` verifies traceability and atomic history |

---

## Per-skill boundaries

| Skill | Writes | Must NOT |
|-------|--------|----------|
| `co-design-solution` | technical annex in `story-spec.md` + `story-tasks.md`; co-author `story-spec.md` when annex needs it | Author per-story `story-tasks.md` (order from epic-spec), `epic-spec.md`, `masterplan.md`, `architecture.md`, `sdd/components/**`, ADRs, OpenAPI; invoke `orchestrate-design`; sign off design |
| `validate-design-package` | Sign-off or gap list | Produce architecture or story bodies; run `/orchestrate-design` as owner; start build |
| `trigger-ai-build` | Application code, Cursor overlay | Skip `review-implementation` per increment; self-approve design package; self-audit |
| `review-implementation` | Per-increment approval or rework request | Holistic MR audit; skip to next task without approval |
| `raise-merge-request` | Draft title, body, and branch names | Approve, merge, audit; commit, push, or GitLab APIs |
| `resolve-review-comments` | Clone code for pasted MR comments; reply draft; git after user yes | Approve, merge, audit; author `story-tasks.md`/per-story `story-tasks.md` (order from epic-spec); unfinished IDs here; post to GitLab |
| `audit-and-approve-code` | `audit-report.md`; GitLab review draft | Per-increment review only; implement fixes; post to GitLab; approve/merge via agent; author ADRs/architecture |

---

## Reference embed files

| Embed | Source reference skill | Used in |
|-------|------------------------|---------|
| [task-breakdown-patterns.md](task-breakdown-patterns.md) | `planning-and-task-breakdown` | `co-design-solution` |
| [build-execution-patterns.md](build-execution-patterns.md) | `incremental-implementation`, `test-driven-development`, `context-engineering`, `source-driven-development`, `frontend-ui-engineering` | `trigger-ai-build` |
| [builder-quality-patterns.md](builder-quality-patterns.md) | `code-review-and-quality`, `debugging-and-error-recovery`, `code-simplification`, `git-workflow-and-versioning`, `browser-testing-with-devtools`, `performance-optimization`, `security-and-hardening` | `review-implementation`, `audit-and-approve-code` (Session 5 co-load) |
| [merge-request-patterns.md](merge-request-patterns.md) | `git-workflow-and-versioning` | `raise-merge-request`, `resolve-review-comments` (Sessions 4 and 6 co-load) |

**Do not** load `references/agent-skills-main/skills/*/SKILL.md` directly during pod-builder engagement when an embed exists.

---

## Doubt-driven checkpoint (user-orchestrated only)

Reference `doubt-driven-development` is **not** embedded in pod-builder skills. Personas must **not** spawn subagent adversarial reviewers.

**When the user may invoke it:**

- Before Step 2 sign-off (high-risk architecture, irreversible data migration)
- Between major increments during build (security-sensitive logic, public API change)
- When correctness matters more than speed and user explicitly requests adversarial review

**Pod Builder behavior:** Offer the checkpoint at design handoff or when detecting high blast-radius scope; defer to user to orchestrate fresh-context review. Continue with standard gate skills for routine validation.

---

## Intent → skill routing

| Intent | Skill |
|--------|-------|
| Design workshop; implementation feasibility; annex + `story-tasks.md` | `co-design-solution` |
| Fill per-story annex under `stories_dir` | `co-design-solution` |
| Design package + `story-tasks.md` draft ready for build sign-off | `validate-design-package` |
| Session 2 — execution plan and Locked research proposals | `trigger-ai-build` (Plan mode) |
| Session 3 — implement one todo | `trigger-ai-build` (Build mode) |
| Resume build from existing `story-tasks.md` | `trigger-ai-build` (Build mode) only |
| Task or increment complete during build | `review-implementation` |
| Last increment approved; draft GitLab MR copy | `raise-merge-request` |
| Address pasted GitLab review comments after `/audit` | `resolve-review-comments` |
| MR ready for formal QC before external QA (Session 5 peer) | `audit-and-approve-code` |
| Peer named an MR branch (including brownfield) | `audit-and-approve-code` only |
| design package or architecture dual-persist needed | Route to SA **or** LB `/orchestrate-design` / architecture commands — **not** Pod Builder |

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "I'll run orchestrate-design in Session 1" | Pod Builder Session 1 is `co-design-solution` → `validate-design-package`; SA/LB owns `/orchestrate-design` |
| "epic-spec.md backlog index is enough — skip task artifacts" | Derive `story-tasks.md` via `co-design-solution`; SA/LB maintains per-story `story-tasks.md` (order from epic-spec) via `/orchestrate-design` |
| "Persist the Cursor plan under nwob-docs/" | Overlay lives in `~/.cursor/plans/` only |
| "Skip `validate-design-package` — I just wrote story-tasks.md" | Run validate as separate skill invocation with explicit sign-off |
| "Increments passed — skip MR draft" | Session 4 is `raise-merge-request`; peer Session 5 audits |
| "Self-audit after Session 4" | Session 5 is a peer developer |
| "Fold MR into trigger-ai-build" | Session 4 is `raise-merge-request` |
| "Use resolve-review-comments for unfinished story-tasks.md IDs" | Unfinished IDs → Session 3 `trigger-ai-build` |
| "I'll author architecture.md / masterplan / ADRs in Session 1" | Route to SA **or** LB — Pod Builder MUST NOT author those |
| "Add stories to `story-tasks.md` without `epic-spec.md` (backlog index) trace" | Route to PO `/features` or `/backlog` (or SA/LB `/features`) for product stories |
| "Rewrite `epic-spec.md` (backlog index) during design" | PO/SA/LB own `epic-spec.md` (backlog index); PB does not rewrite |
| "Spawn doubt-driven reviewer from pod-builder persona" | User-orchestrated only; use standard gate skills |
| "Store architecture in `docs/architecture.md`" | Use `nwob-docs/architecture/` ↔ `sdd/masterplan.md` per sdd-artifact-layout |
| "Fix code while running audit skill" | Author uses `resolve-review-comments`; unfinished IDs use `trigger-ai-build` |

---

## Material vs minor scope

| Change type | Required action |
|-------------|-----------------|
| **New iteration / epic slice** | Sessions 1 → 2 → 3 (per todo) → 4 → 5 (peer); ensure SA/LB `/orchestrate-design` index exists upstream |
| **Resume mid-build** | `trigger-ai-build` (Build) only if SDD + design sign-off still valid |
| **Design drift detected during build** | Stop build → route to SA **or** LB `/orchestrate-design` or architecture command |
| **Single task retry** | `trigger-ai-build` (Build) on current task after `review-implementation` rework |
| **Design-only review** | `validate-design-package` only (requires `story-tasks.md` draft; per-story `story-tasks.md` (order from epic-spec) from SA/LB) |
| **Draft MR only** | `raise-merge-request` only after last increment approved |
| **Pasted GitLab comments** | `resolve-review-comments` only; loop to Session 5 |
| **Audit existing MR** | `audit-and-approve-code` only if upstream gates documented or re-verified |
