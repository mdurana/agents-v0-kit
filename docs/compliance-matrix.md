# Compliance matrix

Maps every org rule clause to the agent, skill, hook, or gate that covers it. It is a coverage map, not proof that a project change complies; delivery evidence comes from the relevant tests, scans, reviews, approvals, and CI results.

Legend: **A** = agent instruction/review, **S** = skill checklist, **H-B** = blocking hook, **H-W** = warning hook, **G** = human-approved gate, **C** = command workflow check, **CI** = CI-side blocking check script, **R** = rule. A/S/C/R describe prompted or manual review, not deterministic enforcement. Gates require recorded evidence and approval; N/A is allowed only for an unaffected surface and never for an applicable Critical VAPT item.

Tool note: hook rows (H-B/H-W) run on Cursor (`.cursor/hooks.json`) and Claude Code (`.claude/settings.json` PreToolUse/PostToolUse/Stop). Kilo Code has no hook runtime — the same contract is enforced via `kilo.json` `permission.bash` (deny/ask patterns) and the CI checks.

## project-delivery-core.mdc

| Clause | Enforcer |
|--------|----------|
| Canonical stack (Spring Boot 3.x, PostgreSQL, Flyway, OpenAPI) | A backend-engineer; S implement-spring-service; G Build gate |
| Frontend: ask Svelte or React once | A requirements-analyst, frontend-engineer; S spec-intake, implement-frontend; G Intake gate |
| Directory profiles (service, ui, app) | R project-delivery-core; `docs/project-profile.md`; C /onboard; CI ci/resolve-layout.sh |
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

## ai-agent-conduct.mdc

| Clause | Enforcer |
|--------|----------|
| Reconnaissance → Plan → Execute → Verify → Report | R workflow-orchestration; all agents; all skills |
| Lead with conclusion; no filler/sycophancy | All agents (system prompt) |
| Minimize scope; no drive-by refactors | A maintenance-engineer; S bugfix-triage, dependency-upgrade |
| Shell: non-interactive, bounded | A all agents; R ai-agent-conduct |
| Ask user only when blocked | R workflow-orchestration (approval stops); all agents |
| Do not commit unless asked | A release-manager; S release-pr; H-B pre-shell.sh (asks on git commit/push; denies force-push/hard reset, `gh pr merge`, destructive git clean; no env/command bypass) |
| No force-push/hard reset | H-B pre-shell.sh; S release-pr |
| PR creation via gh | A release-manager; S release-pr; C /release |
| Rule precedence: repository wins | R workflow-orchestration; `docs/project-profile.md`, ADRs |

## security-baseline.mdc

| Clause | Enforcer |
|--------|----------|
| §1 Authn (OAuth2/JWT, MFA, logout, blacklist fail-closed, dev bypass local) | A backend-engineer, bff-engineer; S implement-spring-service, implement-bff; R vapt-spring F1 |
| §2 Authz (`@PreAuthorize`, server-side, no client role trust, BOLA) | A backend-engineer, bff-engineer, frontend-engineer; S implement-*; H-W after-edit.sh (heuristic only — Verify/Sonar authoritative); R vapt-spring F4, vapt-webapp F4; G Build gate |
| §3 Secrets (vault/env, no client exposure, PII not in URLs, sanitize logs) | A all build agents; H-B pre-shell.sh (obvious secret-output commands); H-W after-edit.sh (limited public-env heuristic); R vapt-webapp F2 |
| §4 Cookies (HttpOnly, Secure, SameSite) | A frontend-engineer; S implement-frontend; H-W after-edit.sh (`document.cookie` write heuristic); R vapt-webapp F7 |
| §5 Uploads (size, content sniff, structure, authz) | A backend-engineer; S implement-spring-service; H-W after-edit.sh (filename-validation heuristic); R vapt-spring F3 |
| §6 Headers (HSTS, nosniff, X-Frame, CSP, Referrer) | A backend-engineer, frontend-engineer; H-W after-edit.sh (`nosniff` heuristic); R vapt-webapp F2 |
| §7 API security (versioned, auth, rate limit, parameterized SQL) | A solution-architect, backend-engineer, bff-engineer; S contract-first-design, implement-*; H-W after-edit.sh (Java SQL-concatenation heuristic); R vapt-spring F5 |
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
| Methods ≤ 30 lines, complexity ≤ 15 | A backend-engineer, code-reviewer; S implement-spring-service, pr-review; G Build/Verify gate |

