---
name: bugfix-triage
description: Maintain phase playbook. Reproduce with a failing test, find root cause, smallest correct fix. No drive-by refactors.
---

# bugfix-triage

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`, `/v0-maintain`). The record is the maintenance note `docs/agents-v0/maintain/<id>/note.md`.

## Steps
1. **Baseline.** The main `/v0-maintain` session runs the full verify command before the first edit (`/v0-maintain` step 3). A red baseline outside this bug's area needs a `known_failures` allowance; otherwise stop.
2. **Acceptance.** In `docs/agents-v0/maintain/<id>/note.md`, write expected versus actual behavior, the reproducing test name, `## Scope`, `## Security surface`, and `## Rollback` with zero template placeholders.
3. **Reproduce with a test.** `maintenance-engineer` writes the test that reproduces the bug; the main session runs it and records the failing card (Command, Exit, Attempt, Failing test, Location) in `docs/agents-v0/build/<id>/build-report.md`. A bug with no reproducing test is `UNVERIFIED`: say so in the note instead of guessing.
4. Write `docs/agents-v0/maintain/<id>/helper-brief.md` (`helper: explore-researcher`, `outputs:`, `return:`, `ask:`) to locate the responsible code. Do not launch the helper (`workflow-orchestration.mdc` Helper Subagents).
5. For a runtime failure or stack trace, write the same brief with `helper: debug-investigator`, `outputs:`, `return:`, and `ask:`, then apply the fix from the result the main session brings back.
6. Apply the **smallest correct diff**; match naming, types, and abstractions. No drive-by refactors.
7. The reproducing test passes. Add the edge-path test. Each attempt appends a card to `docs/agents-v0/build/<id>/build-report.md`; the main session checks `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<id>/build-report.md` and `sh .agents-v0/scripts/check-failure-brief.sh docs/agents-v0/build/<id>/build-report.md` before the next retry.
8. The main session runs the full verify command once (`docs/agents-v0/build/<id>/build-output.txt` + `check-tests-ran.sh`). Bounded fix attempts (≤ 3 per failure, prompt-only); on exhaustion run `sh .agents-v0/scripts/guard-maintain.sh block <id> "<reason>"` and stop.
9. Record the change tier and impacted surfaces in the note, draft `## Lessons` -> `### maintain` in `docs/agents-v0/maintain/<id>/phase-result.md`, and have the main session run `sh .agents-v0/scripts/guard-maintain.sh ready <id>`. Auth, sessions, routes, controllers, uploads, or deployment security configuration means the full Verify with the VAPT checklist.
10. Do not commit or push without the user's external TTY approval (`sh .agents-v0/scripts/guard-common.sh approve maintain <id>`) followed by `sh .agents-v0/scripts/guard-maintain.sh commit <id>`.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: smallest correct diff; no commits/force-push without approval.
- [ ] A test that failed before the fix passes after it; its failing card is in `docs/agents-v0/build/<id>/build-report.md`.
- [ ] `vapt.mdc` / `vapt-webapp.mdc`: VAPT-required tests for affected surfaces.
- [ ] `quality-and-testing.mdc`: coverage maintained; no new CVEs.
- [ ] `security-baseline.mdc`: no secrets introduced; BOLA rechecked for changed `{id}` paths.
- [ ] `workflow-orchestration.mdc`: classifier output in the note; routed to the right Verify.
