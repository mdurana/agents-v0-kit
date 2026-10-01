# Compliance matrix

Maps every org rule clause to the agent, skill, hook, or gate that covers it. It is a coverage map, not proof that a project change complies; delivery evidence comes from the relevant tests, scans, reviews, approvals, and CI results.

Legend: **A** = agent instruction/review, **S** = skill checklist, **H-B** = blocking hook, **H-W** = warning hook, **G** = human-approved gate, **C** = command workflow check, **CI** = CI-side blocking check script, **R** = rule. A/S/C/R describe prompted or manual review, not deterministic enforcement. Gates require recorded evidence and approval; N/A is allowed only for an unaffected surface and never for an applicable Critical VAPT item.

Tool note: hook rows (H-B/H-W) run on Cursor (`.cursor/hooks.json`) and Claude Code (`.claude/settings.json` PreToolUse/PostToolUse/Stop). Kilo Code has no hook runtime — the same contract is enforced via `kilo.json` `permission.bash` (deny/ask patterns) and the CI checks.

## project-delivery-core.mdc

| Clause | Enforcer |
|--------|----------|
| Canonical stack (Spring Boot 3.x, PostgreSQL, Flyway, OpenAPI) | A backend-engineer; S implement-spring-service; G Build gate |
| Frontend: ask Svelte or React once | A requirements-analyst, frontend-engineer; S spec-intake, implement-frontend; G Intake gate |
| Directory profiles (service, ui, app); `Service roots` for several services in one repo (one catalog per service) | R project-delivery-core; `docs/project-profile.md`; C /onboard; CI ci/resolve-layout.sh |
| Correlation ID propagation | A backend-engineer, bff-engineer, frontend-engineer; S implement-spring-service, implement-bff, implement-frontend; G Build gate |
| Distributed tracing (traceparent/OTel) | A backend-engineer, bff-engineer, frontend-engineer; G Build gate |
| Structured logging | A backend-engineer; S implement-spring-service |
| Metrics (Prometheus/RED) | A backend-engineer; S implement-spring-service |
| Auth: JWT/S2S, never log tokens | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R security-baseline |
| Resilience: breaker/retry/timeout | A bff-engineer; S implement-bff |
| API envelopes (success/error) | A solution-architect; S contract-first-design; G Design gate |
| Async only when justified | A solution-architect; S contract-first-design; G Design gate |
| Mandated docs (README, architecture, network, sequences) | A maintenance-engineer, release-manager; S doc-sync, release-pr; G Release gate |
| BFF thin; domain logic in services | A bff-engineer; S implement-bff; R architecture-and-diagrams |
| Health (`/health`, `/ready`, `/live` when the project uses them) | A backend-engineer; S implement-spring-service; G Build gate |
| Cache and YugabyteDB only when requirements justify them | A solution-architect; S contract-first-design; G Design gate |
| DDD defaults (aggregates, value objects, repository ports) | A solution-architect, backend-engineer; S contract-first-design, implement-spring-service; G Design/Build gate |
| Do not switch MVC and WebFlux without an ADR | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; G Design gate |
| OMS / order domain only when the task touches that domain | A solution-architect; S contract-first-design; R architecture-and-diagrams |

## ai-agent-conduct.mdc

| Clause | Enforcer |
|--------|----------|
| Reconnaissance → Plan → Execute → Verify → Report | R workflow-orchestration; all agents; all skills |
| Lead with conclusion; no filler/sycophancy | All agents (system prompt) |
| Minimize scope; no drive-by refactors | A maintenance-engineer; S bugfix-triage, dependency-upgrade |
| No unsolicited scratch notes, session exports, or duplicate rule dumps | All agents; R ai-agent-conduct |
| Prefer empirical checks (files, tests, build) over guesses | All agents; R ai-agent-conduct |
| Prompt efficiency (Context → Task → Constraints; scope vague requests) | All agents (system prompt) |
| Shell: non-interactive, bounded | A all agents; R ai-agent-conduct |
| Ask user only when blocked | R workflow-orchestration (approval stops); all agents |
| Do not commit unless asked | A release-manager; S release-pr; H-B pre-shell.sh (asks on git commit/push; denies force-push/hard reset, `gh pr merge`, destructive git clean; no env/command bypass) |
| No force-push/hard reset | H-B pre-shell.sh; S release-pr |
| MR creation via glab (GitLab default) or PR via gh | A release-manager; S release-pr; C /release |
| Rule precedence: repository wins | R workflow-orchestration; `docs/project-profile.md`, ADRs |

