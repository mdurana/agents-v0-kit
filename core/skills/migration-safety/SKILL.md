---
name: migration-safety
description: Database migration playbook. Flyway baseline, expand/contract, backfill verification, rollback notes.
---

# migration-safety

Schema changes on brownfield or production-bound services. Used by `/build` (`implement-spring-service` step 10) for every new migration and by `/maintain` for schema fixes. The design's data-model section (`design.md`) states the migration shape; Build follows it.

## Steps
1. Prefer **expand/contract**: additive migration first; deploy; backfill; then contract in a later release.
2. Flyway: use `baselineOnMigrate` / `baselineVersion` when adopting Flyway on existing DB — document in ADR.
3. Never destructive DDL without explicit user approval and rollback script in the same change set notes.
4. Add migration test (Testcontainers or profile-specific integration test) proving up and down (if down supported).
5. Record rollback steps in `docs/build/<feature>/build-report.md` or ADR.
6. Liquibase repos: follow existing tool; do not introduce Flyway without ADR.

## Rule-compliance checklist
- [ ] `java-spring-backend.mdc`: Flyway SQL migrations.
- [ ] `workflow-orchestration.mdc`: Build evidence with `commit:`.
