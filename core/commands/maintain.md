---
description: Maintain phase. Bug triage, dependency/CVE upgrades, doc sync; routes back to Verify.
---

# /maintain

You are entering the **Maintain** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

When the requirements artifact exists, run `sh scripts/sync-feature-state.sh <artifact> --active-phase maintain --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from files on disk. On exhausted fix attempts or a missing prerequisite, re-run with `--status blocked --reason "<one line>"` and stop. When the result is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

Before the first edit, follow `workflow-orchestration.mdc` Parallel features. If `git status` shows another feature's code or a shared-file edit that is not this change's diff, run `sh scripts/sync-feature-state.sh <artifact> --active-phase maintain --status blocked --reason "<paths>"` and stop. Do not rewrite `docs/project-profile.md` unless this change is itself a layout, command, or ratchet update.

## Instructions
1. Launch the `maintenance-engineer` subagent with the task (bug report, CVE, dependency upgrade, or refactor request).
2. Select the skill:
   - Bug fix → `bugfix-triage` (explore sub-task on the fast model; runtime failures to the debug model — see `docs/model-routing-matrix.md`).
   - Dependency/CVE → `dependency-upgrade`.
   - Doc drift → `doc-sync` (docs sub-task for drafting — see `docs/model-routing-matrix.md`).
   - Brownfield refactor without spec change → `characterization-tests` before behavior edits.
   - Schema/migration change → `migration-safety` (expand/contract; no destructive flyway in same release as contract break).
3. Apply the **smallest correct diff**; no drive-by refactors.
4. If the change touches auth/sessions/routes/controllers/uploads/deployment security config, route to Verify (VAPT checklist).
5. Run `mvn -B clean verify` / frontend script with bounded fix attempts (≤ 3 per failure); on exhaustion stop and report the blocker.
6. Do not commit or push without explicit user approval.
7. **Stop** and present the result to the user. Record the maintenance scope, evidence, and explicit approval to enter Verify in the existing requirements artifact or the linked issue/PR. Route to Verify for re-verification; do not infer approval when evidence is absent.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `vapt-spring.mdc`, `vapt-webapp.mdc`, `security-baseline.mdc` §9, `quality-and-testing.mdc`, `architecture-and-diagrams.mdc`.
