> **RETIRED PATH:** Do **not** write `story-plan.md`. Copy annex sections into `{stories_dir}/{STORY_ID}/story-spec.md` under `## Technical design annex`. This file remains a section-pattern reference only.

# Story spec technical annex — section pattern reference

**Do not create `story-plan.md`.** Per-story design annex sections live **inside** `{stories_dir}/{STORY_ID}/story-spec.md` (see `templates/sdd/story-spec-template.md`). This file is a **reference only** for baseline audit, prerequisites, reusable artifacts, subtasks tables, and sign-off blocks that Builder / Lead Builder `co-design-solution` merges into the technical annex portion of `story-spec.md`.

This is neither Product Owner story authoring nor a replacement for `{stories_dir}/{STORY_ID}/story-tasks.md` (full task bodies). Cross-story order comes from the chronological backlog index in `epic-spec.md`.

Copy applicable sections into the resolved `stories_dir` (default `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md`, overridable via `.nwob/artifact-paths.json` `stories_dir`). Fill every `<!-- -->` block with real content, and delete whichever optional sections do not apply. Engagement-specific package names, branch regex, and constructor-injection rules belong in the project's `.cursor/rules/constitution-custom.mdc` when that file is present; do not hard-code them here.

---

## NWOB placement

The table below shows where each NWOB skill's responsibility begins and ends around this annex:

| This annex | Does | Does not |
|------------|------|----------|
| **Builder** `co-design-solution` | Baseline audit, package layout, mocks, reusable artifacts, subtasks table, **technical annex in `story-spec.md`**, **author `story-tasks.md`** | Rewrite product Gherkin without PO `/backlog`; create `story-spec.md` |
| **Lead Builder** `orchestrate-design` | Consolidate design package; dual-persist architecture / flat component plans | Put full task bodies only in `story-tasks.md`; author retired epic-plan/epic-tasks files |
| **Lead Builder** `validate-design-package` | Confirm `story-spec.md` annex + `story-tasks.md` + architecture are build-ready; write Sign-off below | Start coding |
| **Builder** `trigger-ai-build` | Consume annex and `story-tasks.md` as context **after** design sign-off | Treat this file as the task list |

**Canonical sources:** Product Gherkin and the technical annex both live in `{stories_dir}/{STORY_ID}/story-spec.md`; build order lives in `{stories_dir}/{STORY_ID}/story-tasks.md`. Cross-story order comes from the backlog index in `epic-spec.md`. If annex work makes an acceptance criterion more precise, Product Owner `/backlog` must update Gherkin (and the `epic-spec.md` backlog index if summary/size/deps change). A local Jira dump must never outrank `story-spec.md`.

**Contracts win:** Wherever OpenAPI, the error catalog, or `qa-test-scenarios.md` disagree with Jira prose, the contracts take precedence, and any resulting drift should be recorded in the Error code mapping section below.

---

## How to use (NWOB sequence)