## security-baseline.mdc

| Clause | Enforcer |
|--------|----------|
| §1 Authn (OAuth2/JWT, MFA, logout, blacklist fail-closed, dev bypass local) | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R vapt-spring F1 |
| §2 Authz (`@PreAuthorize`, server-side, no client role trust, BOLA) | A backend-engineer, bff-engineer, frontend-engineer; S implement-*; H-W after-edit.sh (heuristic only — Verify/Sonar authoritative); R vapt-spring F4, vapt-webapp F4; G Build gate |
| §3 Secrets (vault/env, no client exposure, PII not in URLs, sanitize logs) | A all build agents; H-B pre-shell.sh (obvious secret-output commands); H-W after-edit.sh (limited public-env heuristic); R vapt-webapp F2 |
| §4 Cookies and client storage (HttpOnly, Secure, SameSite; no secrets in localStorage) | A frontend-engineer; S implement-frontend; H-W after-edit.sh (`document.cookie` write heuristic); R vapt-webapp F7 |
| §5 Uploads (size, content sniff, structure, authz) | A backend-engineer; S implement-spring-service; H-W after-edit.sh (filename-validation heuristic); R vapt-spring F3 |
| §6 Headers (HSTS, nosniff, X-Frame, CSP, Referrer; explicit CORS; no fingerprinting headers) | A backend-engineer, frontend-engineer; H-W after-edit.sh (`nosniff` heuristic); R vapt-webapp F2 |
| §7 API security (versioned, auth, rate limit, `@Valid`, parameterized SQL, 401/403 not 200-with-error, no stack traces) | A solution-architect, backend-engineer, bff-engineer; S contract-first-design, implement-*; H-W after-edit.sh (Java SQL-concatenation heuristic); R vapt-spring F5 |
| §8 Production hygiene (DEBUG off, no demo routes, sourcemaps off, permit-all=false) | A backend-engineer, frontend-engineer; H-W after-edit.sh (permit-all/sourcemap heuristics); R vapt-webapp F2, vapt-spring F4 |
| §9 Supply chain (dep scanning, SBOM) | A maintenance-engineer; S dependency-upgrade; G Verify gate (CVE check) |
| §11 Compliance & review triggers | A requirements-analyst, security-reviewer; S spec-intake, vapt-review; G Intake gate, Verify gate |

## vapt-spring.mdc

| Finding | Enforcer |
|---------|----------|
| F1 Unauthorized Account Access | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; G Verify gate |
| F3 File Upload Validation | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |
| F4 Improper Access Control | A backend-engineer, bff-engineer, security-reviewer; S implement-*; H-W after-edit.sh (limited heuristic); G Build/Verify gate |
| F5 Exposed API Calls | A solution-architect, backend-engineer, security-reviewer; S contract-first-design, vapt-review; G Verify gate |
| F6 Multiple Active Sessions | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; G Verify gate |

## vapt-webapp.mdc

| Finding | Enforcer |
|---------|----------|
| F1 Unauthorized Account Access | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F2 Sensitive Info in Frontend | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |
| F3 File Upload UI | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F4 Improper Access Control | A frontend-engineer, bff-engineer, security-reviewer; S implement-frontend, implement-bff, vapt-review; G Verify gate |
| F5 Exposed API Calls | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F6 Multiple Active Sessions | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F7 Cookies Without HttpOnly | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |

