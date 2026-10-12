# Compliance matrix

Maps every org rule clause to the agent, skill, hook, or gate that covers it. It is a coverage map, not proof that a project change complies; delivery evidence comes from the relevant tests, scans, reviews, approvals, and CI results.

Legend: **A** = agent instruction/review, **S** = skill checklist, **H-B** = blocking hook, **H-W** = warning hook, **G** = human-approved gate, **C** = command workflow check, **CI** = CI-side blocking check script, **R** = rule. A/S/C/R describe prompted or manual review, not deterministic enforcement. Gates require recorded evidence and approval; N/A is allowed only for an unaffected surface and never for an applicable Critical VAPT item.

Tool note: hook rows (H-B/H-W) run on Cursor via `.cursor/hooks.json` (sessionStart, beforeShellExecution, preToolUse, afterFileEdit, stop). CI checks enforce the same contract at merge time.

## project-delivery-core.mdc

| Clause | Enforcer |
|--------|----------|
| Active pack (`java`, `dotnet`, `node`, `python`, or `go`). The java pack pins Java 21, Spring Boot 4.1.1, Maven wrapper, Spring MVC, Tomcat 11.0.26, Spring Security, PostgreSQL 15, Flyway, OpenAPI; React 19 / TS 5.9 / Vite 7; JUnit / ArchUnit 1.4.2 / H2 test profile / Vitest 3; Compose API 8080, UI 8081, `postgres:15-alpine`. Other packs pin their own list in `.agents-v0/packs/<pack>/PACK.md` | A backend-engineer, frontend-engineer; S the pack's implement-* skill, implement-frontend; C /v0-architecture; CI check-architecture-pack.sh, activate-stack-pack.sh; G Architecture and Build gates |
| P0 app template archive (`templates/app/p0-platform-skeleton.tar.gz`) extracted by `--scaffold-app` when Pack is `java` or empty. Other packs use their scaffold skill and do not extract it | scripts/pack-app-template.sh, scaffold-app-template.sh, bootstrap-greenfield.sh; S scaffold-service, scaffold-aspnet-service, scaffold-node-service, scaffold-python-service, scaffold-go-service; G validate-kit + test-app-template |
| Frontend default: React 19, TypeScript 5.9, Vite 7, Vitest 3. SvelteKit only when the repo already uses it | A requirements-analyst, frontend-engineer; S spec-intake, implement-frontend; G Intake gate |
| Directory profiles (service, ui, app); `Service roots` for several services in one repo (one catalog per service) | R project-delivery-core; `docs/agents-v0/project-profile.md`; C /v0-onboard; CI ci/resolve-layout.sh |
| Correlation ID propagation | A backend-engineer, bff-engineer, frontend-engineer; S implement-spring-service, implement-bff, implement-frontend; G Build gate |
| Distributed tracing (traceparent/OTel) | A backend-engineer, bff-engineer, frontend-engineer; G Build gate |
| Structured logging | A backend-engineer; S implement-spring-service |
| Metrics (Prometheus/RED) | A backend-engineer; S implement-spring-service |
| Auth: JWT/S2S, never log tokens | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R security-baseline |
| Resilience: breaker/retry/timeout | A bff-engineer; S implement-bff |
| API envelopes (success/error) | A solution-architect; S contract-first-design; G Design gate |
| Async only when justified | A solution-architect; S contract-first-design; G Design gate |
| Mandated docs: README and sequence diagrams in the feature release. `architecture.md` and `network.md` are written by `/v0-onboard` or the P0 build, then a docs-only follow-up | A maintenance-engineer, release-manager; S doc-sync, release-pr; C /v0-onboard, /v0-build, /v0-release |
| BFF thin; domain logic in services | A bff-engineer; S implement-bff, implement-aspnet-bff, implement-node-bff, implement-python-bff, implement-go-bff; R architecture-and-diagrams |
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
| Do not commit unless asked | A release-manager; S release-pr; H-B pre-shell.sh (asks on git commit/push; denies force-push/hard reset, destructive git clean; no env/command bypass) |
| No force-push/hard reset | H-B pre-shell.sh; S release-pr |
| MR creation via **`glab`**, only when the user requests it | A release-manager; S release-pr; C /v0-release |
| Rule precedence: repository wins | R workflow-orchestration; `docs/agents-v0/project-profile.md`, ADRs |

## security-baseline.mdc

