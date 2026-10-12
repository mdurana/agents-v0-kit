---
name: migration-safety
description: Database migration playbook. Expand/contract, backfill verification, and rollback notes for the pack's migration tool.
---

# migration-safety

Schema changes on brownfield or production-bound services. Used by `/v0-build` (the pack implement skill's migration step, including `implement-service` step 10) for every new migration and by `/v0-maintain` for schema fixes. The design's data-model section (`design.md`) states the migration shape; Build follows it. The tool is the one named in the pack `PACK.md`: Flyway (`java`), EF Core (`dotnet`), TypeORM (`node`), Alembic (`python`, or Django migrations when that app already exists), golang-migrate (`go`). Do not introduce a second migration tool.

## Steps
1. Prefer **expand/contract**: additive migration first; deploy; backfill; then contract in a later release.
2. Adopting a tool on an existing database needs a baseline version recorded in an ADR. Flyway uses `baselineOnMigrate` / `baselineVersion`.
3. Never destructive DDL without explicit user approval and rollback script in the same change set notes.
4. Add a migration test proving up and down (if down is supported).
5. Record rollback steps in `docs/agents-v0/build/<feature>/build-report.md` or ADR.
6. A repo that already uses Liquibase stays on Liquibase. Do not introduce Flyway without an ADR.

## Rule-compliance checklist
- [ ] The pack backend rule: migrations use that pack's tool.
- [ ] `workflow-orchestration.mdc`: Build evidence with `commit:`.