## vapt-pr-review.mdc

| Clause | Enforcer |
|--------|----------|
| Full PR checklist with sign-off | A security-reviewer, code-reviewer, release-manager; S vapt-review, pr-review, release-pr; .github/pull_request_template.md; G Release gate |
| Critical = merge blocker | G Verify gate, Release gate |

## java-spring-backend.mdc

| Clause | Enforcer |
|--------|----------|
| Constructor injection, `@Transactional(readOnly=true)` | A backend-engineer; S implement-spring-service |
| DTOs only, no entities at edge | A backend-engineer; S implement-spring-service; R api-and-events; G Build gate |
| Flyway migrations | A backend-engineer; S implement-spring-service; G Build gate |
| `Encode.forJava` log sanitization | A backend-engineer; S implement-spring-service; A code-reviewer; S pr-review |
| No empty catch; domain exceptions via `@ControllerAdvice` | A backend-engineer; S implement-spring-service; A code-reviewer; S pr-review |
| Methods ≤ 30 lines (target ≤ 20), ≤ 4 parameters, complexity ≤ 15 | A backend-engineer, code-reviewer; S implement-spring-service, pr-review; G Build/Verify gate |
| JPA (`@Enumerated(STRING)`, `@Version`, avoid N+1) | A backend-engineer; S implement-spring-service; G Build gate |
| Controllers delegate; no business rules in the REST layer | A backend-engineer; S implement-spring-service; G Build gate |
| Lombok: no `@AllArgsConstructor`, `@ToString`, or `@EqualsAndHashCode` on entities with lazy collections | A backend-engineer, code-reviewer; S implement-spring-service, pr-review |
| Records and MapStruct only when the repo already uses them | A backend-engineer; S implement-spring-service |

## frontend-web.mdc

| Clause | Enforcer |
|--------|----------|
| SvelteKit/React structure, load/server loads, browser guard | A frontend-engineer; S implement-frontend |
| API client: Bearer, X-Correlation-ID, traceparent, 401 handling | A frontend-engineer; S implement-frontend; G Build gate |
| Accessibility (semantic HTML, keyboard, ARIA, reduced motion) | A frontend-engineer; S implement-frontend; G Verify gate (a11y check) |
| XSS: sanitize/avoid innerHTML/{@html}/dangerouslySetInnerHTML | A frontend-engineer; S implement-frontend; A code-reviewer; S pr-review |
| Loading, error, and empty states; no silent fetch failures | A frontend-engineer; S implement-frontend; G Build gate |
| No secrets in `localStorage` | A frontend-engineer; S implement-frontend; R security-baseline §4 |
| Forms: Zod plus the project form library | A frontend-engineer; S implement-frontend |

## ux-design.mdc (local rule)

| Clause | Enforcer |
|--------|----------|
| UX requirements at Intake (WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria) | A requirements-analyst; S spec-intake; G Intake gate |
| UX spec (flows, state matrix, HTML mockups, per-component defaults, a11y, responsive, design-system conformance, UX acceptance criteria) | A ux-designer; S ux-design; G Design gate |
| Build implements the UX spec (state matrix, component defaults, mockup layout, named OpenAPI operations, a11y, design-system conformance) | A frontend-engineer; S implement-frontend; G Build gate |
| Automated a11y check (axe-core) green; UX acceptance criteria covered | A test-engineer; S quality-gate; G Verify gate |
| UX/a11y review (state matrix, keyboard/focus, contrast, no UI-hide-only auth) | A code-reviewer; S pr-review; G Verify gate |

## api-and-events.mdc

