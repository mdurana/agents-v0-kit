# Task Breakdown Patterns

Condensed patterns embedded in Builder `co-design-solution`. Source: `references/agent-skills-main/skills/planning-and-task-breakdown`.

**Do not** persist tasks to standalone plan documents — canonical **bodies** are `{stories_dir}/{STORY_ID}/story-tasks.md` (default `nwob-docs/sdd/stories/{STORY_ID}/story-tasks.md`), traceable to `nwob-docs/sdd/epic-spec.md` backlog index rows and `{STORY_ID}/story-spec.md`. Cross-story execution order follows the epic-spec chronological backlog index.

---

## When this applies

Run during **Write `story-tasks.md`** in `co-design-solution` when:

- Selected stories are ready for implementation planning
- Implementation order or dependencies are unclear
- Tasks must be sized for AI-assisted single-session increments

**Skip** when `story-tasks.md` for the story already exists, is ordered, traceable, and passes verification — validate only. Lead Builder `orchestrate-design` may reconcile the design package against existing `story-tasks.md` IDs.

**Not here:** Product-level vertical slicing and Gherkin AC → Product Owner `/features`.

---

## Process

### 1. Read-only planning

Before writing `story-tasks.md`:

- Read `nwob-docs/sdd/epic-spec.md` (backlog index + HL US/TS), sibling `story-spec.md`, and existing `nwob-docs/architecture/`
- Map dependency graph between stories and technical components
- Note risks requiring SA commands (`/pattern`, `/adr`) or ADRs

Do not write application code during this step.

### 2. Dependency graph → order

Build foundations before dependents (example):

```
Database migration / entity
    └── Repository + domain logic
            └── API endpoint + DTOs
                    └── BFF aggregation (if applicable)
                            └── Frontend route / component
```

`story-tasks.md` order must respect `epic-spec.md` chronological backlog index **and** technical dependencies.

### 3. Vertical implementation slices

Prefer tasks that complete **one story path** through the stack — not horizontal layers in isolation.

| Good task | Bad task |
|-----------|----------|
| "Story US-012: soft-delete user — migration + entity + API + test" | "Create all Flyway scripts for sprint" |
| "Story US-012: admin UI delete action + API client" | "Build entire admin settings page" |

Horizontal-only tasks (schema-only, API-only without a story path) are prohibited unless explicitly scoped as a **Technical Story** in `epic-spec.md` backlog index.

### 4. Task anatomy

Each `story-tasks.md` item MUST include:

| Field | Purpose |
|-------|---------|
| **ID** | Stable identifier (e.g. `T-001`) |
| **Story trace** | Epic-spec backlog row ID or summary |
| **Description** | What to implement in one focused increment |
| **Acceptance signal** | How to know the task is done (maps to story Gherkin where applicable) |
| **Verify** | Command or check (e.g. `mvn clean verify`, specific test class) |
| **Dependencies** | Prior task IDs |
| **Files** | Expected touch set (keep ≤5 files per task when possible) |
| **Scope** | XS / S / M / L / XL — target XS–S for AI increments |

Full task bodies live only in `story-tasks.md` (no separate epic-level task index).

### 5. Checkpoints

Insert explicit checkpoint markers every 2–3 tasks:

- Run verify command
- Confirm design package alignment
- Optional: user doubt-driven adversarial review for high-risk slices

### 6. Parallelization notes

Document tasks that may run in parallel only when:

- No shared file conflicts
- No ordering dependency
- Separate services or modules

Default: **strict sequential** execution in `trigger-ai-build`. Cross-story parallel notes may reference epic-spec backlog order.

---

## Example task entry (`story-tasks.md`)

```markdown
### T-003 — Soft-delete user API (US-012)

- **Story:** Soft delete an active user via admin API
- **Description:** Add DELETE handler, service method, and repository soft-delete using effective data lifecycle policy
- **Acceptance signal:** Gherkin scenario "Soft deleting an active user" passes
- **Verify:** `mvn test -Dtest=UserControllerTest` then `mvn clean verify`
- **Dependencies:** T-001 (entity + migration), T-002 (repository)
- **Files:** `UserController.java`, `UserService.java`, `UserControllerTest.java`
- **Scope:** S
```

---

## Anti-patterns

| Anti-pattern | Correct action |
|--------------|----------------|
| Tasks without epic-spec backlog story trace | Add or fix PO story first |
| File paths in epic-spec product sections | Move to `story-tasks.md` / technical annex in `story-spec.md` |
| Mega-tasks (>5 files, XL scope) | Split into ordered subtasks |
| Standalone "Implementation Plan" doc | Write `story-tasks.md` under `stories_dir/{STORY_ID}/` |
| Epic-level task index file | Use per-story `story-tasks.md` only; order from epic-spec |
| Invoke reference skill file directly | Use this embed inside `co-design-solution` |