| Clause | Enforcer |
|--------|----------|
| §1 Authn (OAuth2/JWT, MFA, step-up, logout, blacklist fail-closed, identical recovery responses, dev bypass local) | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R vapt-spring F1; ASVS v5.0.0-7.4.1, v5.0.0-6.3.8 |
| §1 JWT (algorithm allowlist, reject `none`, `iss`/`aud`/`exp`/`nbf`, known `kid`, refresh rotation) | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R vapt-spring F9; G Verify gate; ASVS v5.0.0-9.1.2, v5.0.0-9.2.1, v5.0.0-9.2.3, v5.0.0-10.4.5 |
| §1 Browser session (access token in memory, refresh token in HttpOnly cookie) | A frontend-engineer, bff-engineer; S implement-frontend, implement-bff; R vapt-webapp F1; ASVS v5.0.0-10.1.1, v5.0.0-3.3.4 |
| §2 Function-level authz (`@PreAuthorize`, server-side, no client role trust, fail closed on policy errors) | A backend-engineer, bff-engineer, frontend-engineer; S implement-*; H-W after-edit.sh (heuristic only — Verify/Sonar authoritative); R vapt-spring F4, vapt-webapp F4; G Build gate, Verify gate; ASVS v5.0.0-8.2.1, v5.0.0-8.3.1, v5.0.0-16.5.3 |
| §2 Object-level authz (BOLA; same-role peer retest) | A backend-engineer, bff-engineer, frontend-engineer; S implement-*, contract-first-design; R vapt-spring F8, vapt-webapp F8; G Verify gate; ASVS v5.0.0-8.2.2 |
| §2 Field-level authz (request DTO rejects unknown properties; `@JsonIgnore` on response secrets) | A backend-engineer; S implement-spring-service; R vapt-spring F8; ASVS v5.0.0-8.2.3, v5.0.0-15.3.3 |
| §3 Secrets (vault/env, encryption at rest, no client exposure, PII not in URLs, sanitize logs) | A all build agents; H-B pre-shell.sh (obvious secret-output commands); H-W after-edit.sh (limited public-env heuristic); R vapt-webapp F2; ASVS v5.0.0-13.3.1, v5.0.0-14.2.1, v5.0.0-14.2.4 |
| §4 Cookies and client storage (HttpOnly, Secure, SameSite; access token in memory) | A frontend-engineer; S implement-frontend; H-W after-edit.sh (`document.cookie` write heuristic); R vapt-webapp F1, vapt-webapp F7; ASVS v5.0.0-3.3.4, v5.0.0-14.3.1 |
| §5 Uploads (size, content sniff, structure, generated name, decompression limit, authz, production virus scan) | A backend-engineer; S implement-spring-service; H-W after-edit.sh (filename-validation heuristic); R vapt-spring F3; ASVS v5.0.0-5.2.2, v5.0.0-5.2.3, v5.0.0-5.3.2, v5.0.0-5.4.3 |
| §6 Headers (HSTS includeSubDomains, nosniff, X-Frame, CSP frame-ancestors/base-uri/object-src, Referrer, Permissions-Policy; explicit CORS) | A backend-engineer, frontend-engineer; H-W after-edit.sh (`nosniff` heuristic); R vapt-webapp F2; ASVS v5.0.0-3.4.1, v5.0.0-3.4.3, v5.0.0-3.4.6 |
| §7 API security (versioned, TLS 1.2+, auth, rate limit, `@Valid`, parameterized SQL, sort/filter allowlist, URL allowlist, 401/403 not 200-with-error, no stack traces) | A solution-architect, backend-engineer, bff-engineer; S contract-first-design, implement-*; H-W after-edit.sh (Java SQL-concatenation heuristic); R vapt-spring F5; ASVS v5.0.0-12.1.1, v5.0.0-12.3.2, v5.0.0-1.2.4, v5.0.0-1.3.6, v5.0.0-15.3.2 |
| §8 Production hygiene (DEBUG off, no demo routes, sourcemaps off, permit-all=false) | A backend-engineer, frontend-engineer; H-W after-edit.sh (permit-all/sourcemap heuristics); R vapt-webapp F2, vapt-spring F4 |
| §9 Supply chain (dep scanning, lockfiles, secret detection, SBOM for every shipped service; license policy when compliance requires) | A maintenance-engineer; S dependency-upgrade; G Verify gate (CVE check); ASVS v5.0.0-15.1.2 |
| §11 Compliance & review triggers (GDPR, BSP, Data Privacy Act; `{id}` paths included) | A requirements-analyst, security-reviewer; S spec-intake, vapt-review; G Intake gate, Verify gate |
| §12 Security audit events (auth, logout, denial, revocation, admin mutation, upload; correlation id, principal, action, result; no token) | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R vapt-spring F10; G Verify gate; ASVS v5.0.0-16.3.1, v5.0.0-16.3.2, v5.0.0-16.2.1, v5.0.0-16.4.1 |

## vapt-spring.mdc

| Finding | Enforcer |
|---------|----------|
| F4 Function-level access control (HIGH, always-on) | A backend-engineer, bff-engineer, security-reviewer; S implement-*; H-W after-edit.sh (limited heuristic); G Build/Verify gate; ASVS v5.0.0-8.2.1 |
| F8 Object-level authorization (HIGH, always-on) | A backend-engineer, bff-engineer, security-reviewer; S implement-*, vapt-review; G Verify gate; ASVS v5.0.0-8.2.2 |
| F9 JWT validation (HIGH, always-on) | A backend-engineer, bff-engineer, security-reviewer; S implement-spring-service, implement-bff, vapt-review; G Verify gate; ASVS v5.0.0-9.1.2 |
| F10 Security audit events (MEDIUM, always-on; applicable miss is Critical) | A backend-engineer, bff-engineer, security-reviewer; S implement-spring-service, implement-bff, vapt-review; G Verify gate; ASVS v5.0.0-16.3.1 |
| F1 Unauthorized Account Access | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; G Verify gate |
| F3 File Upload Validation | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |
| F5 Exposed API Calls (missing authz recorded as F4) | A solution-architect, backend-engineer, security-reviewer; S contract-first-design, vapt-review; G Verify gate |
| F6 Multiple Active Sessions | A backend-engineer, security-reviewer; S implement-spring-service, vapt-review; G Verify gate |

