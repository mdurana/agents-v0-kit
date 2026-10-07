---
name: feature-definition
description: >-
  Bridges strategy and execution by breaking initiatives into constitution-compliant
  epics, features, and user stories in epic-spec.md (backlog index + HL US/TS)
  and per-story story-spec.md files per US Readiness Rubric. Defines the
  11-column tickets.csv export contract consumed by /backlog. Use when an initiative
  is approved and the development team needs actionable work items with numbered
  acceptance criteria.
---

# Feature Definition

Command: `/features`

**Available on:** Product Owner, **Solution Architect**, and **Lead Builder** (SA and LB are co-equal with PO for `/features` authorship of `epic-spec.md` backlog index and `story-spec.md`).

## Overview

Bridges strategy and execution by breaking initiatives into actionable epics, features, and user stories per [constitution-core.mdc](../../../rules/constitution-core.mdc) Planning and story anatomy and the **US Readiness Rubric**.

Layer 1 — Author. Extends `epic-spec.md` with high-level US/TS and the chronological **backlog index**, and writes each `{stories_dir}/{STORY_ID}/story-spec.md`. Use [templates/sdd/spec-template.md](../../../templates/sdd/spec-template.md) for epic-spec structure (not retired `plan-template.md`). Does not group capabilities for decks (that is `presentation-content-extraction`). Does **not** emit `tickets.csv` or own Jira import constants — that is `/backlog`.

**Primary outputs:**
- `nwob-docs/sdd/epic-spec.md` — Problem, roadmap, HL US/TS, and chronological backlog index (ID, summary, size, dependencies, link to story-spec)
- `{stories_dir}/{STORY_ID}/story-spec.md` — canonical full story anatomy (Type, Summary, Description, numbered Gherkin AC, Dependencies, Size); default `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md`

**Export contract:** Documents the 11-column `tickets.csv` schema and column mapping below. `/backlog` applies engagement-specific params from `tickets-export-params.md` when generating the CSV for manual Jira import.

**Readiness gate:** Every story MUST pass the US Readiness Rubric before handoff to backlog/export. Stories that fail conditional criteria (API contracts, UI/UX evidence) are **not READY**.

**Boundary:** `/features` owns **initial authoring** — epics, features, and new user stories. Use `/backlog` for grooming, refinement, and Jira CSV export of **existing** items (see `backlog-management-and-refinement`).

## When to Use

- An initiative is approved and the development team needs actionable work items.
- Stories must be written as `story-spec.md` under `{stories_dir}/{STORY_ID}/` with numbered acceptance criteria and Fibonacci sizing, and indexed in `epic-spec.md`.
- Epics or features need **initial decomposition** into stories (not sprint grooming of existing items).
- **Net-new** epics/stories from roadmap themes (refinements on existing stories → `/backlog`).

**Do not use when:** Top-of-backlog grooming, DoR fixes, reprioritization, or Jira CSV export — use `/backlog` instead.

## Prerequisites

- `nwob-docs/sdd/epic-spec.md` has `## Roadmap`.
- If missing: **stop** → run `/roadmap`.

## Process