| Clause | Enforcer |
|--------|----------|
| Contract-first OpenAPI | A solution-architect; S contract-first-design; G Design gate |
| `/api/v1/`, 201/204 | A backend-engineer; S implement-spring-service; G Build gate |
| DTOs only | A backend-engineer; S implement-spring-service; G Build gate |
| Idempotency keys on non-idempotent creates | A solution-architect, backend-engineer; S contract-first-design, implement-spring-service; G Design/Build gate |
| One error envelope per surface | A solution-architect; S contract-first-design; G Design gate |
| Event schemas with eventVersion; additive evolution | A solution-architect; S contract-first-design; G Design gate |
| Idempotent consumers (dedupe by eventId) | A backend-engineer, test-engineer; S implement-spring-service, quality-gate; G Verify gate |
| Parameterized queries only | A backend-engineer; H-W after-edit.sh (limited heuristic); R security-baseline §7 |
| Bean Validation (`@Valid`) on request DTOs | A backend-engineer; S implement-spring-service; G Build gate |
| PATCH semantics documented in OpenAPI | A solution-architect; S contract-first-design; G Design gate |
| Optimistic concurrency (ETag / `If-Match`) | A solution-architect, backend-engineer; S contract-first-design, implement-spring-service; G Design/Build gate |
| Pagination: offset or cursor, matching the contract | A solution-architect, backend-engineer; S contract-first-design, implement-spring-service; G Design/Build gate |
| Correlation and request IDs in error payloads | A backend-engineer; S implement-spring-service; G Build gate |
| Bounded event retries and a DLQ; never swallow failures | A backend-engineer; S implement-spring-service; G Build gate |
| Transactional outbox when the domain write and the event commit together | A backend-engineer; S implement-spring-service; G Build gate |

## quality-and-testing.mdc

| Clause | Enforcer |
|--------|----------|
| AAA pattern; naming conventions | A test-engineer; S quality-gate |
| Coverage ≥ 80% backend lines, branch coverage per JaCoCo/Sonar, 70% frontend | A test-engineer; S quality-gate; G Verify gate |
| Methods ≤ 30 lines, complexity ≤ 15, class size < ~300 lines, duplication < ~3% | A code-reviewer; S pr-review; G Verify gate |
| Testcontainers + Pact where repo depends | A test-engineer; S quality-gate |
| No new high/critical CVEs | A test-engineer, maintenance-engineer; S quality-gate, dependency-upgrade; G Verify gate |
| Tests cover happy, error, and edge paths, including every exception handler that changes behavior | A test-engineer; S quality-gate; G Verify gate |
| Skip tests only when the user explicitly requests no tests | A test-engineer, backend/bff/frontend-engineer; S quality-gate, implement-*; R ai-agent-conduct |
| Red–green-refactor (TDD where practical), front-loaded into Build | R workflow-orchestration; A backend/bff/frontend-engineer, test-engineer; S implement-*, quality-gate; G Build/Verify gate |
| `mvn -B clean verify` before merge with the quality gate wired (coverage/static/CVE) | A backend-engineer, test-engineer; S implement-spring-service, quality-gate; C /build; G Build/Verify gate |

## architecture-and-diagrams.mdc

| Clause | Enforcer |
|--------|----------|
| Diagram locations (architecture, network, sequences) | A solution-architect, maintenance-engineer; S contract-first-design, doc-sync; G Release gate |
| Mermaid conventions | A solution-architect; S contract-first-design; G Design gate |
| Service boundaries / DB per service | A solution-architect; S contract-first-design; G Design gate |
| BFF stack/pipeline/thin | A bff-engineer; S implement-bff; G Build gate |

## code-review.mdc

| Clause | Enforcer |
|--------|----------|
| Full checklist (correctness, security, API, observability, complexity, errors, docs) | A code-reviewer; S pr-review; G Verify gate |
| Critical/Suggestion/Nice to have labels | A code-reviewer; S pr-review |
| Critical = merge blocker | G Verify gate, Release gate |

## workflow-orchestration.mdc