1. Start by confirming the story in `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from `epic-spec.md` backlog index), checking that all six constitution fields and the numbered Gherkin are present; if the story is missing or weak, stop here and route it to Product Owner `/features` or `/backlog` instead of continuing.
2. Once the story is confirmed, switch to Builder and run `co-design-solution` for this story alone, creating `{stories_dir}/{STORY_ID}/story-spec.md` (technical annex) from this template as the starting point.
3. Before writing any code, complete a Phase 0 baseline audit by grepping the service clone under `repositories/{service-name}/` and recording what already exists versus what this story is responsible for, rather than guessing at the current state.
4. With that audit in hand, fill in the sections below, paying particular attention to the scope boundary, the prerequisites, the reusable artifacts, and the subtasks.
5. With the annex table filled, keep running `co-design-solution` so every subtask row becomes a `story-tasks.md` item using the annex `story-tasks.md` ID unchanged, since a row without a `story-tasks.md` ID cannot be built. Hand off to `orchestrate-design` to refresh the in-scope `story-tasks.md` (order from epic-spec backlog) for this story.
6. Before generating any Cursor execution plan or running `trigger-ai-build`, have Lead Builder run `validate-design-package` to confirm everything is ready and record sign-off in the Sign-off section below (or `{STORY_ID}-design-validation.md`).
7. Finally, keep this annex and sibling `story-tasks.md` updated throughout the build, since they are the handoff artifacts that `review-implementation` and downstream stories will rely on.

None of this reaches the execution-plan stage until step 6 has passed, so `execution-plan-template.md` and Cursor Plan Mode should wait until then. The live execution plan belongs only in `~/.cursor/plans/`; it is not an SDD artifact.

### File naming

The table below lists where each related artifact should live:

| Artifact | Path |
|----------|------|
| **Technical annex (in story-spec.md)** | `{stories_dir}/{STORY_ID}/story-spec.md` (default `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md`) |
| **Story tasks (canonical bodies)** | `{stories_dir}/{STORY_ID}/story-tasks.md` |
| **Backlog index** | `nwob-docs/sdd/epic-spec.md` (chronological US/TS index) |
| Example | `nwob-docs/sdd/stories/US1-INTa/story-spec.md` |
| Optional sprint demo | `demo/{STORY_ID}-sprint-demo-script.md` (not SDD) |
| Local scratch copies | Supporting only — not source of truth |

Here, `{STORY_ID}` refers to the story id in `epic-spec.md` backlog index (for example `US1-INTa`). The Jira key belongs in the document's header rather than standing in as the only filename.

### Story doc types (pick one emphasis)

Each annex should pick a single emphasis from the four story doc types below:

| Type | Focus | Typical stories |
|------|-------|-----------------|
| **A — Artifacts / contracts** | Schemas, OpenAPI alignment, docs | Contract or schema tickets |
| **B — Implementation** | Production code, services, validators | Feature and API tickets |
| **C — Tests only** | Unit/IT suites; mock heavy dependencies | Coverage and IT lanes |
| **D — Code review** | MR review checklist against story AC | Peer-review / audit tickets |

Type D specifically feeds into Lead Builder `review-implementation` and `/audit` as input, rather than standing in as a substitute for either skill.

### Subtasks table (required columns)

Every subtasks table in this annex needs the five columns shown below:

| Task ID | Description | Artifacts | Category | `story-tasks.md` ID |
| :---: | ----- | ----- | :---: | :---: |

The Category column takes one of five values: `Configuration`, `Coding`, `Documentation`, `Unit Test`, or `Quality Management`. The Task ID column holds either a master task identifier from the story sequence, such as `T021b`, a simple letter like `a` or `b`, or the literal value `config`. Builder `co-design-solution` fills the `story-tasks.md` ID column when it writes this annex (example `S16-T-01`), then copies each annex ID unchanged into `{stories_dir}/{STORY_ID}/story-tasks.md`. Lead Builder `orchestrate-design` confirms design-package traceability to `epic-spec.md` and in-scope `story-tasks.md` IDs. One item per row, no second ID.

### Status values (baseline audit & prerequisites)

The baseline audit and prerequisites sections use one of seven status values: `Not started`, `In progress`, `Complete (branch)`, `Complete (merged)`, `Optional`, `Blocked`, or, for contracts specifically, `Done`. Lead Builder `validate-design-package` fails whenever the Overall row is still marked `Not started` with no grep evidence recorded to support it.

### Link convention

A story is referenced as `story-spec.md` under `{stories_dir}/{STORY_ID}/` (indexed from `epic-spec.md` backlog index), and a sibling story is linked as [`nwob-docs/sdd/stories/{ID}/story-spec.md`](../../nwob-docs/sdd/stories/{ID}/story-spec.md) (adjust the relative path if `stories_dir` is mapped elsewhere).

---

<!-- Copy everything below this line into the filled annex, and delete this comment once you do. -->

**{STORY_ID}: <!-- Short story title — must match story-spec.md Summary -->**

| Field | Value |
|-------|--------|
| **story-spec.md ID** | <!-- e.g. US1-INTa --> |
| **Jira** | <!-- e.g. PROJ-12345 --> |
| **Type (A/B/C/D)** | <!-- --> |
| **Service clone** | `repositories/<!-- service-name -->/` |
| **NWOB skills** | Builder `co-design-solution` → Lead Builder `orchestrate-design` → Lead Builder `validate-design-package` |

**Description**

<!-- Write two to four sentences describing what this story delivers, stating the boundary explicitly,
and restating story-spec.md rather than inventing new product acceptance criteria. -->

This story delivers **<!-- e.g. compile-only / validator logic / unit tests only -->**, while <!-- the split-off work --> lands instead in **[{STORY_B}](../../nwob-docs/sdd/stories/{STORY_B}/story-spec.md)**, and <!-- the other split-off work --> lands in **[{STORY_C}](../../nwob-docs/sdd/stories/{STORY_C}/story-spec.md)**.

**Why it matters:** <!-- Explain, in one paragraph at most, how this ties back to FR-*, SC-*, an NFR, or the story-spec.md Description. -->

**Package convention:** Types for this story follow reverse-domain layout from `nwob-docs/architecture/service-map.md` and, when present, `.cursor/rules/constitution-custom.mdc` (package depth, singular nouns, injection style). Record the actual namespace below; do not invent a second convention.

**Package layout (<!-- {STORY_ID} --> populates <!-- packages -->):**

```
<!-- Show a tree of only what this story adds or modifies, marking any prerequisite packages with a
     comment noting which story introduced them. -->

