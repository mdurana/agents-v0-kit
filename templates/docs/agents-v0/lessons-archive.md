# Lessons archive

<!--
MEM-02: entries moved out of docs/agents-v0/lessons.md to keep the active list at or under its cap.
Edited only in the integration checkout, by a human or by the release-manager with the user's
approval; never on a story branch. Keep each entry's id and text; change only the status and add:
- promoted: "- Promoted to: docs/agents-v0/project-profile.md (<section or row>)" or the ADR /
  design record path that now holds the rule, e.g. docs/agents-v0/adr/0007-migration-naming.md
- retired: "- Reason: <why it no longer applies>"

### L-001 · 2026-10-28 · promoted
- Story/phase: orders-api / build
- Trigger: failure-brief
- What happened: Flyway migration used a reserved word as a column name and failed twice on PostgreSQL.
- Do instead: Check new column names against the PostgreSQL reserved-word list before writing the migration.
- Scope: Any story that adds a database migration.
- Promoted to: docs/agents-v0/project-profile.md (Conventions: migration naming)

Check with: sh .agents-v0/scripts/check-lessons.sh
-->

Promoted and retired lessons. Not read by phase agents by default.

## Archived lessons

_No entries yet._
