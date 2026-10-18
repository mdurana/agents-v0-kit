---
name: implement-service
description: Build phase playbook. Implement a NestJS service, or keep an existing Express app, with migrations, auth, tracing, and red–green tests.
pack: node
---

# implement-service

Build phase playbook for the `backend-engineer` agent when `Pack` is `node` (`workflow-orchestration.mdc`). Pins are in `.agents-v0/packs/node/PACK.md`. A new service is NestJS. Keep Express when the repo already uses it. Do not add `pom.xml`, a `.csproj`, or a second Node framework.

## Steps
1. Read the Design artifacts (OpenAPI, event schemas, ADR) and the existing repo.
2. **Baseline:** run the full Backend verify command from `docs/agents-v0/project-profile.md` before the first edit, unless `/v0-build` skips a checkout that is already the default branch tip. If it fails, stop and report the pre-existing failure. Put code under that backend root.
3. **Wire the quality gate** so the verify command writes `junit.xml` and `coverage/coverage-summary.json`. Unwired tests make `npm run build` compile-only.
4. When `docs/agents-v0/design/<feature>/openapi.yaml` exists, merge that approved draft into the org catalog before service implementation edits (or right after `--record-red` when a plan row tests the catalog itself). Stop if that catalog file is already modified by another feature. `sh .agents-v0/ci/check-openapi.sh merged <draft> <catalog>` must pass. A story with no draft records N/A in the build report.
5. Before the first implementation edit, write `docs/agents-v0/build/<feature>/plan.md` with one row per approved `AC-*` (AC, Status `pending`/`done`/`blocked`, Test). Do not add, delete, or rewrite AC rows.
6. Work **red–green (TDD where practical)** per plan row: failing test first, capture the red test report (`sh .agents-v0/ci/check-build-plan.sh <feature> --record-red` before the green run overwrites `junit.xml`), then implement until green (`quality-and-testing.mdc`). Each loop run **must** use `Backend verify (fast, no OWASP)` from the profile. If that cell is empty or still a placeholder, stop and fill the profile. Append a command-result card (Command, Exit, Attempt, Failing test, Location). The next attempt must not read `build-output.txt`. Before each new attempt run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md`; exit 1 means the phase attempt budget is spent: record `blocked` and stop. The second red result for the same test writes `docs/agents-v0/build/<feature>/failure-brief.md` (`helper: debug-investigator`) and returns. Before attempt three run `sh .agents-v0/scripts/check-failure-brief.sh <feature>`.
7. Implement layers: controller (validated DTO) → service → repository → domain.
8. Put `@UseGuards` on every admin or mutation handler. A public route uses `@Public` and is local-dev only. Express uses `requireAuth` or an explicit public middleware. `sh .agents-v0/ci/check-endpoint-auth.sh <base>` fails a new route with neither.
9. Auth, upload, and RBAC changes ship with their VAPT-required tests in the same diff.
10. Add TypeORM migrations for schema changes, following `migration-safety`: additive first, a rollback note, and a test that applies the migration to the previous schema.
11. Wire correlation id and `traceparent`.
12. Structured logs. No PII, secrets, or tokens.
13. Uploads: size limit, content and structure checks, generated storage name, decompression limit, authorization, production virus scan.
14. Logout revokes the token and clears server session state. A denylist fails closed.
15. Validate JWTs for `iss`, `aud`, `exp`, and `nbf`. Fail closed.
16. Emit security audit events for auth, denial, admin mutation, and upload outcome (`security-baseline.mdc` §12).
17. Use parameterized queries only.
18. Run the full Backend verify command from the profile once for the Build gate, with **bounded fix attempts (≤ 3 per failure)**. The fast loop does not replace this gate.
19. Persist `docs/agents-v0/build/<feature>/build-report.md` and `docs/agents-v0/build/<feature>/build-output.txt`. Do not read `build-output.txt` on the next attempt.

## Rule-compliance checklist
- [ ] `backend.mdc`: constructor injection; DTOs only; no empty catch; methods ≤ 30 lines.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; coverage targets on changed code.
- [ ] `vapt.mdc` F1, F3, F4, F8, F9, F10.
- [ ] `api-and-events.mdc`: `/api/v1/`; 201/204; one error envelope per surface.
- [ ] `security-baseline.mdc` §2 and §3.
- [ ] Build evidence persisted; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
