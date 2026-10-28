# Milestone: P1 — Contracts and Data Models

Roadmap: docs/agents-v0/roadmap/finance-back-office-portal.md
Architecture: docs/agents-v0/architecture.md

## Goal

Establish the core domain schemas, Flyway migrations, and REST contracts for versioned reference lookup tables and transformation recipes.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P1-A | As a finance operator, I want to create and query versioned reference lookup tables, so that transformation recipes validate commission rates against governed reference data. | docs/agents-v0/requirements/p1-a-lookup-table-registry.md | planned | P0-A | backend | 3 |
| P1-B | As a finance operator, I want to register and retrieve declarative transformation recipes for seeded Funding Cost report types, so that commission calculations execute deterministically. | docs/agents-v0/requirements/p1-b-transformation-recipe-schema.md | planned | P0-A | backend | 3 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/plan.md, docs/agents-v0/milestones/p1-contracts-and-data-models.md, docs/agents-v0/design/system/context-map.md, docs/agents-v0/roadmap/finance-back-office-portal.md | mdurana | Approved | 2026-10-28 |
