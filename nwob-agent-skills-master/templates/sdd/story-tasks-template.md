# Story Task Breakdown — <!-- STORY_ID -->

> **SDD artifact** — Ordered, actionable tasks for a single story.
> Story order from `epic-spec.md` chronological backlog index. Product AC + technical annex in sibling `story-spec.md`.
> Constitution: `.cursor/rules/constitution-core.mdc`
> Produced by Builder `co-design-solution` during design (not `/features`).
> Do **not** create `epic-tasks.md` or `story-plan.md`.

## Story

| Field | Value |
|-------|--------|
| **Story ID** | <!-- e.g. US1-INTa --> |
| **Summary** | <!-- must match story-spec.md Summary --> |
| **epic-spec.md** | Indexed chronologically in backlog section |
| **story-spec.md** | [`./story-spec.md`](./story-spec.md) |

## Prerequisites

- [ ] `story-spec.md` has constitution fields + numbered Gherkin AC
- [ ] `story-spec.md` technical annex subtasks table filled with matching `story-tasks.md` IDs
- [ ] Design package reviewed (Lead Builder `validate-design-package` before build)

## Tasks

<!-- One item per story-spec annex subtask row. Same ID in annex column and this file.
     Format per references/rules/task-breakdown-patterns.md -->

### <!-- T-001 --> — <!-- short title -->

- **Story:** <!-- STORY_ID — summary -->
- **Description:** <!-- what to implement in one focused increment -->
- **Acceptance signal:** <!-- maps to story Gherkin where applicable -->
- **Verify:** <!-- e.g. `mvn test -Dtest=…` then `mvn clean verify` -->
- **Dependencies:** <!-- prior task IDs, or none -->
- **Files:** <!-- expected touch set; ≤5 preferred -->
- **Scope:** <!-- XS / S / M / L / XL — target XS–S for AI increments -->

### <!-- T-002 --> — <!-- short title -->

- **Story:**
- **Description:**
- **Acceptance signal:**
- **Verify:**
- **Dependencies:**
- **Files:**
- **Scope:**

<!-- Repeat as needed. -->