{{reverse.domain.package}}/
└── <!-- package/ -->
    └── <!-- ClassName.java -->   # T0XX — purpose  → story-tasks.md T-NNN
```

**Sibling deliverables (not <!-- {STORY_ID} -->):** <!-- Delete this section if it does not apply. -->

| Artifact | Story | Role |
|----------|-------|------|
| `<!-- ClassOrFile -->` | **{STORY_B}** or annex link | <!-- consumer / prerequisite --> |
| `<!-- ClassOrFile -->` | **{STORY_C}** | <!-- downstream --> |

**Depends on:** <!-- List hard prerequisites here, linking to their story-spec.md IDs and annexes. -->

| Prerequisite | Doc |
|--------------|-----|
| {STORY_PREREQ} domain types | `story-spec.md` + annex `{ID}/story-spec.md` (technical annex) |
| <!-- add rows --> | |

**Connected stories (reference only):**

| Jira | Story (`story-spec.md`) | Relationship |
|------|-------------------|--------------|
| <!-- PROJ-n --> | <!-- STORY_ID --> | <!-- Hard prerequisite / consumer / parallel --> |
| **{STORY_REST}** | REST CRUD | <!-- if applicable --> |

---

## Current status (baseline audit)

<!-- As part of Builder co-design-solution, grep repositories/{service}/ before writing any code, and
keep this table updated as implementation proceeds. -->

| Area | Status | Notes |
|------|--------|-------|
| Overall | **Not started (~0%)** | <!-- one-line summary + evidence (class/path) --> |
| <!-- prerequisite --> | **<!-- status -->** | <!-- evidence --> |
| <!-- deliverable 1 --> | **Not started** | |
| <!-- deliverable 2 --> | **Not started** | |
| Authoritative contracts | **Available** | `contracts/rest-api.openapi.yaml`, `api-error-catalog.md`, OpenAPI under `repositories/{service}/src/main/resources/swagger/` |
| <!-- optional --> | **<!-- status -->** | |

---

## Prerequisites

This story cannot start until the following prerequisites are satisfied:

| Prerequisite | Status | Action |
|--------------|--------|--------|
| `story-spec.md` + Gherkin | **<!-- status -->** | If missing → Product Owner `/backlog` |
| {STORY_PREREQ} <!-- name --> | **<!-- status -->** | annex / `story-spec.md` — <!-- action if blocked --> |
| OpenAPI + validation matrix | **Done** | swagger path from service-map, or `repositories/{service-name}/contracts/` |
| Database / Kafka / Spring context | **Not required** / **Required** | <!-- justify test scope --> |

---

## Reusable from <!-- sources --> (do not reimplement)

The table below lists what already exists and should be reused rather than rebuilt:

| Library / artifact | Covers | Usage in <!-- {STORY_ID} --> |
|--------------------|--------|------------------------------|
| `<!-- artifact -->` (<!-- story -->) | <!-- what it does --> | <!-- how you use it --> |
| `contracts/api-error-catalog.md` | Stable `ERR_*` codes | Map failures to catalog |
| `contracts/qa-test-scenarios.md` | QA id → scenario | Traceability in tests |
| {{shared-error-library}} | RFC 7807 / domain exceptions | <!-- exception strategy --> |

**Service-local only (<!-- {STORY_ID} --> deliverables):** everything below this line is new to this story and will become the Files entries in `story-tasks.md`.

- <!-- List the classes, files, and tests this story must create. -->
- <!-- If this is an implementation story, include its public API methods here too. -->

Orchestration stories can optionally sketch their pipeline or flow as a short diagram:

```
<!-- e.g.
Input
  → step 1 (schema)
  → step 2 (business rules)
  → step 3 (compileInSandbox)
  → Output | throw
