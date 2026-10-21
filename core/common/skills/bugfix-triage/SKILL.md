---
name: bugfix-triage
description: Maintain phase playbook. Reproduce with a failing test, find root cause, smallest correct fix. No drive-by refactors.
---

# bugfix-triage

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`, `/v0-maintain`). The record is the maintenance note `docs/agents-v0/maintain/<id>/note.md`.

## Steps
1. **Baseline.** Run the full verify command before the first edit (`/v0-maintain` step 3). A red baseline outside this bug's area needs a `known_failures` allowance; otherwise stop.
2. **Acceptance.** In the note, write expected versus actual behavior and the steps that show it.
3. **Reproduce with a test.** Write the test that reproduces the bug. Run it and record the failing card (Command, Exit, Attempt, Failing test, Location) in `docs/agents-v0/build/<id>/build-report.md`. A bug with no reproducing test is `UNVERIFIED`: say so in the note instead of guessing.
4. Write `docs/agents-v0/maintain/<id>/helper-brief.md` (`helper: explore-researcher`) to locate the responsible code. Do not launch the helper (`workflow-orchestration.mdc` Helper agents).
5. For a runtime failure or stack trace, write the same brief with `helper: debug-investigator`, then apply the fix from the result the main session brings back.
6. Apply the **smallest correct diff**; match naming, types, and abstractions. No drive-by refactors.
7. The reproducing test passes. Add the edge-path test. Each attempt appends a card; run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<id>/build-report.md` before the next one.
8. Run the full verify command once. Bounded fix attempts (≤ 3 per failure); on exhaustion stop and report the blocker.
9. Record the change tier and impacted surfaces in the note. Auth, sessions, routes, controllers, uploads, or deployment security configuration means the full Verify with the VAPT checklist.
10. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: smallest correct diff; no commits/force-push without approval.
- [ ] A test that failed before the fix passes after it; its failing card is in `docs/agents-v0/build/<id>/build-report.md`.
- [ ] `vapt.mdc` / `vapt-webapp.mdc`: VAPT-required tests for affected surfaces.
- [ ] `quality-and-testing.mdc`: coverage maintained; no new CVEs.
- [ ] `security-baseline.mdc`: no secrets introduced; BOLA rechecked for changed `{id}` paths.
- [ ] `workflow-orchestration.mdc`: classifier output in the note; routed to the right Verify.
