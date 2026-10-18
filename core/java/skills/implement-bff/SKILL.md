---
name: implement-bff
description: Build phase playbook. Implement a thin BFF — aggregation, auth/session edge, rate limits, Resilience4j — with red–green tests.
pack: java
---

# implement-bff

Build phase playbook for the `bff-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts and the existing BFF (MVC or WebFlux — do not switch without an ADR).
2. **Baseline:** run the full Backend verify command from `docs/agents-v0/project-profile.md` before the first edit (use the BFF root when Layout sets one), unless `/v0-build` skips a checkout that is already the default branch tip. If it fails, stop and report the pre-existing failure; never build on a broken baseline.
3. **Wire the quality gate** if missing (`maven/quality-plugins.xml`; contract conformance where the BFF exposes an API) — unwired tooling makes `./mvnw -B clean verify` compile-only.
4. When `docs/agents-v0/design/<feature>/openapi.yaml` exists and this BFF owns that contract, merge the approved draft into the org catalog before service implementation edits (or immediately after `--record-red` when a plan row tests the catalog itself). Stop if that catalog file is already modified by another feature. If the backend story already merged it, do not merge it again.
5. Before the first implementation edit, write or continue `docs/agents-v0/build/<feature>/plan.md`: one row per approved `AC-*`. Mark a row `done` only after that unit's fast command is green, and name the test; then run `sh .agents-v0/ci/check-build-plan.sh <feature>` (it fails when the test does not exist or was never red; `(no-red: <reason>)` waives one row). Do not add, delete, or rewrite AC rows.
6. Work **red–green (TDD where practical)** per plan row: failing test first, then implement until green (`quality-and-testing.mdc`). Each loop run **must** use `Backend verify (fast, no OWASP)` from the profile (a real command, not a `<!--` placeholder). If that cell is empty or still a placeholder, stop and fill the profile rather than running the full verify in the loop. Append a command-result card. The next attempt must not read `build-output.txt`. Before each new attempt run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md`; exit 1 means the phase attempt budget is spent (`workflow-orchestration.mdc`): record `blocked` and stop. The second red result for the same test writes `docs/agents-v0/build/<feature>/failure-brief.md` and returns for `debug-investigator`. Before attempt three run `sh .agents-v0/scripts/check-failure-brief.sh <feature>` (must exit 0). Attempt three applies that note. A third red result stops.
7. Keep the BFF **thin**: aggregation, UI DTOs, auth/session handoff, safe GET cache, rate limits, unified errors. Domain logic stays in backend services.
8. Wire outbound clients: ~10s timeout, retry, circuit breaker; `X-Correlation-ID`; service auth.
9. Validate permissions **before** proxying admin operations; auth/session changes ship with their VAPT-required tests in the same diff.
10. Add `@PreAuthorize` on admin/mutation endpoints; no authz bypass flags.
11. Implement logout: expire the refresh cookie, purge session state, blacklist fail-closed, and trigger IdP sign-out for SSO. Keep the access token out of the cookie; the browser holds it in memory.
12. Run the full verify command for the BFF root from `docs/agents-v0/project-profile.md` once for the Build gate (`./mvnw -B clean verify` when that row names it), with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. For a security-critical or complex unit, hand it to `solution-architect` for a design review instead of a further attempt. The fast loop does not replace this gate.
13. Persist evidence to `docs/agents-v0/build/<feature>/build-report.md` (command, result, attempt cards, per-criterion file:line evidence) and `docs/agents-v0/build/<feature>/build-output.txt` (raw output; no secrets). Do not read `build-output.txt` on the next attempt.

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc` (BFF): pipeline Auth → rate limit → cache/validation → controller; thin; domain logic in services.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; methods ≤ 30 lines; cognitive complexity ≤ 15; coverage targets on changed code.
- [ ] Baseline green before the first edit; red–green loop uses `Backend verify (fast, no OWASP)` when that cell is a real command; quality gate executed once in `./mvnw -B clean verify`.
- [ ] Contract conformance diff clean (or recorded N/A reason) where the BFF exposes an API.
- [ ] `vapt.mdc` F1: logout purges session; fail-closed. Access token stays in memory; refresh token is an HttpOnly cookie.
- [ ] `vapt.mdc` F4: `@PreAuthorize` on admin/mutation; no bypass flags; policy errors deny.
- [ ] `vapt.mdc` F8: BFF authorizes the `{id}` before proxying.
- [ ] `vapt.mdc` F9: token validation matches the API (algorithm allowlist, audience, expiry).
- [ ] `vapt-webapp.mdc` F4: server-side route/module enforcement — not UI hide-only.
- [ ] `api-and-events.mdc`: one error envelope per surface; idempotency on non-idempotent creates.
- [ ] `security-baseline.mdc` §2: BOLA authorized lookup; §3: no secrets in client-facing errors.
- [ ] Build evidence persisted under `docs/agents-v0/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