## vapt-webapp.mdc

| Finding | Enforcer |
|---------|----------|
| F4 Function-level access control (HIGH, always-on) | A frontend-engineer, bff-engineer, security-reviewer; S implement-frontend, implement-bff, vapt-review; G Verify gate |
| F8 Object-level authorization (HIGH, always-on) | A frontend-engineer, bff-engineer, security-reviewer; S implement-frontend, implement-bff, vapt-review; G Verify gate; ASVS v5.0.0-8.2.2 |
| F1 Unauthorized Account Access (memory access token, HttpOnly refresh) | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F2 Sensitive Info in Frontend | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |
| F3 File Upload UI | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F5 Exposed API Calls (missing authz recorded as F4) | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F6 Multiple Active Sessions | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; G Verify gate |
| F7 Cookies Without HttpOnly (auth-cookie miss blocks merge) | A frontend-engineer, security-reviewer; S implement-frontend, vapt-review; H-W after-edit.sh (limited heuristic); G Verify gate |

## vapt-pr-review.mdc

| Clause | Enforcer |
|--------|----------|
| Full MR checklist with sign-off (always-on F4, F8, F9, F10 plus regression) | A security-reviewer, code-reviewer, release-manager; S vapt-review, pr-review, release-pr; `.gitlab/merge_request_templates/default.md`; G Release gate |
| Always-on miss = Critical; LOW regression blocks only when exploitable | G Verify gate, Release gate |

## java-spring-backend.mdc

| Clause | Enforcer |
|--------|----------|
| Constructor injection, `@Transactional(readOnly=true)` | A backend-engineer; S implement-spring-service |
| DTOs only, no entities at edge | A backend-engineer; S implement-spring-service; R api-and-events; G Build gate |
| Flyway migrations | A backend-engineer; S implement-spring-service; G Build gate |
| `Encode.forJava` log sanitization; §12 security audit events | A backend-engineer; S implement-spring-service; A code-reviewer; S pr-review; R security-baseline §12 |
| No empty catch; domain exceptions via `@ControllerAdvice` | A backend-engineer; S implement-spring-service; A code-reviewer; S pr-review |
| Methods ≤ 30 lines (target ≤ 20), ≤ 4 parameters, complexity ≤ 15 | A backend-engineer, code-reviewer; S implement-spring-service, pr-review; G Build/Verify gate |
| JPA (`@Enumerated(STRING)`, `@Version`, avoid N+1) | A backend-engineer; S implement-spring-service; G Build gate |
| Controllers delegate; no business rules in the REST layer | A backend-engineer; S implement-spring-service; G Build gate |
| Lombok: no `@AllArgsConstructor`, `@ToString`, or `@EqualsAndHashCode` on entities with lazy collections | A backend-engineer, code-reviewer; S implement-spring-service, pr-review |
| Records and MapStruct only when the repo already uses them | A backend-engineer; S implement-spring-service |
| Intel Mac host JDK: a missing Java 21 is MacPorts `openjdk21` via `sh .agents-v0/scripts/host-tools-macports.sh`; kit builds set `JAVA_HOME` from `/usr/libexec/java_home -v 21`; Maven is `./mvnw` | C /v0-build, /v0-maintain; R java-spring-backend; `docs/agents-v0/gold-standards.md` |

## frontend-web.mdc

| Clause | Enforcer |
|--------|----------|
| React structure (default); SvelteKit load/server loads and browser guard when existing | A frontend-engineer; S implement-frontend |
| API client: Bearer, X-Correlation-ID, traceparent, 401 handling | A frontend-engineer; S implement-frontend; G Build gate |
| Accessibility (semantic HTML, keyboard, ARIA, reduced motion) | A frontend-engineer; S implement-frontend; G Verify gate (a11y check) |
| XSS: sanitize/avoid innerHTML/{@html}/dangerouslySetInnerHTML | A frontend-engineer; S implement-frontend; A code-reviewer; S pr-review |
| Loading, error, and empty states; no silent fetch failures | A frontend-engineer; S implement-frontend; G Build gate |
| Access token in memory; refresh token in an HttpOnly cookie; no secrets in `localStorage` | A frontend-engineer; S implement-frontend; R security-baseline §4 |
| Forms: Zod plus the project form library | A frontend-engineer; S implement-frontend |
| Intel Mac host Node: the kit targets Node 22 (22.12+ for Vite 7) and npm; a missing Node or npm is MacPorts `nodejs22` and `npm11` via `sh .agents-v0/scripts/host-tools-macports.sh` | C /v0-build, /v0-maintain; R frontend-web; `docs/agents-v0/gold-standards.md` |

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
| Parameterized queries only; sort/filter allowlist; user-supplied URL allowlist; DTO rejects unknown properties | A backend-engineer; H-W after-edit.sh (limited heuristic); R security-baseline §2, §7 |
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
| No new high/critical CVEs; lockfiles; secret detection; SBOM for a shipped service | A test-engineer, maintenance-engineer; S quality-gate, dependency-upgrade; G Verify gate; R security-baseline §9 |
| Tests cover happy, error, and edge paths, including every exception handler that changes behavior | A test-engineer; S quality-gate; G Verify gate |
| Skip tests only when the user explicitly requests no tests | A test-engineer, backend/bff/frontend-engineer; S quality-gate, implement-*; R ai-agent-conduct |
| Red–green-refactor (TDD where practical), front-loaded into Build | R workflow-orchestration; A backend/bff/frontend-engineer, test-engineer; S implement-*, quality-gate; G Build/Verify gate |
| Profile Backend verify before merge with the quality gate wired (coverage/static/CVE). Pack `java` is `./mvnw -B clean verify` | A backend-engineer, test-engineer; S the pack's implement-* skill, quality-gate; C /v0-build; G Build/Verify gate |