-->
```

**Design constraints (from epic-spec / story-spec / story sequence):**

| Constraint | Source | <!-- Story --> obligation |
|------------|--------|---------------------------|
| <!-- rule --> | FR-<!-- n -->, SC-<!-- n -->, `story-spec.md` AC | <!-- what you must enforce --> |

**Out of scope in <!-- {STORY_ID} -->:** each excluded item below should point to whichever story actually owns it.

- <!-- item --> → **{STORY_B}** / **{STORY_REST}** / etc.
- <!-- item --> → downstream story

For test-only stories (Type C), record the mocking policy as well [OPTIONAL]:

**Mocking policy:**

| Dependency | Mock? | Rationale |
|------------|-------|-----------|
| `<!-- Dep -->` | **Yes** / **No** | <!-- why — copy into execution-plan locked decisions --> |

When the story sequence's error codes have drifted from the contracts, record the mapping between them here [OPTIONAL]:

**Error code mapping (story sequence → contract authority):**

| Story sequence AC (if obsolete) | Contract `error_code` | QA id |
|-----------------------------------|----------------------|-------|
| `<!-- old name -->` | `<!-- ERR_* -->` | <!-- RR-V01 --> |

---

## Subtasks

<!-- Builder co-design-solution fills all five columns when writing this annex. -->

| Task ID | Description | Artifacts | Category | `story-tasks.md` ID |
| :---: | ----- | ----- | :---: | :---: |
| config | <!-- e.g. Wire dependency in pom.xml --> | `pom.xml` | Configuration | T-<!-- nnn --> |
| T0XX | <!-- master task description --> | `path/to/Class.java` | Coding | T-<!-- nnn --> |
| a | <!-- subtask --> | `path/to/file` | Coding | T-<!-- nnn --> |
| b | <!-- subtask --> | `path/to/file` | Unit Test | T-<!-- nnn --> |

Each `story-tasks.md` item created from these rows must in turn include a story trace back to `{STORY_ID}`, an acceptance signal (Gherkin or QA id), a Verify command, its dependencies, its files (ideally five or fewer), and a scope of XS–S.

**Master task mapping:** This story corresponds to <!-- T0XX, T0YY --> in the engagement story sequence, if one exists.

**Upstream handoff:** Before this story can start, the `{STORY_PREREQ}` annex and `story-spec.md` must already deliver <!-- capability -->.

**Downstream handoff:** Once this story is done, `{STORY_DOWNSTREAM}` and **{STORY_REST}** consume <!-- capability --> from it.

---

## Related work already completed (other stories)

The following work from other stories is directly relevant here:

| Story | Artifact | Relevance |
|-------|----------|-----------|
| {STORY_FOUNDATION} | Package scaffold, error handler | Foundation |
| <!-- STORY_ID --> | <!-- artifact --> | **Prerequisite** / reference |
| `contracts/` / swagger | OpenAPI, error catalog, example payloads | Authoritative — do not drift |
| `nwob-docs/architecture/` | ADRs, service-map | SA-owned; do not rewrite here |

---

## Acceptance Criteria

<!-- Every acceptance criterion here must match the numbered Gherkin in story-spec.md and cite the relevant
FR-*, SC-*, or QA ids; if the acceptance criteria genuinely need to change, that change belongs in
Product Owner /backlog first, with this annex updated afterward to match. -->

### 1. <!-- AC title (e.g. RR-H02 happy path) — same as story-spec.md -->

**Given** <!-- preconditions -->

**When** <!-- action -->

**Then** <!-- expected outcome -->

**And** <!-- additional assertions -->

### 2. <!-- next AC -->

**Given** …

**When** …

**Then** …

### N. Scope boundary — deferred work stays out of <!-- {STORY_ID} -->

**Given** this story's scope boundary

**When** Lead Builder `review-implementation` / `/audit` runs

**Then** no <!-- forbidden artifacts --> exist

**And** those remain deferred to **[{STORY_B}](../../nwob-docs/sdd/stories/{STORY_B}/story-spec.md)** / **{STORY_REST}** / etc.

---

## Verification

All verification commands below should be run from `repositories/<!-- service-name -->`, and copied onto each mapped `story-tasks.md` **Verify** field as appropriate:

```shell
# Install a shared library locally only when the service-map says it is required
# cd ../{{shared-lib}} && mvn -q clean install && cd ../{{service-name}}