| Clause | Enforcer |
|--------|----------|
| Phases Intake→Design→Build→Verify→Release; Maintain→Verify | C /intake, /design, /build, /verify, /maintain, /release, /deliver |
| Gates per phase | G Intake/Design/Build/Verify/Release gates; all phase commands |
| Approval stops | C /deliver; R ai-agent-conduct; CI ci/check-approvals.sh (merge-time) |
| Critical findings route back | C /verify, /deliver; G Verify gate |
| Gate decisions, approver, date, and evidence recorded in the existing handoff artifact | C all phase commands; R workflow-orchestration; CI ci/check-approvals.sh, ci/check-evidence.sh |
| Merge-request readiness is intermediate; completion is an authorized human merge, with no follow-up commit to record it | C /release, /deliver; A release-manager; S release-pr; R workflow-orchestration |
| Build: green baseline before edits; red–green loop may use the profile fast verify command; the gate still runs full `mvn -B clean verify` (coverage/static/CVE) | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-*; G Build gate |
| Build: tests ship with new behavior (red–green; VAPT-required tests in the same diff) | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-*, quality-gate; G Build gate |
| Build: contract conformance and ArchUnit layer rules | R workflow-orchestration; C /build; S implement-spring-service, implement-bff; G Build gate |
| Build: bounded fix attempts and escalation instead of loops | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-* |
| Build: `docs/build/<feature>/plan.md` has one row per approved `AC-*`; rows are not added or rewritten | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-*; G Build gate |
| Build: second red result of the same test writes `failure-brief.md`; `debug-investigator` runs before attempt three | R workflow-orchestration; C /build; A backend/bff/frontend-engineer, debug-investigator; S implement-* |
| Build: each verify attempt records a command-result card; the next attempt does not read `build-output.txt` | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-* |
| Phase result file `docs/requirements/<feature>.phase-result.md` is the handoff the next phase reads | R workflow-orchestration; A orchestrator; C /intake, /design, /build, /verify, /maintain, /release |
| Verify: `test-engineer` first; `security-reviewer` and `code-reviewer` together; one gathered Critical list | R workflow-orchestration; A orchestrator, security-reviewer, code-reviewer; C /verify, /deliver; G Verify gate |
| Build evidence persisted under `docs/build/<feature>/` and referenced from approvals | R workflow-orchestration; C /build, /verify; CI ci/check-evidence.sh |
| Design: feature contract draft at `docs/design/<feature>/openapi.yaml`; org catalog unchanged until Build merges it | R workflow-orchestration; A solution-architect; S contract-first-design; C /design; G Design gate |
| Design: UX spec and HTML mockups exist (flows, state matrix, per-component defaults, a11y, responsive, design-system conformance, UX acceptance criteria) | R workflow-orchestration; A ux-designer; S ux-design; C /design; G Design gate |
| Design: threat-model notes (assets, trust boundaries, top risks) for non-trivial security | A solution-architect; S contract-first-design; C /design; G Design gate |
| Verify: a11y check green and UX acceptance criteria covered for UI-affecting changes | R workflow-orchestration; A test-engineer; S quality-gate; C /verify; G Verify gate |
| Intake: user story (`As a` / `I want` / `so that`) split into stable `AC-*` rows; out of scope listed separately; NFRs recorded; open questions resolved | A requirements-analyst; S spec-intake; C /intake; G Intake gate |
| Intake: one primary surface unless `Vertical slice: yes`; at most `AC-8`; oversized stories stop on `## Proposed split` | A requirements-analyst; S spec-intake; C /intake; R workflow-orchestration; G Intake gate |
| Milestone programs: manifests group user stories into incremental delivery (P0..P5); story chains + go/no-go | C /intake (story links); R workflow-orchestration; CI ci/check-approvals.sh (milestone row), ci/check-milestone.sh |
| P4 SLO rows close with `docs/design/system/slo-evidence.md`: each filled row is measured or waived | A test-engineer; S slo-evidence; C /verify; R workflow-orchestration; CI ci/check-milestone.sh (verify/release when the manifest names the file) |
| Contract draft is valid and compatible: OpenAPI 3.0, `/api/v1`, unique operationIds, security, Idempotency-Key on POST, one error envelope, no breaking change to the catalog | A solution-architect; S contract-first-design; C /design; G Design gate; CI ci/check-openapi.sh (lint, compat), ci/check-design-contracts.sh |
| Design is complete and traceable: every AC mapped, an authorization row per operation, data model, failure modes, observability, rollout, ADR with alternatives | A solution-architect; S contract-first-design; C /design; G Design gate; CI ci/check-design.sh |
| Independent design review; no open Critical before the design is approved and pinned | A design-reviewer; C /design; G Design gate; `ci/check-design.sh --pin` |
| Approved design is pinned (`design.lock`); a later change needs an Approved amendment row | C /design (Amending an approved design), /build; CI ci/check-design.sh --verify-lock, ci/check-delivery-linkage.sh |
| UX spec and mockups agree (`data-component` on every control, a row per control, operations exist in the draft, no API call in a mockup) | A ux-designer; S ux-design; C /design; CI ci/check-ux-spec.sh |
| Architecture owners review `docs/design/`, `docs/adr/`, and the `openapi/` catalog | CODEOWNERS |
| The catalog merge is proven: the catalog contains every operation and component of the approved draft | C /build; S implement-*; CI ci/check-openapi.sh merged |
| Build plan is real: one row per AC, each done row names an existing test with a red card first | C /build; S implement-*; CI ci/check-build-plan.sh (via ci/check-delivery-linkage.sh) |
| No new Spring endpoint without a security annotation (`@PermitAll` marks a public one) | C /build; S implement-spring-service; CI ci/check-endpoint-auth.sh |
| The frontend calls only operations the catalog lists | C /build; S implement-frontend; CI ci/check-frontend-calls.sh |
| Runtime OpenAPI matches the catalog in both directions (a missing or an undocumented endpoint fails) | C /build; `maven/contract-conformance.xml` |
| `/deliver` runs the phase commands in order and holds no phase detail of its own; resumes from the state file; a reopened phase is marked `Re-opened` until re-approved | C /deliver; A orchestrator; R workflow-orchestration |
| Merge and approval of a merge request are human acts on the default host: `glab mr merge`, `glab mr approve`, and merge/approve through `glab api` are blocked; `glab mr create`, `glab ci trigger`, state-changing `glab api`, and `git tag` ask | H-B / H-ask pre-shell.sh; hook-policy.py shell; Kilo kilo.json |
| Local dry run of the delivery gate before the push; the MR description is rendered from the evidence | C /release; S release-pr; `scripts/render-mr-body.sh`; CI ci/check-delivery-linkage.sh |
| Release approver is the GitLab username that approves the MR; the manual `delivery-approval` job is played by a person or with explicit authorization | C /release; S release-pr; CI ci/check-approver-gitlab.sh |
| CI fix loop is capped at three rounds; a code fix re-enters Verify | C /release; S release-pr |
| Deployment records never go straight to the default branch (docs-only follow-up MR or release issue) | C /release; S release-deploy; R workflow-orchestration Release gate |
| Changelog and release notes come from approved stories; the release owner picks the version and tags | C /release; `scripts/release-notes.sh`; `docs/project-profile.md` Release rows |
| Maintenance record: every fix, CVE patch, upgrade, or hotfix has `docs/maintain/<id>/note.md` with its own `maintain` and `verify` rows and evidence; it never borrows a feature artifact | A maintenance-engineer; S bugfix-triage, dependency-upgrade, doc-sync; C /maintain, /verify; CI ci/check-delivery-linkage.sh (`Maintain-Note`; a feature artifact needs build or verify evidence in the same change) |
| Trivial lane is qualified by the diff (docs-only or version-only, no security surface, schema, major bump, or delivery artifact; size-bounded) and confirmed by a person | C /triage, /maintain; CI ci/classify-change.sh, ci/check-delivery-linkage.sh |
| Abbreviated Verify (Tier trivial): test-engineer only, full verify command, gate metrics, CVE re-scan | C /verify; A test-engineer; S quality-gate |
| Emergency tier: person-confirmed, rollback recorded, Verify owed by `Follow-up verify due` (OVERDUE in the metrics) | C /maintain; CI ci/check-delivery-linkage.sh; `scripts/delivery-metrics.sh` |
| Maintenance discipline: baseline first, failing test before the fix, attempt budget, critical-unit model, dependency graph diff | C /maintain; A maintenance-engineer; S bugfix-triage, dependency-upgrade; `scripts/check-attempt-budget.sh`; R docs/model-routing-matrix.md |
| Change tiers (Trivial / Standard / Major); `/triage` | C /intake, /triage, /deliver; A orchestrator; R workflow-orchestration |
| Machine-readable resume (`lastApprovedPhase`, `activePhase`, `activeStatus`, `blockedReason`) | C /status; R workflow-orchestration Phase resume; `scripts/sync-feature-state.sh`; CI ci/check-feature-state.sh (optional) |
| Parallel features: per-feature artifacts; feature contract drafts under `docs/design/<feature>/` are not shared; stop before a second writer touches a shared file; creating a branch needs explicit user authorization | R workflow-orchestration Parallel features; C /status, /design, /build, /verify, /release, /maintain |
| Helper agents (`explore-researcher`, `schema-author`, `debug-investigator`, `docs-author`) are launched from the main session off a helper brief, not from inside a phase agent | R workflow-orchestration Helper agents; A orchestrator; C /intake, /design, /verify, /maintain |
| Program planning: `/plan` writes the context map and milestone manifests; the Plan gate is a `plan` row | A program-planner, orchestrator; S system-design, program-planning; C /plan; R workflow-orchestration Program planning; CI ci/check-approvals.sh (plan), ci/check-delivery-linkage.sh |
| Story order: a build-approved story needs a Verify approval on every story it depends on | R workflow-orchestration Plan gate; A orchestrator; CI ci/check-milestone.sh (`MILESTONE_ORDER=0` disables) |
| One worktree and branch per feature; creating it needs explicit authorization | R workflow-orchestration Worktree per feature; `scripts/feature-worktree.sh`; H-ask pre-shell.sh; Kilo kilo.json |
| Batch approval of Intake and Design for named, low-risk stories (one row per story artifact) | R workflow-orchestration Batch approval; A orchestrator; CI ci/check-approvals.sh (per artifact) |
| Phase attempt budget: total failed attempts per phase are capped | R workflow-orchestration Phase attempt budget; C /build; S implement-*; `scripts/check-attempt-budget.sh` |
| Verify numbers read from machine output: executed tests, diff coverage, unsuppressed HIGH/CRITICAL CVEs | R workflow-orchestration Verify gate; CI ci/check-gate-metrics.sh |
| Event schemas evolve additively and record `eventVersion` | R api-and-events; A solution-architect; S contract-first-design; CI ci/check-event-schemas.sh |
| Messaging: outbox, idempotent consumers, DLQ, saga compensations, with tests | A backend-engineer; S implement-messaging; G Build gate |
| E2E journeys, consumer-driven contract pairs, resilience cases, k6 SLO measurements | A test-engineer; S e2e-perf-testing, slo-evidence; C /verify; G Verify gate; CI ci/check-milestone.sh (`SLO_ALLOW_WAIVERS=0`) |
| Deployment per environment: own authorization, smoke check, rollback (when the profile has a Deploy table) | A release-manager; S release-deploy; C /release; R workflow-orchestration Release gate |
| Critical units (security triggers, sagas, consumers) run on the Plan-role model; reviewers are independent of the builder | R docs/model-routing-matrix.md; C /build |