## architecture-and-diagrams.mdc

| Clause | Enforcer |
|--------|----------|
| Diagram locations (architecture, network, sequences, context map, component plans, ops readiness) | A solution-architect, maintenance-engineer; S program-architecture, contract-first-design, doc-sync; G Architecture gate, Release gate |
| Mermaid conventions | A solution-architect; S contract-first-design; G Design gate |
| Service boundaries / DB per service | A solution-architect; S contract-first-design; G Design gate |
| BFF stack/pipeline/thin | A bff-engineer; S implement-bff or the pack's implement-*-bff skill; G Build gate |

## code-review.mdc

| Clause | Enforcer |
|--------|----------|
| Full checklist (correctness, security, API, observability, complexity, errors, docs) | A code-reviewer; S pr-review; G Verify gate |
| Critical/Suggestion/Nice to have labels | A code-reviewer; S pr-review |
| Critical = merge blocker | G Verify gate, Release gate |

## workflow-orchestration.mdc

| Clause | Enforcer |
|--------|----------|
| Phases Intake→Design→Build→Verify→Release; Maintain→Verify | C /v0-intake, /v0-design, /v0-build, /v0-verify, /v0-maintain, /v0-release, /v0-deliver |
| Gates per phase | G Intake/Design/Build/Verify/Release gates; all phase commands |
| Approval stops | C /v0-deliver; R ai-agent-conduct; CI ci/check-approvals.sh (merge-time) |
| Critical findings route back | C /v0-verify, /v0-deliver; G Verify gate |
| Gate decisions, approver, date, and evidence recorded in the existing handoff artifact | C all phase commands; R workflow-orchestration; CI ci/check-approvals.sh, ci/check-evidence.sh |
| Merge-request readiness is intermediate; completion is an authorized human merge, with no follow-up commit to record it | C /v0-release, /v0-deliver; A release-manager; S release-pr; R workflow-orchestration |
| Build: green baseline before edits, skipped when the checkout is already the default branch tip with a clean tree; red–green loop may use the profile fast verify command; the gate still runs the profile Backend verify command (pack `java`: full `./mvnw -B clean verify`, coverage/static/CVE) | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer; S implement-*; G Build gate |
| Build: tests ship with new behavior (red–green; VAPT-required tests in the same diff) | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer; S implement-*, quality-gate; G Build gate |
| Build: contract conformance and ArchUnit layer rules | R workflow-orchestration; C /v0-build; S implement-spring-service, implement-bff; G Build gate |
| Build: bounded fix attempts and escalation instead of loops | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer; S implement-* |
| Build: `docs/agents-v0/build/<feature>/plan.md` has one row per approved `AC-*`; rows are not added or rewritten | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer; S implement-*; G Build gate |
| Build: second red result of the same test writes `failure-brief.md`; `debug-investigator` runs before attempt three; `check-failure-brief.sh` must pass | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer, debug-investigator; S implement-*; `scripts/check-failure-brief.sh` |
| Build: each verify attempt records a command-result card; the next attempt does not read `build-output.txt` | R workflow-orchestration; C /v0-build; A backend/bff/frontend-engineer; S implement-* |
| Build: red–green uses a real fast verify profile cell (not a placeholder); full verify only at the gate | S implement-*; bootstrap-greenfield.sh fills Backend/Frontend fast cells; G Build gate |
| Design: prefer snippet packs for CRUD OpenAPI, sync-vs-async ADR, one-screen UX | S contract-first-design, ux-design; `docs/agents-v0/snippets/` |
| Phase result file `docs/agents-v0/requirements/<feature>.phase-result.md` is the handoff the next phase reads. Intake also copies `user_story`, `ac_count`, `negative_count`, `regulations`, and `open_questions` | R workflow-orchestration; A orchestrator; C /v0-intake, /v0-design, /v0-build, /v0-verify, /v0-maintain, /v0-release |
| Verify: `test-engineer` first; `security-reviewer` and `code-reviewer` together; one gathered Critical list | R workflow-orchestration; A orchestrator, security-reviewer, code-reviewer; C /v0-verify, /v0-deliver; G Verify gate |
| Build evidence persisted under `docs/agents-v0/build/<feature>/` and referenced from approvals | R workflow-orchestration; C /v0-build, /v0-verify; CI ci/check-evidence.sh |
| Design: feature contract draft at `docs/agents-v0/design/<feature>/openapi.yaml` when the story adds a `/api/v1` operation; org catalog unchanged until Build merges it. P0-A and a no-contract story do not add a draft | R workflow-orchestration; A solution-architect; S contract-first-design; C /v0-design; G Design gate |
| Design: UX spec and HTML mockups exist (flows, state matrix, per-component defaults, a11y, responsive, design-system conformance, UX acceptance criteria) | R workflow-orchestration; A ux-designer; S ux-design; C /v0-design; G Design gate |
| Design: threat-model notes (assets, trust boundaries, top risks) for non-trivial security, naming always-on VAPT findings F4, F8, F9, F10 | A solution-architect; S contract-first-design; C /v0-design; G Design gate |
| Verify: a11y check green and UX acceptance criteria covered for UI-affecting changes | R workflow-orchestration; A test-engineer; S quality-gate; C /v0-verify; G Verify gate |
| Intake: user story (`As a` / `I want` / `so that`) split into stable `AC-*` headings, one Gherkin scenario each, with `Kind` and an observable `Then` (the analyst and the approver judge the result; `ci/check-intake.sh` checks `Kind`, `Then` length, and the banned phrases only); one negative or edge, or `Negatives: N/A` when no security-review trigger applies; preconditions and a desk check; out of scope listed separately; `Material: yes` or `Material: no`; NFRs recorded; open questions are `none`. P0-A is copied by `/v0-build` from the milestone and skips `ci/check-intake.sh` | A requirements-analyst; S spec-intake; C /v0-intake, /v0-build; G Intake gate; CI ci/check-intake.sh |
| Intake: one primary surface unless `Vertical slice: yes`; at most `AC-8`, including the negative or edge; oversized stories stop on `## Proposed split`. P0-A is already one story, stays at four criteria, and is not split | A requirements-analyst; S spec-intake; C /v0-intake, /v0-build, /v0-plan; R workflow-orchestration; G Intake gate, Plan gate |
| Milestone programs: manifests group user stories into incremental delivery (P0..P5); story chains + go/no-go | C /v0-intake (story links); R workflow-orchestration; CI ci/check-approvals.sh (milestone row), ci/check-milestone.sh |
| P4 SLO rows close with `docs/agents-v0/design/system/slo-evidence.md`: each filled row is measured or waived | A test-engineer; S slo-evidence; C /v0-verify; R workflow-orchestration; CI ci/check-milestone.sh (verify/release when the manifest names the file) |
| Contract draft is valid and compatible: OpenAPI 3.0, `/api/v1`, unique operationIds, security, Idempotency-Key on POST, one error envelope, no breaking change to the catalog | A solution-architect; S contract-first-design; C /v0-design; G Design gate; CI ci/check-openapi.sh (lint, compat), ci/check-design-contracts.sh |
| Design is complete and traceable: every AC mapped, every `Kind: negative` and `Kind: edge` id named in Failure modes, an authorization row per operation, data model, failure modes, observability, rollout, ADR with alternatives and Status `Proposed` or `Accepted` (the pin requires `Accepted`) or `ADR: N/A: no product decision`. An accepted ADR is superseded, not rewritten. P0-A writes this file in `/v0-build` | A solution-architect; S contract-first-design; C /v0-design, /v0-build; G Design gate; CI ci/check-design.sh, ci/check-adr.sh |
| Independent design review when the story has a contract, a UI, or a public route other than `/health`, `/ready`, or `/live`; no open Critical before the design is pinned. Otherwise the design pins without `review.md` and without a Design stop; that row is written with the Build approval. P0-A is pinned in Build and approved at Release | A design-reviewer; C /v0-design, /v0-build; G Design gate; `ci/check-design.sh --pin` |
| A contract, UI, or public-route design is pinned after approval, including the cited ADR. A no-contract design and P0-A are pinned first (`design.lock`). A later change needs `design-reviewer` on the design as it stands, then an Approved amendment row, then a new pin. An Accepted ADR is superseded, not rewritten | C /v0-design (Amending an approved design), /v0-build; CI ci/check-design.sh --verify-lock, ci/check-adr.sh, ci/check-delivery-linkage.sh |
| UX spec and mockups agree (`data-component` on every control, a row per control, operations exist in the draft, no API call in a mockup) | A ux-designer; S ux-design; C /v0-design; CI ci/check-ux-spec.sh |
| Architecture owners review `docs/agents-v0/design/`, `docs/agents-v0/adr/`, and the `openapi/` catalog | CODEOWNERS |
| The catalog merge is proven: the catalog contains every operation and component of the approved draft | C /v0-build; S implement-*; CI ci/check-openapi.sh merged |
| Build plan is real: one row per AC, each done row names an existing test with a red card first | C /v0-build; S implement-*; CI ci/check-build-plan.sh (via ci/check-delivery-linkage.sh) |
| No new Spring endpoint without a security annotation (`@PermitAll` marks a public one) | C /v0-build; S implement-spring-service; CI ci/check-endpoint-auth.sh |
| The frontend calls only operations the catalog lists | C /v0-build; S implement-frontend; CI ci/check-frontend-calls.sh |
| Runtime OpenAPI matches the catalog in both directions (a missing or an undocumented endpoint fails) | C /v0-build; `maven/contract-conformance.xml` |
| `/v0-deliver` runs the phase commands in order and holds no phase detail of its own; resumes from the state file; a reopened phase is marked `Re-opened` until re-approved. P0-A skips `/v0-intake` and `/v0-design` and stops once at Release. Build copies the milestone story. A no-contract story does not stop at Design | C /v0-deliver; A orchestrator; R workflow-orchestration |
| Merge and approval of a merge request are human acts on the default host: `glab mr merge`, `glab mr approve`, and merge/approve through `glab api` are blocked; `glab mr create`, `glab ci trigger`, state-changing `glab api`, and `git tag` ask | H-B / H-ask pre-shell.sh; hook-policy.py shell |
| Optional local release after Verify: Decision `Local` (not Approved). `/v0-release` does not require it. After the checkpoint the next story may start | C /v0-local-release, /v0-release, /v0-status; S local-release; `scripts/resolve-integration-branch.sh`; `scripts/sync-feature-state.sh --clear-active` |
| Local dry run of the delivery gate before the push; the MR description is rendered from the evidence | C /v0-release; S release-pr; `scripts/render-mr-body.sh`; CI ci/check-delivery-linkage.sh |
| Release approver is the GitLab username that approves the MR; the manual `delivery-approval` job is played by a person or with explicit authorization | C /v0-release; S release-pr; CI ci/check-approver-gitlab.sh |
| CI fix loop is capped at three rounds; a code fix re-enters Verify | C /v0-release; S release-pr |
| Deployment records never go straight to the default branch (docs-only follow-up MR or release issue) | C /v0-release; S release-deploy; R workflow-orchestration Release gate |
| Changelog and release notes come from approved stories; the release owner picks the version and tags | C /v0-release; `scripts/release-notes.sh`; `docs/agents-v0/project-profile.md` Release rows |
| Maintenance record: every fix, CVE patch, upgrade, or hotfix has `docs/agents-v0/maintain/<id>/note.md` with its own `maintain` and `verify` rows and evidence; it never borrows a feature artifact | A maintenance-engineer; S bugfix-triage, dependency-upgrade, doc-sync; C /v0-maintain, /v0-verify; CI ci/check-delivery-linkage.sh (`Maintain-Note`; a feature artifact needs build or verify evidence in the same change) |
| Trivial lane is qualified by the diff (docs-only or version-only, no security surface, schema, major bump, or delivery artifact; size-bounded) and confirmed by a person | C /v0-triage, /v0-maintain; CI ci/classify-change.sh, ci/check-delivery-linkage.sh |
| Abbreviated Verify (Tier trivial): test-engineer only, full verify command, gate metrics, CVE re-scan | C /v0-verify; A test-engineer; S quality-gate |
| Emergency tier: person-confirmed, rollback recorded, Verify owed by `Follow-up verify due` (OVERDUE in the metrics) | C /v0-maintain; CI ci/check-delivery-linkage.sh; `scripts/delivery-metrics.sh` |
| Maintenance discipline: baseline first, failing test before the fix, attempt budget, critical-unit model, dependency graph diff | C /v0-maintain; A maintenance-engineer; S bugfix-triage, dependency-upgrade; `scripts/check-attempt-budget.sh`; R docs/agents-v0/model-routing-matrix.md |
| Change tiers (Trivial / Standard / Major); `/v0-triage` | C /v0-intake, /v0-triage, /v0-deliver; A orchestrator; R workflow-orchestration |
| Machine-readable resume (`lastApprovedPhase`, `activePhase`, `activeStatus`, `blockedReason`) | C /v0-status; R workflow-orchestration Phase resume; `scripts/sync-feature-state.sh`; CI ci/check-feature-state.sh (optional) |
| Parallel features: per-feature artifacts; feature contract drafts under `docs/agents-v0/design/<feature>/` are not shared; stop before a second writer touches a shared file; creating a branch needs explicit user authorization | R workflow-orchestration Parallel features; C /v0-status, /v0-design, /v0-build, /v0-verify, /v0-release, /v0-maintain |
| Helper agents (`explore-researcher`, `schema-author`, `debug-investigator`, `docs-author`) are launched from the main session, not from inside a phase agent. A known `/api/v1` contract launches `schema-author` in the same turn as `solution-architect`, with no brief. Other helpers start from a helper brief | R workflow-orchestration Helper agents; A orchestrator; C /v0-intake, /v0-design, /v0-verify, /v0-maintain |
| Roadmap: `/v0-roadmap <path>` reads only the discovery file the user names, wherever it sits in the repo, and writes a now / next / later sequence. The `roadmap` row covers the sequence. The discovery file has no kit approval row | A program-planner; S program-roadmap; C /v0-roadmap; R workflow-orchestration Roadmap; CI ci/check-approvals.sh (roadmap) |
| Architecture before backlog: `/v0-architecture` writes C4 through operations and the ARC record. One approval records the `architecture` row and names the ARC file. An `arc` row is only a later amendment. Plan does not rewrite the pack. Skip list: `workflow-orchestration.mdc` Architecture | A solution-architect, design-reviewer; S program-architecture; C /v0-architecture; R workflow-orchestration Architecture; G Architecture gate; CI ci/check-approvals.sh (architecture), ci/check-arc.sh (architecture row may cover a material story), ci/check-milestone.sh (`Architecture:` line), ci/check-architecture-pack.sh |
| Program planning: `/v0-plan` reads the approved architecture pack and writes milestone manifests from the approved roadmap, with Surface and Size on each story, plus `docs/agents-v0/milestones/plan.md` (milestone table and story flowchart). It does not rewrite the pack. The Plan gate is a `plan` row. A P0-A-only plan does not require a roadmap or an architecture row | A program-planner, orchestrator; S program-planning; C /v0-plan; R workflow-orchestration Program planning; CI ci/check-approvals.sh (plan), ci/check-milestone.sh (`Roadmap:` and `Architecture:` lines), ci/check-delivery-linkage.sh |
| ARC: a `Material: yes` story cites `docs/agents-v0/design/system/arc-record.md`. `ci/check-arc.sh` accepts an `Approved` `architecture` row that names that file. An `arc` row is added only when the story amends the recommendation, and that row is separate from Design. P4 closes the SLO rows in `docs/agents-v0/design/system/nfr-slo.md`. A no-contract shortcut does not apply | A solution-architect; S contract-first-design; C /v0-design; R workflow-orchestration Design gate; CI ci/check-arc.sh, ci/check-approvals.sh (architecture or arc) |
| Architecture pack is complete and consistent: data flow reuses the C4 Container nodes, logical and physical data models, state machine, failure domains and degradation, target topology, MVP and future state, `N/A: <reason>` where a section does not apply. C4 names no product technology | A solution-architect; S program-architecture; C /v0-architecture; G Architecture gate; CI ci/check-architecture-pack.sh (also from ci/check-milestone.sh `--approved`) |
| Architecture pack has an independent review: `design-reviewer` writes `architecture-review.md` and no Critical stays open before the `architecture` row | A design-reviewer; S program-architecture; C /v0-architecture; G Architecture gate; CI ci/check-architecture-pack.sh |
| Operations readiness: ownership, error budget policy, and database operation are written at architecture time. The P5 story ticks the checklist. A production deploy waits on those boxes. The pack check requires the sections, not ticked boxes | A solution-architect, release-manager; S program-architecture, release-deploy; C /v0-architecture; CI ci/check-architecture-pack.sh |
| Structural fitness functions (principle, check, threshold, on failure) recorded in the ARC record. SLO targets stay in `nfr-slo.md` | A solution-architect; S program-architecture; R architecture-and-diagrams; CI ci/check-architecture-pack.sh |
| Component plan per bounded context links its parent and does not contradict it; the context map is the service map | A solution-architect; S program-architecture; R architecture-and-diagrams; CI ci/check-architecture-pack.sh |
| Contract retirement is additive: `deprecated: true` with a sunset date, removal in a later change, a major version or ADR for a breaking change | A solution-architect; S contract-first-design, program-architecture; R api-and-events |
| Export and deck: derived documentation. `/v0-deck intake` reads one approved requirements artifact. Product and delivery decks also read every approved Intake artifact. They do not edit approvals, and a missing file does not block a gate | C /v0-export, /v0-deck; S jira-export, leadership-deck; R workflow-orchestration Documentation |
| Story order: a build-approved story needs a Verify approval on every story it depends on | R workflow-orchestration Plan gate; A orchestrator; CI ci/check-milestone.sh (`MILESTONE_ORDER=0` disables) |
| One worktree and branch per feature; creating it needs explicit authorization | R workflow-orchestration Worktree per feature; `scripts/feature-worktree.sh`; H-ask pre-shell.sh; hook-policy.py shell |
| Batch approval of Intake and Design for named, low-risk stories (one row per story artifact) | R workflow-orchestration Batch approval; A orchestrator; CI ci/check-approvals.sh (per artifact) |
| Phase attempt budget: total failed attempts per phase are capped | R workflow-orchestration Phase attempt budget; C /v0-build; S implement-*; `scripts/check-attempt-budget.sh` |
| Verify numbers read from machine output: executed tests, diff coverage, unsuppressed HIGH/CRITICAL CVEs | R workflow-orchestration Verify gate; CI ci/check-gate-metrics.sh |
| Event schemas evolve additively and record `eventVersion` | R api-and-events; A solution-architect; S contract-first-design; CI ci/check-event-schemas.sh |
| Messaging: outbox, idempotent consumers, DLQ, saga compensations, with tests | A backend-engineer; S implement-messaging; G Build gate |
| E2E journeys, consumer-driven contract pairs, resilience cases, k6 SLO measurements | A test-engineer; S e2e-perf-testing, slo-evidence; C /v0-verify; G Verify gate; CI ci/check-milestone.sh (`SLO_ALLOW_WAIVERS=0`) |
| Deployment per environment: own authorization, smoke check, rollback (when the profile has a Deploy table) | A release-manager; S release-deploy; C /v0-release; R workflow-orchestration Release gate |
| Critical units (security triggers, sagas, consumers) run on the Plan-role model; reviewers are independent of the builder | R docs/agents-v0/model-routing-matrix.md; C /v0-build |