# Compile
mvn -q clean compile

# Story-specific tests (adjust -Dtest=)
mvn -q test -Dtest='<!-- TestClass1,TestClass2 -->'

# Optional coverage (unit gate; *IntegrationTest often excluded)
mvn -q test -Pcodecoverage -Dtest='<!-- TestClass -->'
```

Running these commands should produce the following results:

| Check | Expected |
| ----- | ----- |
| `mvn clean compile` | SUCCESS; classes under `{{package/path}}/` |
| <!-- scenario --> | <!-- expected behavior --> |
| Scope guard | No <!-- out-of-scope files/patterns --> |
| Tagging | `@Tag("<!-- lane-tag -->")` per README |

The table below cross-references each test scenario with the contract fixture it relies on:

**Fixture cross-reference (contracts):**

| Scenario | Example payload / QA id |
|----------|-------------------------|
| <!-- happy path --> | `contracts/example-payloads/<!-- path -->` |
| <!-- error path --> | `contracts/example-payloads/<!-- path -->` (<!-- QA-Vnn -->) |

---

## Downstream readiness

Once <!-- {STORY_ID} --> merges — and once Lead Builder `/audit` has reviewed the MR, if this story raised one — the following becomes possible:

| Story | Unblocked capability |
|-------|---------------------|
| [{STORY_B}](../../nwob-docs/sdd/stories/{STORY_B}/story-spec.md) | <!-- what they can do now --> |
| **{STORY_REST}** | <!-- REST / integration --> |

---

## Dependency note

**<!-- Gate name --> gate:** `{STORY_PREREQ}` must merge first, because <!-- reason -->.

**SDD gate:** Builder `trigger-ai-build` should not run until `epic-spec.md`, in-scope `story-spec.md` (product + technical annex), `story-tasks.md`, and a Lead Builder `validate-design-package` sign-off are all in place.

**Contracts:** The authoritative HTTP and validation semantics live at the swagger path in service-map (or `repositories/{service-name}/contracts/`), and whenever the story sequence prose disagrees with `api-error-catalog.md` or `qa-test-scenarios.md`, the contracts win.

**Split stories:** When the product key has been split across multiple Jira tickets, document that split here:

| Jira | Story (`story-spec.md`) | SP | Scope |
|------|-------------------|-----|-------|
| **<!-- PROJ-n -->** | {STORY_ID} | <!-- n --> | <!-- section --> — <!-- this annex --> |
| <!-- PROJ-n --> | {STORY_B} | <!-- n --> | <!-- section --> |

**Title note:** This work is tracked under Jira **<!-- PROJ-NNNNN -->** and product key **{STORY_ID}** (<!-- n --> SP), positioned according to `epic-spec.md` backlog index's chronological order.

---

## Sign-off (Lead Builder `validate-design-package`)

Lead Builder `validate-design-package` writes here when the design package is build-ready. Alternatively persist to `{stories_dir}/{STORY_ID}-design-validation.md`.

| Field | Value |
|-------|-------|
| **Verdict** | <!-- Approved for build / Changes required --> |
| **Date** | <!-- YYYY-MM-DD --> |
| **Validator notes** | <!-- gaps waived, ADR refs, or return-to-orchestrate-design list --> |

---

## Appendix A — Section checklist

Use this checklist in Builder `co-design-solution` and again in Lead Builder `validate-design-package`.

- [ ] Technical annex sections live in `{stories_dir}/{STORY_ID}/story-spec.md` (default `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md`); no separate `story-spec.md` file exists.
- [ ] The scope boundary is stated consistently in the Description, in Out of scope, and in the final acceptance criterion.
- [ ] The baseline audit reflects the actual state of the repository rather than the template's default placeholders.
- [ ] Every prerequisite lists a status along with either a link or an action.
- [ ] The subtasks table includes Task ID, Description, Artifacts, Category, and `story-tasks.md` ID on every row (filled by `co-design-solution`).
- [ ] The acceptance criteria match the Given/When/Then in `story-spec.md` and cite QA ids wherever applicable.
- [ ] The verification commands are copy-paste runnable and have been copied onto the corresponding `story-tasks.md` Verify fields.
- [ ] The error codes match `contracts/api-error-catalog.md`.
- [ ] Downstream stories are identified with links to their annex or to `story-spec.md`.
- [ ] No file paths have been written into `story-spec.md`.
- [ ] Package naming follows service-map and `.cursor/rules/constitution-custom.mdc` when that file exists.

## Appendix B — Authoritative references

The table below collects every authoritative reference this annex draws on:

| Resource | Path |
|----------|------|
| Product stories / Gherkin | `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from `epic-spec.md` backlog index) |
| Implementation tasks (bodies) | `{stories_dir}/{STORY_ID}/story-tasks.md` |
| Backlog index | `nwob-docs/sdd/epic-spec.md` |
| Architecture / service-map | `nwob-docs/architecture/` |
| Story sequence (supporting, if present) | engagement story-sequence doc — not SDD source of truth |
| OpenAPI | `repositories/{service-name}/src/main/resources/swagger/` |
| Error catalog | `contracts/api-error-catalog.md` or swagger-adjacent catalog |
| Validation matrix | `contracts/api-validation-matrix.md` |
| QA scenarios | `contracts/qa-test-scenarios.md` |
| Data model | SA / shared-specs path from service-map |
| Execution plan (after design sign-off) | `templates/lb/execution-plan-template.md` → `~/.cursor/plans/` only |

