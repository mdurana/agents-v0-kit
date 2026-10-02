---
name: characterization-tests
description: Brownfield safety. Capture current behavior with characterization tests before refactoring legacy code.
---

# characterization-tests

Use before structural refactors on brownfield code (`workflow-orchestration.mdc` Maintain/Major paths).

## Steps
1. Identify the smallest surface to change (class, module, endpoint).
2. Write characterization tests that assert **current** outputs for representative inputs (golden or snapshot where appropriate).
3. Run tests on the **known baseline**; if red, record under `known_failures` in `docs/agents-v0/project-profile.md` or fix baseline first.
4. Refactor with tests green; add targeted tests for new behavior.
5. Route to `/v0-verify` when touching auth, uploads, or public routes.

## Rule-compliance checklist
- [ ] `quality-and-testing.mdc`: useful tests only; no trivial assertions.
- [ ] `ai-agent-conduct.mdc`: smallest correct diff.