## frontend-web.mdc

| Clause | Enforcer |
|--------|----------|
| SvelteKit/React structure, load/server loads, browser guard | A frontend-engineer; S implement-frontend |
| API client: Bearer, X-Correlation-ID, traceparent, 401 handling | A frontend-engineer; S implement-frontend; G Build gate |
| Accessibility (semantic HTML, keyboard, ARIA, reduced motion) | A frontend-engineer; S implement-frontend; G Verify gate (a11y check) |
| XSS: sanitize/avoid innerHTML/{@html}/dangerouslySetInnerHTML | A frontend-engineer; S implement-frontend; A code-reviewer; S pr-review |

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

## quality-and-testing.mdc

| Clause | Enforcer |
|--------|----------|
| AAA pattern; naming conventions | A test-engineer; S quality-gate |
| Coverage ≥ 80% backend / 70% frontend | A test-engineer; S quality-gate; G Verify gate |
| Methods ≤ 30 lines, complexity ≤ 15 | A code-reviewer; S pr-review; G Verify gate |
| Testcontainers + Pact where repo depends | A test-engineer; S quality-gate |
| No new high/critical CVEs | A test-engineer, maintenance-engineer; S quality-gate, dependency-upgrade; G Verify gate |
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
| Merge-request readiness is intermediate; completion after human-authorized merge | C /release, /deliver; A release-manager; S release-pr; R workflow-orchestration |
| Build: green baseline before edits; wired quality gate (coverage/static/CVE fail `mvn -B clean verify`) | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-*; G Build gate |
| Build: tests ship with new behavior (red–green; VAPT-required tests in the same diff) | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-*, quality-gate; G Build gate |
| Build: contract conformance and ArchUnit layer rules | R workflow-orchestration; C /build; S implement-spring-service, implement-bff; G Build gate |
| Build: bounded fix attempts and escalation instead of loops | R workflow-orchestration; C /build; A backend/bff/frontend-engineer; S implement-* |
| Build evidence persisted under `docs/build/<feature>/` and referenced from approvals | R workflow-orchestration; C /build, /verify; CI ci/check-evidence.sh |
| Design: UX spec and HTML mockups exist (flows, state matrix, per-component defaults, a11y, responsive, design-system conformance, UX acceptance criteria) | R workflow-orchestration; A ux-designer; S ux-design; C /design; G Design gate |
| Verify: a11y check green and UX acceptance criteria covered for UI-affecting changes | R workflow-orchestration; A test-engineer; S quality-gate; C /verify; G Verify gate |
| Milestone programs: manifests group user stories into incremental delivery (P0..P5); story chains + go/no-go | C /intake (story links); R workflow-orchestration; CI ci/check-approvals.sh (milestone row), ci/check-milestone.sh |
| Change tiers (Trivial / Standard / Major); `/triage` | C /intake, /triage, /deliver; A orchestrator; R workflow-orchestration |
| Machine-readable resume (`lastApprovedPhase`, `activePhase`, `activeStatus`) | C /status; R workflow-orchestration Phase resume; `scripts/sync-feature-state.sh`; CI ci/check-feature-state.sh (optional) |
| Parallel features: per-feature artifacts; stop before a second writer touches a shared file | R workflow-orchestration Parallel features; C /status, /design, /build, /verify, /release, /maintain |
| Multi-repo workspace manifest | `docs/workspace.manifest.json`; C /onboard; A orchestrator |

## Hooks and CI guardrails (kit)

| Control | Enforcer |
|---------|----------|
| Shell deny/ask (git, secrets, rm, kubectl, protected-path shell writes) | H-B pre-shell.sh; hook-policy.py; Kilo kilo.json |
| Protected path edits (hooks, CI, agents, rules, entry files) | H-B pre-edit.sh; hook-policy.py path |
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
| Delivery and hook metrics | scripts/delivery-metrics.sh |

**Kilo Code limits:** Kilo has no hook runtime, so protected-path edits, delivery-artifact edit prompts, MCP policy, and session context are **not** enforced there. Kilo relies on `kilo.json` bash patterns, agent `tools:` maps (reviewers without `write`/`bash` stay read-only), CODEOWNERS, and the CI checks above.