## Onboarding

| Clause | Enforcer |
|--------|----------|
| Multi-repo workspace manifest | `docs/agents-v0/workspace.manifest.json`; C /v0-onboard; A codebase-documenter, orchestrator |
| Existing codebase documented as-is: baseline numbers, inventories, module documents, architecture, network, context map, inherited ADR, flows | A codebase-documenter; S onboard-discovery; C /v0-onboard; G Onboard gate; `scripts/discover-codebase.sh`, `scripts/generate-repo-map.sh`, `scripts/collect-dependency-graphs.sh` |
| Onboarding documents cite real code, carry the commit they describe, and leave no template line | `scripts/check-onboarding-docs.sh`; C /v0-onboard; G Onboard gate |
| No secret value in onboarding output (configuration by key name only); literal secrets reported by key | A codebase-documenter; `scripts/discover-codebase.sh`; R security-baseline |
| Onboarding approval (`onboard` row) recorded and bound to its evidence; `/v0-intake` and `/v0-plan` wait for it | C /v0-onboard, /v0-intake, /v0-plan; A orchestrator; CI ci/check-approvals.sh (onboard), ci/check-evidence.sh, ci/check-delivery-linkage.sh |

## Hooks and CI guardrails (kit)

| Control | Enforcer |
|---------|----------|
| Shell deny/ask (git, secrets, rm, kubectl, protected-path shell writes) | H-B pre-shell.sh; hook-policy.py |
| Protected path edits (hooks, every `.agents-v0/ci/*.sh` gate script and every `.agents-v0/scripts/*.sh` kit script, agents, rules, commands and skills, entry files) | H-B pre-edit.sh; hook-policy.py path; CODEOWNERS (`/.agents-v0/`, the project profile) |
| Credential reads outside the repository (SSH and GPG keys, cloud and cluster credentials, `*.pem` and `*.key`) and environment dumps (`declare -x`, `compgen -e`, `/proc/*/environ`) are blocked; `git restore`, branch create/delete/rename, `sudo`, and a download piped into an interpreter ask first | H-B/H-ask pre-shell.sh; hook-policy.py shell |
| The delivery jobs read the whole `.agents-v0/ci` directory from the default branch, so every script the linkage check calls is trusted | `.gitlab-ci.yml` (`.delivery-linkage`); validate-kit |
| When a phase has several approval rows the last one is the current decision, and a conditional approval (`with conditions`, `pending`, `provisional`) is not an approval | CI ci/check-approvals.sh, ci/check-evidence.sh, ci/check-approver-gitlab.sh, ci/check-delivery-linkage.sh, ci/check-feature-state.sh; scripts/sync-feature-state.sh |
| A green build means the checks ran: a JVM module with no resolved root fails CI | CI ci/check-layout-roots.sh (build and gate-metrics jobs) |
| Delivery/milestone artifact edits (human gate) | H-ask pre-edit.sh; hook-policy.py path |
| `git rebase`, `git merge`, `git cherry-pick`, `git revert`, and `git stash pop/drop/clear` ask first | H-ask pre-shell.sh; hook-policy.py shell |
| Local pre-push gate (linkage, design contracts, build plan, endpoint auth) | `scripts/check-delivery-gate-local.sh` |
| Session context (profile, repo map, state) | session-start.sh |
| PR code ↔ feature artifact linkage | CI ci/check-delivery-linkage.sh |
| Verify approval bound to a human GitLab approver named in the Approver column | CI ci/check-approver-gitlab.sh (manual `delivery-approval` job) |
| Release or verify approval bound to a human GitLab approver named on either row | CI ci/check-approver-gitlab.sh from the default branch (manual `.gitlab-ci.yml` job `delivery-approval`; `GITLAB_TOKEN` is `read_api` and scoped to that job's environment) |
| Evidence `commit:` + staleness vs PR head | CI ci/check-evidence.sh |
| Build failures cannot be masked by log piping | CI `.gitlab-ci.yml` (`set -o pipefail` in build/verify job scripts) |
| Brownfield test failure budget: after a failed verify only test failures inside the `known_failures` budget are excused, never a compile or plugin error | CI ci/check-known-failures.sh (`--require-failures`), ci/check-gate-metrics.sh; `.gitlab-ci.yml` build job; docs/agents-v0/project-profile.md |
| Kit scripts named in `.gitlab-ci.yml` resolve under `.agents-v0/`; the CI file parses; JaCoCo, ArchUnit, and Node minimums hold | scripts/validate-kit.sh |
| Brownfield coverage ratchet | R quality-and-testing; CI ci/check-coverage-ratchet.sh; docs/agents-v0/project-profile.md `coverage_ratchet` |
| Secret scan | CI `.gitlab-ci.yml` (`Security/Secret-Detection.gitlab-ci.yml` include) |
| Delivery and hook metrics (approved gates, failed attempts, blocked features per feature) | scripts/delivery-metrics.sh |
| Optional compliance audit manifest (SHA-256 of delivery evidence) | scripts/export-audit-pack.sh |
| AsyncAPI contract lint (when `docs/agents-v0/design/<feature>/asyncapi.yaml` exists) | CI ci/check-asyncapi.sh; ci/check-design-contracts.sh |
| Private/air-gapped CI container pulls | `.gitlab-ci.yml` variable `CI_IMAGE_PREFIX`; docs/agents-v0/project-profile.md |
| Branch, worktree, or `feature-worktree.sh` creation asks first | H-ask pre-shell.sh; hook-policy.py shell |
| Behavior tests for the template CI scripts | scripts/test-ci-checks.sh (run by validate-kit.sh) |
