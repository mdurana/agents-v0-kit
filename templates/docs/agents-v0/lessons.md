# Lessons

<!--
MEM-02: cross-story memory. This file holds lessons a human accepted at a local-release gate,
so the next story does not repeat a mistake an earlier story already paid for. It lives on the
integration branch (main) only. It was added to the kit on 2026-10-28 (refs/MEMORY-20261028.md).

Who writes here
- Only the release-manager, in the integration checkout, right after the user approved the
  local release and the merge succeeded (/v0-local-release). It appends the lessons the user
  accepted from the story's "## Proposed lessons" section.
- A story branch (feature/<feature>, maintain/<id>) never edits this file. Phase agents put
  up to 3 candidates per phase in the phase-result "## Lessons" section instead.
- Number new entries with: sh .agents-v0/scripts/check-lessons.sh --next-id

Who reads here
- Phase agents read the active entries at the start of /v0-plan, /v0-intake, /v0-design,
  /v0-build, /v0-verify, and /v0-maintain, and apply those whose Scope matches the work.

Keep it small
- At most 30 active entries (check-lessons.sh --max-active, or LESSONS_MAX_ACTIVE).
  When full, move entries to lessons-archive.md: "promoted" when the lesson became a rule in
  docs/agents-v0/project-profile.md or a decision record (ADR), "retired" when it no longer applies.
  Do not delete entries; ids stay unique and sequential across both files.
- One short line per bullet; an entry is at most 800 characters.
- Never write secrets, tokens, passwords, keys, customer data, or internal hostnames.

Entry format (copy below "## Active lessons", outside this comment):

### L-001 · 2026-10-28 · accepted
- Story/phase: orders-api / build
- Trigger: failure-brief
- What happened: Flyway migration used a reserved word as a column name and failed twice on PostgreSQL.
- Do instead: Check new column names against the PostgreSQL reserved-word list before writing the migration.
- Scope: Any story that adds a database migration.

Trigger is one of: failure-brief, verify-fail, reopen, review, attempt-budget, blocked, other.
Check the file with: sh .agents-v0/scripts/check-lessons.sh
-->

Accepted cross-story lessons. Read them before you plan, design, build, verify, or maintain.
Apply an entry when its Scope matches your work.

## Active lessons

_No entries yet._