## Appendix C — Quick prompts for AI-assisted drafting

This prompt can be handed to an agent as-is to drive annex and `story-tasks.md` together.

**Builder — fill this annex and `story-tasks.md` (`co-design-solution`):**

```
Run co-design-solution for {STORY_ID}.
Load the co-design-solution skill. Read `{stories_dir}/{STORY_ID}/story-spec.md` (indexed from epic-spec.md backlog index) for {STORY_ID}.
Merge applicable sections from templates/lb/story-plan-template.md into the technical annex portion of
{stories_dir}/{STORY_ID}/story-spec.md (default stories_dir is nwob-docs/sdd/stories/).
Write {stories_dir}/{STORY_ID}/story-tasks.md using templates/sdd/story-tasks-template.md
with one full task body per annex subtask (same story-tasks.md IDs).
Grep repositories/{service}/ for the baseline audit. Contracts win over sequence prose.
Fill every subtask column including story-tasks.md ID.
Apply .cursor/rules/constitution-custom.mdc when present.
Do not create story-spec.md. Do not rewrite product Gherkin without PO /backlog.
```

**Lead Builder — design package (`orchestrate-design`):**

```
Run orchestrate-design for stories including {STORY_ID}.
Input: epic-spec.md backlog index, in-scope story-spec.md (annex + Gherkin), and story-tasks.md.
Consolidate design-package.md; dual-persist architecture.md ↔ masterplan.md and flat component plans as needed.
Apply .cursor/rules/constitution-custom.mdc when present.
Do not author epic-plan.md, epic-tasks.md, or story-spec.md. If any annex row lacks a story-tasks.md ID, stop and fill co-design first.
```