1. **Identify Epics:** Break roadmap themes into large bodies of work.
2. **Define Features & Functions:** Slice epics into standalone value units using **vertical slicing** — one complete user-visible path per story, not horizontal layers (schema-only, API-only). Apply **dependency-first ordering** (data/API before UI).
3. **Tag story segment:** Assign each story one or more segments — `API`, `Web`, `Mobile`, `DB`, `Config`, `Kafka`, `Integration` — to activate conditional rubric rows.
4. **Write User Stories:** Decompose features into outcome-based stories. For each story: lazy-create `{stories_dir}/{STORY_ID}/`, write full anatomy to `story-spec.md` from [templates/sdd/story-spec-template.md](../../../templates/sdd/story-spec-template.md), and add an index row to `epic-spec.md` (backlog index section). Default to one story per capability per owner; add numbered scenarios, not separate tickets, for edge cases unless size or ownership forces a split. Use the mandatory story template (below) in `story-spec.md`.
5. **Acceptance Criteria:** Write in numbered scenario format (see below) inside `story-spec.md`. Each scenario uses Given/When/Then sub-steps (`a.` / `b.` / `c.`). Each scenario must be atomic, measurable, and pass/fail demonstrable — no vague lines like "works as expected."
6. **Apply US Readiness Rubric:** Validate every story against all applicable rubric criteria (see below). Add negatives, preconditions, contracts, and testability details before handoff.
7. **Size Stories:** Per [product-owner-skill-boundaries.md](../../../references/rules/product-owner-skill-boundaries.md#shared-story-standards-both-features-and-backlog). Stories ≥ 5 SP must be decomposed into 2/3 SP increments where logically possible.
8. **Order in epic-spec.md:** Keep backlog index rows in strict chronological execution order — foundation/infra before UI/features. Sync Summary, Size, and Dependencies on each index row with the linked `story-spec.md`.
9. **Handoff:** Point the prompter to `/backlog` for grooming and parameterized Jira `tickets.csv` export when ready to import.

Stories are **product-level** in `story-spec.md` — no file paths, verify commands, or implementation tasks in product fields (technical annex and `story-tasks.md` belong to Builder `co-design-solution` and SA/LB `/orchestrate-design`). **Do not** generate `epic-spec.md` backlog index, `story-tasks.md`, or `story-spec.md` (technical annex).

### US Readiness Rubric (mandatory quality gate)

Every story MUST satisfy applicable criteria before it is backlog-ready. Use weights for prioritization during authoring; all **Always applies** rows are blocking for READY status.

| # | Criterion | Weight | Applies | Authoring requirement |
|---|-----------|--------|---------|----------------------|
| 1 | **Definition & completeness** (Ready for QA) | 18 | Always | Scope, ACs, preconditions, and technical/testability details are explicit — QA can start test design without guessing intent |
| 2 | **Refinement / Three Amigos alignment** | 16 | Always | Risks, negatives, and cross-functional needs (PO/Dev/QA) appear in the story — not happy-path only |
| 3 | **Acceptance criteria testability** | 16 | Always | Each AC maps to a pass/fail check with observable outcomes (HTTP status, DB state, message text, metric) |
| 4 | **Edge cases & negative scenarios** | 12 | Always | Errors, invalid input, boundaries, failure paths, and toggle-off states relevant to the story |
| 5 | **Demonstrability / desk check readiness** | 12 | Always | Happy path + key non-happy paths verifiable by PO/QA before formal QA; walkthrough or demo steps noted |
| 6 | **Automation & CI evidence** | 5 | Always | Unit/integration/API test intent, CI gate, or explicit coverage note — even lightweight |
| 7 | **Scope, integrations, toggles, environments** | 3 | Always | Feature flags, env constraints (SIT/UAT/prod), test data, whitelists, and integration prerequisites identifiable |
| 8 | **API contracts & traceability** | 12 | When segment includes **API** | `METHOD` + path, OpenAPI/Swagger ref, or request/response example in Description. **No contract → not READY** |
| 9 | **UI/UX design evidence** | 6 | When segment includes **Web** or **Mobile** | Figma link, flows, copy, or loading/error/empty states in Description or AC. Figma optional if AC + design notes suffice |

**READY rule:** A story is READY only when every applicable rubric row is satisfied. Conditional rows (#8 API, #9 UI/UX) block READY when the segment applies but evidence is missing.

**Where rubric content lands (`story-spec.md` and CSV export):**

| Rubric area | Primary field |
|-------------|----------------|
| Scope, preconditions, env/toggles, integrations (#1, #7) | **Description** |
| Three Amigos risks, automation notes (#2, #6) | **Description** |
| Testable ACs, negatives, desk-check scenarios (#3, #4, #5) | **Acceptance Criteria** |
| API contract (#8) | **Description** (`**API:**` bullet — when segment:API) |
| UI/UX evidence (#9) | **Description** (`**UI/UX:**` bullet — when segment:Web|Mobile) or **Acceptance Criteria** (state scenarios) |
| Segment tags | **Tags** on CSV export (e.g. `segment:API`, `segment:Web`) |

### Tickets.csv export contract (for `/backlog`)

`/features` does **not** write `tickets.csv`. `/backlog` emits the file using this schema and values from `nwob-docs/sdd/tickets-export-params.md`.

**`tickets.csv` columns (11 — use this order exactly):**

| # | Column |
|---|--------|
| 1 | Issue type |
| 2 | Parent ID |
| 3 | Summary |
| 4 | Description |
| 5 | Acceptance Criteria |
| 6 | Priority |
| 7 | Product |
| 8 | Capability |
| 9 | Tags |
| 10 | **Story Points** |
| 11 | **Assignee** |

| File | Format | Notes |
|------|--------|-------|
| `tickets.csv` (path from export params) | UTF-8 CSV | Quote fields containing commas or newlines |

### Column mapping — `tickets.csv`

Map `story-spec.md` fields (ordered via `epic-spec.md` backlog index) and rubric content into the 11 export columns. Parameterized fields come from `tickets-export-params.md` (resolved by `/backlog`).

| Column | Source / rule |
|--------|---------------|
| **Issue type** | From params `issue_type` — same value on every row |
| **Parent ID** | From params `parent_id` — same value on every row |
| **Summary** | Params `summary_prefix` + story one-line outcome; strip duplicate prefix if already in source |
| **Description** | Mandatory bullet list (see below); include all applicable fields; optional `**API:**` / `**UI/UX:**` when segment requires |
| **Acceptance Criteria** | Mandatory numbered scenario list (see below); happy path + applicable negatives per rubric #3–#5 |
| **Priority** | `High` / `Medium` / `Low` — default `Medium`; elevate from cost-of-delay if groomed |
| **Product** | From params `product` |
| **Capability** | Feature name from epic breakdown (e.g. `PG.2 Rollout Strategy Resolve`) |
| **Tags** | Story ID, `segment:*`, scope tags, squad (e.g. `AR-006`, `segment:API`, `scope:deployment-ms`) |
| **Story Points** | Fibonacci estimate from story `Size` — **integer only** (`1`, `2`, `3`, `5`, `8`); mandatory per row |
| **Assignee** | From params `assignee` — same value on every row unless overridden after handoff |

**Description format (mandatory — authoring and export):**

Use top-level markdown bullets with bold labels. **Scope** nests `In:` / `Out:` as sub-bullets. Include every row below; use `—` or `N/A` when a field does not apply.

```markdown
* **Scope:**
  * In: …
  * Out: …
* **Pre-conditions:** …
* **Dependencies:** …
* **Size:** … SP
* **Risks / Three Amigos notes:** …
* **Environment:** …
* **Automation:** …
* **Desk check:** …
```

**Conditional Description bullets** (add when segment applies — rubric #8 / #9):

```markdown
* **API:** <METHOD /path, OpenAPI ref, request/response example — when segment:API>
* **UI/UX:** <Figma link, flows, copy, states — when segment:Web|Mobile>
```

**Acceptance Criteria format (mandatory — authoring and export):**

Number each scenario. Use lettered sub-steps for Given / When / Then. Add `d. And …` (or further letters) for additional observable assertions in the same scenario.

```markdown
1. **Scenario: <name — happy path>**
   a. Given …
   b. When …
   c. Then …
   d. And …

2. **Scenario: <name — negative or edge case>**
   a. Given …
   b. When …
   c. Then …
```

**Row rules (applied by `/backlog` on export):**

- One CSV row = one story (multiple numbered scenarios stay in the **Acceptance Criteria** cell).
- **Issue type**, **Parent ID**, **Assignee**, and **Product** come from export params — not hardcoded in this skill.
- **Summary** starts with params `summary_prefix` on every exported row (empty prefix allowed).
- Story ID (e.g. `AR-001`) goes in **Tags** — not in the Summary prefix.
- **Description** and **Acceptance Criteria** use the mandatory list formats above — not flat `Key: value` lines or unnumbered Gherkin blocks.
- **Story Points** column is mandatory — Fibonacci integer; **Size** also appears in Description as `N SP` (both required).
- Subtasks (JPA / service / controller checklist) are **not** exported as rows.

| Level | Definition | Sprint-commit? | In export? |
|-------|------------|----------------|------------|
| **Epic** | Initiative-sized outcome spanning multiple features | No | **Parent ID** column (from params) |
| **Feature** | Standalone capability or bounded scope within an epic | No | **Capability** column |
| **Story** | Smallest item with all mandatory fields, rubric pass, and Fibonacci size | **Yes** | **One row** + **Story Points** column |
| **Subtask** | Tooling-only dev checklist (e.g. Jira subtasks) | No | Not exported |

**Rule:** Only **stories** are backlog / Definition of Ready items. Subtasks never replace story-level acceptance criteria in numbered scenario format.

### Story Slicing Rules

**Default:** Slice by **outcome** (API contract, persisted state, integration behavior), not by Spring layer (controller / service / repository).

**One story MAY include multiple numbered scenarios** when they are variants of the same capability (happy path + error paths), same owner, same PR boundary, and total size ≤ 5 SP.

**Decompose into separate stories when:**

- Estimated size ≥ 5 SP and can be split into 2/3 SP increments with incremental value
- Different bounded contexts or microservices (clear ownership handoff)
- Different sprints with explicit dependency (foundation → feature)
- Different verbs or deliverables that can ship independently (e.g. promote vs abort)

**Do NOT decompose into separate stories when:**

- Scenarios are error variants of the same endpoint and one dev owns the work
- Split would put multiple devs on the same handler/PR (merge conflict risk)

**Foundation exception (horizontal allowed):** Schema/migration and entity-repo stories are acceptable as prerequisite **technical stories** when:

- DDL and runtime writers have different team ownership, OR
- Migrations must land before application code, AND
- Downstream **vertical** stories explicitly own population / behavior (document in Dependencies and a population map)

**Layer work inside one story:** JPA, service, and controller steps may appear as **subtasks** in the tracker — implementation checklist only. Acceptance remains at the story level via numbered scenarios.

**Anti-pattern (red flag):** Separate **stories** for "create JPA", "create service", "create controller" with no story that proves the endpoint works end-to-end.

### Mandatory Story Template (authoring in story-spec.md)

Every story MUST include these fields during authoring (mapped to CSV columns on `/backlog` export):

```markdown
Type: User Story | Technical Story
Segment: API | Web | Mobile | DB | Config | Kafka | Integration (one or more)
Summary: <one-line goal — no product prefix in authoring; export prepends summary_prefix from params>
Description:
* **Scope:**
  * In: …
  * Out: …
* **Pre-conditions:** …
* **Dependencies:** …
* **Size:** … SP
* **Risks / Three Amigos notes:** …
* **Environment:** …
* **API:** … (required when Segment includes API)
* **UI/UX:** … (required when Segment includes Web or Mobile)
* **Automation:** …
* **Desk check:** …
Acceptance Criteria (AC):
1. **Scenario: <name — happy path>**
   a. Given …
   b. When …
   c. Then …
   d. And …

2. **Scenario: <name — negative or edge case>**
   a. Given …
   b. When …
   c. Then …
```

**Authoring note:** On CSV export, copy the numeric **Size** to **Story Points** (column 10) and retain `**Size:** N SP` in the **Description** bullet list. **Dependencies** in Description lists blocking story IDs only.

### Example — API story (rubric-compliant)

```markdown
Type: Technical Story
Segment: API
Summary: POST /api/v1/rollout/{deploymentId}/promote advances paused canary
Description:
* **Scope:**
  * In: Human promotion REST endpoint; Redis-only bridge — no cluster call.
  * Out: Cluster-side promotion execution (handled by Rollouts controller).
* **Pre-conditions:** 1. Deployment exists with rollout_phase CANARY_PAUSED. 2. Redis token status HOLD.
* **Dependencies:** AR-013
* **Size:** 2 SP
* **Risks / Three Amigos notes:** QA must seed Redis + DB; Dev confirms no v1 contract change.
* **Environment:** SIT/UAT; test deployment_id from fixture set ROLLOUT-PAUSED-001.
* **API:** POST /api/v1/rollout/{deploymentId}/promote — body: { actor, reason } — 200 on success, 409 when not paused. OpenAPI: deployment-ms v1.2.0.
* **Automation:** Integration test PromoteControllerIT; CI gate mvn verify.
* **Desk check:** Call endpoint via Postman with fixture ID; verify Redis token PROMOTE.
Acceptance Criteria (AC):
1. **Scenario: Promote at paused canary step**
   a. Given a deployment with rollout_phase CANARY_PAUSED and Redis token status HOLD
   b. When POST /api/v1/rollout/{deploymentId}/promote is called with actor and reason
   c. Then the Redis token status is updated to PROMOTE
   d. And HTTP 200 is returned

2. **Scenario: Promote rejected when not paused**
   a. Given a deployment with rollout_phase IN_PROGRESS
   b. When POST /api/v1/rollout/{deploymentId}/promote is called
   c. Then HTTP 409 Conflict is returned
   d. And the Redis token status remains unchanged
```

### Example — one story, multiple scenarios (preferred for single-dev endpoints)

Use this pattern when effective data lifecycle is soft-delete (the default). When sources specify hard-delete or alternate lifecycle, write AC that match the effective policy.

```markdown
Type: User Story
Segment: API
Summary: GET /api/v1/users/{id} returns user or appropriate 404
Description:
* **Scope:**
  * In: Read API for user lookup; enforces soft-delete policy.
  * Out: Write/update endpoints.
* **Pre-conditions:** 1. user table migrated. 2. Test user fixtures loaded.
* **Dependencies:** User entity and repository (foundation story if not yet present)
* **Size:** 2 SP
* **Risks / Three Amigos notes:** N/A
* **Environment:** SIT; soft-delete policy active.
* **API:** GET /api/v1/users/{id} — 200 + UserDTO | 404. OpenAPI: user-ms v1.
* **Automation:** UserControllerIT covers all three scenarios.
* **Desk check:** Hit endpoint with active, missing, and soft-deleted IDs.
Acceptance Criteria (AC):
1. **Scenario: Retrieve active user by ID**
   a. Given a user exists with deleted_at null
   b. When GET /api/v1/users/{id} is called
   c. Then HTTP 200 and the user DTO is returned

2. **Scenario: Unknown ID returns 404**
   a. Given no user exists for the ID
   b. When GET /api/v1/users/{id} is called
   c. Then HTTP 404 is returned

3. **Scenario: Soft-deleted user returns 404**
   a. Given a user exists with deleted_at populated
   b. When GET /api/v1/users/{id} is called
   c. Then HTTP 404 is returned
```

### 5-Point Cap Rule

Any story estimated at 5 Story Points or higher MUST be critically evaluated for decomposition. If logically possible, break into smaller 2 SP and 3 SP discrete stories that deliver incremental value.

When decomposing, split by **behavior or deliverable**, not by **technical layer**. Prefer: happy path now, audit trail next sprint — over: repository story then controller story.

## Constitution Compliance

**Mandatory:** All story template fields; numbered-scenario AC (Given/When/Then — Planning and story anatomy in constitution-core BDD); US Readiness Rubric pass; chronologically ordered backlog index in `epic-spec.md`; Description bullet list + numbered AC formats. Export schema documented for `/backlog`.

**Default-overridable:** Soft-delete scenarios included when effective data lifecycle is soft-delete (default). Adapt deletion AC when sources specify alternate lifecycle per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Gherkin AC can wait until dev starts" | Constitution section 4 + rubric #1/#3 require testable numbered scenarios before handoff; vague AC produces rework. |
| "This epic is one 8-point story" | 5-point cap forces decomposition; large stories block incremental delivery and hide risk. |
| "Dependencies can be figured out during the sprint" | Chronological `epic-spec.md` backlog index requires explicit dependencies upfront in Description. |
| "Write implementation tasks here" | Product anatomy in `story-spec.md`; technical annex + `story-tasks.md` → `co-design-solution` + SA/LB `/orchestrate-design`. |
| "/features is PO-only" | `/features` is also available on Solution Architect and Lead Builder. |
| "Refine existing story sizing in /features" | DoR fixes and decomposition → `/backlog`. |
| "We use subtasks for JPA / service / controller" | Fine as **in-sprint checklist** under one story with full numbered AC — not as separate export rows. |
| "One scenario per ticket is cleaner" | Cleaner for the board, worse for delivery if one dev ships one endpoint. Multiple scenarios per story is the default for same-PR work. |
| "DB and code must be separate tickets" | Acceptable for **foundation** prerequisites with explicit downstream writers — not as the primary pattern for every feature. |
| "Vertical slices mean many small tickets per endpoint" | Vertical means **outcome-based acceptance**, not one ticket per HTTP status code. |
| "Emit tickets.csv from /features" | Jira import constants and CSV emit belong to `/backlog` with `tickets-export-params.md`. |
| "Flat Description or legacy unnumbered Gherkin blocks are fine" | **Description** must use bullet list; **AC** must use numbered scenarios with `a.`/`b.`/`c.` sub-steps. |
| "API contract can be added during dev" | Rubric #8 blocks READY without METHOD + path or OpenAPI ref on API-segment stories. |
| "Negatives will be tested later" | Rubric #4 requires negative/edge scenarios in AC before handoff — not post-build. |
| "Three Amigos happens in refinement meeting" | Rubric #2 requires risks and cross-functional needs **in the story text**, not meeting notes only. |

## Red Flags

- Separate **stories** sliced by layer only (JPA / service / controller) with no end-to-end acceptance story.
- Acceptance criteria not in numbered scenario format (missing `1. **Scenario:**` or `a.`/`b.`/`c.` sub-steps).
- **Description** not using mandatory bullet list (`* **Scope:**`, `* **Size:**`, etc.).
- Vague AC lines ("works as expected", "handles errors gracefully") — rubric #3 failure.
- Happy-path-only stories with no negative or edge scenarios — rubric #4 failure.
- API-segment story missing `**API:**` bullet (METHOD + path or OpenAPI) — rubric #8 failure, **blocks READY**.
- Web/Mobile-segment story missing UI states or design reference — rubric #9 failure.
- Missing preconditions, environment, or test data notes — rubric #1/#7 failure.
- No automation or desk-check notes — rubric #5/#6 failure.
- Stories ≥ 5 SP without decomposition justification.
- UI/feature stories placed before foundation/infrastructure stories in the `epic-spec.md` backlog index.
- `/features` writing `tickets.csv` or hardcoding Jira Parent ID / Summary prefix / Assignee.

## Verification

### Authoring & slicing

- [ ] Prerequisite: ## Roadmap exists in `epic-spec.md`?
- [ ] Stories written to `{stories_dir}/{STORY_ID}/story-spec.md` and indexed in `nwob-docs/sdd/epic-spec.md` (not CSV-only)?
- [ ] Features sliced vertically by outcome (not layer completion)?
- [ ] Error/happy-path variants grouped in one story when same owner/PR?
- [ ] All mandatory story template fields present for every `story-spec.md`?
- [ ] **Description** uses bullet list with `* **Scope:**` (In/Out), `* **Size:**`, and other mandatory fields?
- [ ] **Acceptance Criteria** uses numbered scenarios with `a.` Given / `b.` When / `c.` Then sub-steps?
- [ ] Stories ordered chronologically in `epic-spec.md` backlog index (foundation/infra first)?
- [ ] No story ≥ 5 SP without decomposition justification?
- [ ] Prompter directed to `/backlog` for Jira CSV when import is needed?

### US Readiness Rubric (per story)

- [ ] **#1 Definition & completeness** — Scope, preconditions, and testability details explicit; QA can design tests without guessing?
- [ ] **#2 Three Amigos** — Risks, negatives, and cross-functional needs documented in Description?
- [ ] **#3 AC testability** — Every scenario has observable pass/fail outcomes (status code, DB state, message)?
- [ ] **#4 Edge cases & negatives** — Invalid input, failure paths, and boundaries covered in AC?
- [ ] **#5 Demonstrability** — Desk-check steps documented; key non-happy paths verifiable pre-QA?
- [ ] **#6 Automation & CI** — Test intent or CI gate noted in Description?
- [ ] **#7 Scope & environments** — Flags, envs, test data, and integration prerequisites identifiable?
- [ ] **#8 API contracts** — When `segment:API`: METHOD + path and OpenAPI/example present?
- [ ] **#9 UI/UX evidence** — When `segment:Web|Mobile`: flows, copy, or states documented?
