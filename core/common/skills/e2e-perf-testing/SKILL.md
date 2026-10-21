---
name: e2e-perf-testing
description: Verify phase playbook. Playwright end-to-end journeys, consumer-driven contract tests for integration stories, and k6 load scripts that produce measured SLO evidence.
---

# e2e-perf-testing

Verify phase playbook for the `test-engineer` agent, used with `quality-gate` (`workflow-orchestration.mdc`). Run it when the story is an integration story, a vertical slice, a P2 journey, or a P4 hardening story. A story with no such scope records N/A and the reason in `docs/agents-v0/verify/<feature>/quality-gate.md`.

## Steps
1. **Journeys (Playwright).** Write one test per primary journey in the requirements artifact, in `frontend/e2e/` (or the root named by the profile). Start the app through the `webServer` block of `playwright.config.*` so CI needs no extra step. Assert user-visible outcomes and run the axe-core check on each route the journey visits. Use role and label selectors, not CSS paths.
2. **Contract tests (integration stories).** For each service pair in the story, write the consumer-side Pact test and verify the provider against it (Pact broker or a committed `pacts/` folder, whichever the repo already uses). The pair's failure modes (timeout, 5xx, 409, malformed body) each get a case.
3. **Load scripts (k6).** For each filled row in `docs/agents-v0/design/system/nfr-slo.md`, write `perf/<surface>.js` with thresholds taken from that row (`http_req_duration: ['p(95)<...']`, `http_req_failed: ['rate<0.01']`). Use realistic data and a ramp, not a single burst. Run it against a production-like environment; a laptop run is not evidence for a P4 row.
4. **Resilience.** For each dependency in the context map, add one test that degrades it (timeout, 5xx, slow response) and asserts the circuit breaker or fallback from `project-delivery-core.mdc`.
5. **Evidence.** Run the commands and save the outputs (`docs/agents-v0/verify/<feature>/e2e-report.md`, k6 summary JSON under `docs/agents-v0/verify/<feature>/`). Start each Markdown report with `commit:`. In `docs/agents-v0/design/system/slo-evidence.md`, a `measured` row names the k6 command and that summary file. A `waiver` row is a last resort; a P4 milestone can set `SLO_ALLOW_WAIVERS=0` so CI rejects it.
6. List every flaky test with its retry count in the report. A test that needs a retry to pass is a defect, not a pass.

## Rule-compliance checklist
- [ ] `quality-and-testing.mdc`: AAA, deterministic domain tests, mocks for external I/O only.
- [ ] `ux-design.mdc`: axe-core on every journey route; UX acceptance criteria covered.
- [ ] Each service pair has a consumer test and a provider verification.
- [ ] Each filled NFR/SLO row has a k6 script and a saved summary, or a named waiver.
- [ ] `workflow-orchestration.mdc`: Verify gate criteria met; evidence carries `commit:`.
