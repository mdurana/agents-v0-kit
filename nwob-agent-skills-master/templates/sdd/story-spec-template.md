# Story Spec Template

> **SDD artifact** — Per-story product anatomy **and** technical co-design annex under `{stories_dir}/{STORY_ID}/story-spec.md`.
> Indexed from the chronological backlog in `epic-spec.md`. Constitution: `.cursor/rules/constitution-core.mdc`.
> Implementation task bodies belong in sibling `story-tasks.md` only — do **not** create `story-plan.md`.

**Story ID:** <!-- e.g. US1-INTa -->

Type: User Story | Technical Story
Summary: <!-- one-line goal -->
Description: <!-- context, business value, or technical necessity -->
Acceptance Criteria (AC):
  Scenario: <!-- name -->
  Given <!-- precondition -->
  When <!-- action -->
  Then <!-- outcome -->
  And <!-- additional outcome -->
Dependencies: <!-- blocking story IDs or "None" -->
Size: <!-- Fibonacci: 1, 2, 3, 5, 8 -->

<!-- Add numbered scenarios as needed. Stories ≥ 5 SP must be decomposed where logically possible. -->

---

## Technical design annex

> Filled by Builder / Pod Builder `co-design-solution` (SA/LB may co-author via `/orchestrate-design`).
> Product AC above remain PO-owned; flag material AC changes for PO `/backlog`.
> Detailed annex patterns: former `templates/lb/story-plan-template.md` sections (baseline audit, prerequisites, reusable artifacts, subtasks table, sign-off).

| Field | Value |
|-------|--------|
| **Jira** | <!-- e.g. PROJ-12345 --> |
| **Type (A/B/C/D)** | <!-- Artifacts / Implementation / Tests / Code review --> |
| **Service clone** | `repositories/<!-- service-name -->/` |
| **story-tasks.md** | [`./story-tasks.md`](./story-tasks.md) |

### Scope boundary

<!-- What this story delivers vs sibling stories. Restate product AC; do not invent new ones. -->

### Baseline audit

| Area | Status | Notes |
|------|--------|-------|
| Overall | **Not started** | <!-- grep evidence under repositories/ --> |

### Prerequisites

| Prerequisite | Status | Action |
|--------------|--------|--------|
| Product AC (this file) | **<!-- -->** | If missing → Product Owner `/backlog` |
| OpenAPI / contracts | **<!-- -->** | From service-map / swagger path |

### Subtasks → story-tasks.md

| Task ID | Description | Artifacts | Category | `story-tasks.md` ID |
| :---: | ----- | ----- | :---: | :---: |
| <!-- a --> | <!-- --> | <!-- --> | Coding | <!-- S16-T-01 --> |

<!-- Category: Configuration | Coding | Documentation | Unit Test | Quality Management -->
<!-- co-design-solution copies each story-tasks.md ID into sibling story-tasks.md unchanged. -->

### Sign-off

| Gate | Status | By |
|------|--------|-----|
| `validate-design-package` | <!-- Pending / Approved --> | <!-- --> |
