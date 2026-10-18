---
name: implement-bff
description: Build phase playbook. Implement a thin Gin BFF — aggregation, auth/session edge, rate limits — with red–green tests.
pack: go
---

# implement-bff

Build phase playbook for the `bff-engineer` when `Pack` is `go`. Do not add `pom.xml` or a Spring BFF. Keep chi or `net/http` only when the repo already uses them.

## Steps
1. Read the Design artifacts and the existing BFF. Do not switch router without an ADR.
2. **Baseline:** run the full Backend verify command from `docs/agents-v0/project-profile.md` on the BFF root before the first edit, unless `/v0-build` skips a checkout that is already the default branch tip. If it fails, stop.
3. Wire `go test` so the verify command writes `go-test.json` and `coverage.out`.
4. When this BFF owns `docs/agents-v0/design/<feature>/openapi.yaml`, merge that approved draft into the org catalog before service edits (or immediately after `--record-red` when a plan row tests the catalog itself). Stop if that catalog is already modified by another feature.
5. Write or continue `docs/agents-v0/build/<feature>/plan.md` with one row per approved `AC-*`.
6. Work **red–green (TDD where practical)** per plan row: failing test first, capture the red test report (`sh .agents-v0/ci/check-build-plan.sh <feature> --record-red` before the green run overwrites `go-test.json`), then implement until green (`quality-and-testing.mdc`). Each loop run **must** use `Backend verify (fast, no OWASP)` from the profile. Append a command-result card. The next attempt must not read `build-output.txt`. Before each new attempt run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md`; exit 1 means the phase attempt budget is spent: record `blocked` and stop. The second red result writes `failure-brief.md`. Before attempt three run `sh .agents-v0/scripts/check-failure-brief.sh <feature>`.
7. Keep the BFF thin: aggregation, UI DTOs, auth/session handoff, safe GET cache, rate limits, unified errors. Domain logic stays in backend services.
8. Outbound clients use a timeout, retry, and a breaker, and send `X-Correlation-ID` plus service auth.
9. Authorize the caller before proxying an admin or `{id}` operation.
10. Auth middleware on admin and mutation routes. Logout revokes the token and clears the server session. The access token stays in browser memory. The refresh token is an HttpOnly cookie.
11. Run the full Backend verify command once, with **bounded fix attempts (≤ 3 per failure)**.
12. Persist `docs/agents-v0/build/<feature>/build-report.md` and `build-output.txt`.

## Rule-compliance checklist
- [ ] `vapt.mdc` F1, F4, and F8.
- [ ] `vapt-webapp.mdc` F4: server-side enforcement, not UI hide-only.
- [ ] `quality-and-testing.mdc` and `api-and-events.mdc`.
- [ ] Build evidence persisted. Fix attempts bounded.