## Onboarding

| Clause | Enforcer |
|--------|----------|
| Multi-repo workspace manifest | `docs/workspace.manifest.json`; C /onboard; A codebase-documenter, orchestrator |
| Existing codebase documented as-is: baseline numbers, inventories, module documents, architecture, network, context map, inherited ADR, flows | A codebase-documenter; S onboard-discovery; C /onboard; G Onboard gate; `scripts/discover-codebase.sh`, `scripts/generate-repo-map.sh`, `scripts/collect-dependency-graphs.sh` |
| Onboarding documents cite real code, carry the commit they describe, and leave no template line | `scripts/check-onboarding-docs.sh`; C /onboard; G Onboard gate |
| No secret value in onboarding output (configuration by key name only); literal secrets reported by key | A codebase-documenter; `scripts/discover-codebase.sh`; R security-baseline |
| Onboarding approval (`onboard` row) recorded and bound to its evidence; `/intake` and `/plan` wait for it | C /onboard, /intake, /plan; A orchestrator; CI ci/check-approvals.sh (onboard), ci/check-evidence.sh, ci/check-delivery-linkage.sh |

## Hooks and CI guardrails (kit)

| Control | Enforcer |
|---------|----------|
| Shell deny/ask (git, secrets, rm, kubectl, protected-path shell writes) | H-B pre-shell.sh; hook-policy.py; Kilo kilo.json |
| Protected path edits (hooks, every `ci/*.sh` gate script, agents, rules, commands and skills, entry files, budget and worktree scripts) | H-B pre-edit.sh; hook-policy.py path; CODEOWNERS (the control on Kilo, which has no edit hook) |
| A green build means the checks ran: a JVM module with no resolved root fails CI | CI ci/check-layout-roots.sh (build and gate-metrics jobs) |
| Delivery/milestone artifact edits (human gate) | H-ask pre-edit.sh; hook-policy.py path |
| MCP tools (per-server allow/ask/block; unlisted servers ask) | H-ask pre-mcp.sh; hook-policy.py mcp; `mcp-policy.json` |
| Session context (profile, repo map, state) | session-start.sh |
| PR code ↔ feature artifact linkage | CI ci/check-delivery-linkage.sh |
| Verify approval bound to a human GitHub reviewer named in the Approver column | CI ci/check-approver-github.sh (re-runs on `pull_request_review`) |
| Release or verify approval bound to a human GitLab approver named on either row | CI ci/check-approver-gitlab.sh from the default branch (manual `.gitlab-ci.yml` job `delivery-approval`; `GITLAB_TOKEN` is `read_api` and scoped to that job's environment) |
| Evidence `commit:` + staleness vs PR head | CI ci/check-evidence.sh |
| Build failures cannot be masked by log piping | CI build-and-security.yml (`pipefail` default shell) |
| Brownfield test failure budget | CI ci/check-known-failures.sh; docs/project-profile.md |
| Brownfield coverage ratchet | R quality-and-testing; CI ci/check-coverage-ratchet.sh; docs/project-profile.md `coverage_ratchet` |
| Secret scan (full history, pinned + checksum-verified gitleaks) | CI build-and-security.yml |
| Delivery and hook metrics (approved gates, failed attempts, blocked features per feature) | scripts/delivery-metrics.sh |
| Branch, worktree, or `feature-worktree.sh` creation asks first | H-ask pre-shell.sh; hook-policy.py shell; Kilo kilo.json |
| Behavior tests for the template CI scripts | scripts/test-ci-checks.sh (run by validate-kit.sh) |

**Kilo Code limits:** Kilo has no hook runtime, so protected-path edits, delivery-artifact edit prompts, MCP policy, and session context are **not** enforced there. Kilo relies on `kilo.json` bash patterns, agent `tools:` maps (reviewers without `write`/`bash` stay read-only), CODEOWNERS, and the CI checks above.
