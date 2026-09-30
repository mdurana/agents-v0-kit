---
name: implement-bff
description: Build phase playbook. Implement a thin BFF — aggregation, auth/session edge, rate limits, Resilience4j — with red–green tests.
---

# implement-bff

Build phase playbook for the `bff-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts and the existing BFF (MVC or WebFlux — do not switch without an ADR).
2. **Baseline:** run the Backend verify command from `docs/project-profile.md` before the first edit (use the BFF root when Layout sets one). If it fails, stop and report the pre-existing failure; never build on a broken baseline.
3. **Wire the quality gate** if missing (`maven/quality-plugins.xml`; contract conformance where the BFF exposes an API) — unwired tooling makes `mvn clean verify` compile-only.
4. Work **red–green (TDD where practical)** per behavior unit: failing test first, then implement until green (`quality-and-testing.mdc`).
5. Keep the BFF **thin**: aggregation, UI DTOs, auth/session handoff, safe GET cache, rate limits, unified errors. Domain logic stays in backend services.
6. Wire outbound clients: ~10s timeout, retry, circuit breaker; `X-Correlation-ID`; service auth.
7. Validate permissions **before** proxying admin operations; auth/session changes ship with their VAPT-required tests in the same diff.
8. Add `@PreAuthorize` on admin/mutation endpoints; no authz bypass flags.
9. Implement logout: purge session state; blacklist fail-closed; trigger IdP sign-out for SSO.
10. Run the verify command for the BFF root from `docs/project-profile.md` with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. For a security-critical or complex unit, hand it to `solution-architect` for a design review instead of a further attempt.
11. Persist evidence to `docs/build/<feature>/build-report.md` (command, result, per-criterion file:line evidence) and `docs/build/<feature>/build-output.txt` (raw output; no secrets).

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc` (BFF): pipeline Auth → rate limit → cache/validation → controller; thin; domain logic in services.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; methods ≤ 30 lines; cognitive complexity ≤ 15; coverage targets on changed code.
- [ ] Baseline green before the first edit; quality gate wired and executed in `mvn -B clean verify`.
- [ ] Contract conformance diff clean (or recorded N/A reason) where the BFF exposes an API.
- [ ] `vapt-spring.mdc` F1: logout purges session; fail-closed.
- [ ] `vapt-spring.mdc` F4: `@PreAuthorize` on admin/mutation; no bypass flags.
- [ ] `vapt-webapp.mdc` F4: server-side route/module enforcement — not UI hide-only.
- [ ] `api-and-events.mdc`: one error envelope per surface; idempotency on non-idempotent creates.
- [ ] `security-baseline.mdc` §2: BOLA authorized lookup; §3: no secrets in client-facing errors.
- [ ] Build evidence persisted under `docs/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
