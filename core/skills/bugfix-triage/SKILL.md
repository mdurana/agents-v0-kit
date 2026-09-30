---
name: bugfix-triage
description: Maintain phase playbook. Reproduce, find root cause, smallest correct fix. No drive-by refactors.
---

# bugfix-triage

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Reproduce the bug; capture the failing test or runtime trace.
2. Launch the `explore-researcher` subagent to locate the responsible code.
3. Send runtime failures/stack traces to the `debug-investigator` subagent; re-inject the fix.
4. Apply the **smallest correct diff**; match naming, types, and abstractions. No drive-by refactors.
5. Add/adjust tests covering the bug and the edge path.
6. If the fix touches auth/sessions/routes/controllers/uploads/deployment security config, route to Verify (VAPT checklist).
7. Run `mvn -B clean verify` or the frontend script with bounded fix attempts (≤ 3 per failure); on exhaustion stop and report the blocker.
8. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `ai-agent-conduct.mdc`: smallest correct diff; no commits/force-push without approval.
- [ ] `vapt-spring.mdc` / `vapt-webapp.mdc`: VAPT-required tests for affected surfaces.
- [ ] `quality-and-testing.mdc`: tests added; coverage maintained; no new CVEs.
- [ ] `security-baseline.mdc`: no secrets introduced; BOLA rechecked for changed `{id}` paths.
- [ ] `workflow-orchestration.mdc`: routed to Verify after fix.
