---
name: bugfix-triage
description: Maintain phase playbook. Reproduce, find root cause, smallest correct fix. No drive-by refactors.
---

# bugfix-triage

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Reproduce the bug; capture the failing test or runtime trace.
2. Write `docs/maintain/<feature>/helper-brief.md` (`helper: explore-researcher`) to locate the responsible code. Do not launch the helper (`workflow-orchestration.mdc` Helper agents).
3. For a runtime failure or stack trace, write the same brief with `helper: debug-investigator`, then apply the fix from the result the main session brings back.
4. Apply the **smallest correct diff**; match naming, types, and abstractions. No drive-by refactors.
5. Add/adjust tests covering the bug and the edge path.
6. If the fix touches auth/sessions/routes/controllers/uploads/deployment security config, route to Verify (VAPT checklist).
7. Red–green attempts use the profile's fast verify command when that cell is a real command. Then run `mvn -B clean verify` or the full frontend verify command once, with bounded fix attempts (≤ 3 per failure); on exhaustion stop and report the blocker.
8. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: smallest correct diff; no commits/force-push without approval.
- [ ] `vapt-spring.mdc` / `vapt-webapp.mdc`: VAPT-required tests for affected surfaces.
- [ ] `quality-and-testing.mdc`: tests added; coverage maintained; no new CVEs.
- [ ] `security-baseline.mdc`: no secrets introduced; BOLA rechecked for changed `{id}` paths.
- [ ] `workflow-orchestration.mdc`: routed to Verify after fix.
