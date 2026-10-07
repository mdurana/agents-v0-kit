# Builder quality patterns

Lookup for Lead Builder `review-implementation` and `audit-and-approve-code`. Sources in `references/agent-skills-main/skills/`: `code-review-and-quality`, `debugging-and-error-recovery`, `code-simplification`, `git-workflow-and-versioning`, `browser-testing-with-devtools`, `performance-optimization`, `security-and-hardening`.

**Authoritative constitution detail** (load when auditing or reviewing):

- [git-delivery-standards.md](git-delivery-standards.md). Branch, commit, and scoped-MR law
- [merge-request-patterns.md](merge-request-patterns.md). Draft MR title and body schema
- [implementation-quality-standards.md](implementation-quality-standards.md). SOLID, defensive design, testing standards

Constitution: 100% meaningful coverage is mandatory (coverage gates in [constitution-core.mdc](../../rules/constitution-core.mdc)). Testcontainers, Checkstyle, PMD, SpotBugs, and `mvn` are Java-only. N/A on iOS and Android. Java diffs must also pass SonarQube / `sonarqube_check` per [implementation-quality-standards.md](implementation-quality-standards.md) as well as JaCoCo. The reference skills' ~80% unit pyramid does not apply.

Do not load `references/agent-skills-main/skills/*/SKILL.md` when this file applies.

Builder build steps live in [build-execution-patterns.md](build-execution-patterns.md).

---

## Scope by skill

| Check category | `review-implementation` | `audit-and-approve-code` |
|----------------|-------------------------|--------------------------|
| Correctness vs `story-tasks.md` and Gherkin AC | Current increment only | Full MR, all increments |
| Security | Changed code in the increment | Full MR |
| Performance | Changed code in the increment | Full MR plus integration |
| Design fidelity | Increment slice | End-to-end |
| Quality gates | Increment verify command | Platform verify (`mvn clean verify` on Java; `xcodebuild` on iOS; Gradle on Android) |
| MR hygiene | Not this skill | Full MR |
| Standards (Git, naming, SOLID, clean code, tests) | Not this skill | Full MR. See MR standards checklist |
| Browser smoke | Optional per increment | Optional before QA handoff |

| Phase | Skill | Trigger |
|-------|-------|---------|
| Per increment | `review-implementation` | Task complete during Builder `trigger-ai-build` |
| MR, QA handoff | `audit-and-approve-code` | All increments approved; human opened MR on `MR_BRANCH` |

---

## Increment review

`review-implementation` uses this slice. It does not run the full MR standards checklist. Branch regex, SOLID, method length, and package depth belong to `/audit`.

| Axis | Check |
|------|-------|
| Correctness | Matches the `story-tasks.md` item and the traceable `epic-spec.md` backlog index Gherkin AC. No scope creep. |
| Security | Input validation at boundaries. Parameterized queries. No secrets in code or logs. Authz on mutations. |
| Performance | No obvious N+1 or unbounded queries in changed code. Pagination where lists are large. |
| Design fidelity | Matches OpenAPI contracts and the approved architecture. No undocumented stack drift. |
| Quality gates | 100% meaningful coverage on the measured scope. Java: Testcontainers, RFC 7807, stateless K8s, Checkstyle, PMD, SpotBugs. iOS: XCTest/`xcodebuild`. Android: Gradle. Mark JVM-only gates N/A on mobile. |

### Failed verify

If an increment fails verification or gates:

1. Stop. Do not approve the next `story-tasks.md` item.
2. Capture the failing test or verify output.
3. Narrow to the changed files for the active task.
4. Fix the root cause. Add a regression test.
5. Re-run the platform verify command (`mvn clean verify` on Java, `xcodebuild test` on iOS, `./gradlew test` on Android) before re-approval.

If the root cause is architectural, route to Lead Builder `orchestrate-design` or the matching SA skill. Do not accept silent drift.

### Optional UI smoke

If the increment includes user-facing UI and DevTools MCP is available:

- Reproduce the primary happy path for the story.
- Check the console for errors. Check that network calls match the expected API contracts.
- Confirm loading, error, and empty states exist.

This does not replace unit or integration gates, or MR audit. If MCP is unavailable, skip and record that in the review notes.

### Code-level performance and security

| Concern | Increment action | Route to SA when |
|---------|------------------|------------------|
| N+1 queries, missing pagination | Reject the increment. Request a fix. | Caching strategy or SLO budget is undefined. |
| Slow hot path | Request profile evidence. | An architecture-level caching decision is needed. |
| Missing input validation | Reject the increment. | Platform IAM or a network boundary change. |
| Authz gap on an endpoint | Reject the increment. | A new security boundary needs an ADR. |

---

## MR audit

`/audit` uses this list on the full MR, not on each increment.

### Reviewer rules

A finding names file and line when the issue is in the diff. Suggest improved code when that is clearer than prose. Use repo context: imports and call chains. Flag a pre-existing issue only when it touches the diff or blocks the change. Do not file speculative or low-confidence findings. Constitution and mandatory gate failures are never low confidence.

### MR audit checklist

| Axis | Check |
|------|-------|
| Correctness | Gherkin and `story-tasks.md` coverage. Logic bugs. Invalid assumptions. Edge cases. Nulls. State transitions. Contract violations. Data consistency. |
| Reliability | Races. Concurrency. Failure handling. Retries and idempotency. Resource leaks. Timeouts. |
| Security | OWASP at boundaries. Injection. SSRF, XSS, CSRF. Secrets in code or logs. Authz on mutations. Privilege escalation. |
| Performance | N+1. Pagination. Re-renders. Memory. Blocking work. Cache staleness and invalidation. |
| Maintainability | Readability. Simplification pass. Duplication. Hidden side effects. Coupling. |
| Architecture | SOLID and clean-code clusters. Business logic in controllers. Infra leaking into domain. Framework coupling in domain. Circular deps. Domain must not depend on infra. ADR gaps go to `architecture-governance`. |
| Scalability | Sync bottlenecks. Hot partitions. Shared mutable state. Centralized coordination. |
| Project consistency | `.cursor/rules/constitution-custom.mdc` and the MR standards checklist. Flag unjustified divergence. |
| Backward compatibility | API, event schema, migration safety, consumer impact. |
| Tests | 100% meaningful coverage on the measured scope, mandatory. Tests assert behavior, not implementation. No assertion-free, getter-only, or coverage-counter-only tests. Testcontainers on Java; N/A on mobile unless the clone uses JVM integration tests. |

### Code simplification pass

After functional correctness:

1. Know why the code exists before you ask to remove it.
2. Name duplication, dead code, and over-abstraction in the MR diff.
3. Request cleanup that does not change behavior.
4. Confirm the full test suite is still green.

If simplification reveals defects, request rework via `trigger-ai-build`. Keep simplification off feature commits when you can.

### Git MR hygiene

Verify law before QA handoff per [git-delivery-standards.md](git-delivery-standards.md). Verify title and body shape per [merge-request-patterns.md](merge-request-patterns.md). Drafting is Session 4 `raise-merge-request`; `/audit` does not create the MR.

Before QA handoff:

- MR title and description follow merge-request-patterns and trace to `epic-spec.md` backlog index stories.
- Commits are atomic per increment where that is feasible.
- No unrelated changes outside sprint scope.
- Branch is mergeable. CI is green.

Apply branch and commit regex from `constitution-custom.mdc` when that file is present.

### MR standards checklist

Apply to the full MR diff during `audit-and-approve-code` only. Normative prose for naming, formatting, booleans, and quality gates: [implementation-quality-standards.md](implementation-quality-standards.md). Rows marked Mandatory are constitution or security gates. Rows marked Default-overridable may be specialized by `constitution-custom.mdc`. Mark each cluster Pass, Fail, or N/A in the audit report.

#### Git and packages

Default-overridable unless noted.

| Check | Rule |
|-------|------|
| Branch naming | Matches engagement layout. Exact regex from `constitution-custom.mdc` when that file is present. |
| Commit format | Headers `<type>: <description>` in imperative mood. |
| Package domain | Reverse-domain layout. |
| Package naming | Singular nouns for core concepts. |
| Package depth | Maximum 4 levels. |

#### Naming

| Check | Rule |
|-------|------|
| Types | PascalCase for classes and interfaces. Suffixes `*Controller`, `*Service`, `*Repository`, `*DTO`, `*Request`, `*Response`, `*Exception`. |
| Methods | camelCase starting with an action verb: `get*`, `set*`, `is*`, `has*`, `can*`, `find*`, `search*`, `create*`, `build*`. |
| Variables | camelCase, intention-revealing. |
| Constants | `UPPER_SNAKE_CASE`, `static final`. |
| Booleans | Prefixed `is`, `has`, or `can`. |

#### Architecture and SOLID

| Check | Severity | Rule |
|-------|----------|------|
| Single responsibility | Default-overridable | One reason to change per class. |
| Open or closed | Default-overridable | Extend via polymorphism without editing closed code. |
| Liskov | Default-overridable | Subtypes substitute parents without breaking callers. |
| Interface segregation | Default-overridable | Small client-specific interfaces. |
| Dependency inversion | Default-overridable | Depend on abstractions, not concretes. |
| Dependency count | Default-overridable | Too many mocks, for example 10 or more, hide design flaws. |
| Constructor injection | Default-overridable | Immutable deps via constructor. Prefer Lombok `@RequiredArgsConstructor` over field `@Autowired` when the stack is Java or Spring. Override in `constitution-custom.mdc`. |

#### Clean code

Numeric limits are default-overridable.

| Check | Rule |
|-------|------|
| Intention-revealing names | Names say what, not how. |
| DRY | No duplicate logic across components. |
| Method size | Prefer under 20 lines. Under 10 is better. |
| Parameters | Maximum 4. Introduce a parameter object if more. |
| Guard clauses | Early returns flatten nested conditionals. |
| File layout | Static constants, then injected deps, then public methods, then private helpers. |
| Dead code | Delete commented-out blocks. |
| Whitespace | No trailing whitespace. 4-space indent on Java/backend. Project formatter wins on mobile. |

#### Defensive design and logging

| Check | Severity | Rule |
|-------|----------|------|
| Null safety | Default-overridable | Handle nulls or return `Optional<T>`. |
| Edge cases | Default-overridable | Guard limits, empty collections, boundaries. |
| Input validation | Mandatory | Bean validation at the controller or API boundary. |
| Layer separation | Mandatory | Do not expose `@Entity` over endpoints. Use DTOs. |
| Exception context | Default-overridable | Log caught exceptions with matching parameters. |
| Global mapping | Mandatory on APIs | Custom runtime exceptions map to RFC 7807. |
| Lazy logging | Default-overridable | SLF4J `{}`, not string concatenation. |
| Sensitive data in logs | Mandatory | Omit secrets and PII. Log metadata or placeholders. |

#### Tests

| Check | Severity | Rule |
|-------|----------|------|
| Presence | Mandatory | New production paths have automated tests. 100% meaningful coverage on the measured scope. JaCoCo (Java) or the platform equivalent is green. |
| AAA | Default-overridable | Arrange, Act, Assert as separate steps. |
| Strategy | Default-overridable | Prefer state-based asserts over interaction-only mocks. |
| Mocking | Default-overridable | Mock only what is outside direct control. |
| Assertions | Mandatory | Tests assert outcomes. No assertion-free, getter-only, or coverage-counter-only tests. |
| Integration env | Mandatory where applicable | Java: Testcontainers, or real test resources. Not mocks for data sources. iOS/Android: N/A for Testcontainers; use XCTest/Gradle harnesses. |

### Finding write-up

Every finding uses this schema. The SDD report and the GitLab draft share it.

1. File, Line. Required when the issue is in the diff. Omit only for a cross-cutting gap such as a missing test file or a missing ADR.
2. What is the problem. Concrete: symbol, behavior, commit.
3. How to verify. Command, grep, or `path:line`.
4. Why it is a problem, and Impact. Checklist row, constitution section, Gherkin AC, who breaks, what fails in production.
5. Suggested fix. Numbered steps. A short improved-code snippet when that is clearer than prose. If several options exist, mark Recommended first.
6. Severity. Critical, Major, or Minor.

| Severity | When |
|----------|------|
| Critical | Must fix before merge: production bug, security, data corruption, breaking change, reliability failure. |
| Major | Architecture violation, scalability risk, missing critical tests, significant design flaw. |
| Minor | Naming, readability, optional refactor. Maps the old NWOB Suggestion bucket. |

Suggestions in the GitLab draft are optional extras that are not findings. Do not duplicate findings there.

### Two renderings

Write findings once. Render twice.

| Artifact | Audience | Shape |
|----------|----------|-------|
| `nwob-docs/observations/audit-report.md` | SDD and QA handoff | [audit-report-template.md](../../templates/lb/audit-report-template.md). Critical, Major, Minor sections. |
| Chat (human copies into GitLab) | Human reviewer on the MR | GitLab Output Format below. |

| GitLab | SDD report |
|--------|------------|
| `APPROVE` | Approved, ready for QA handoff. |
| `REQUEST CHANGES` | Changes requested. Author uses Builder `resolve-review-comments` or `trigger-ai-build`. |

### GitLab Output Format

Print this draft in chat after you write the audit report. Every issue comes from the same findings. Do not post to GitLab. The human copies the draft into GitLab if they choose.

```markdown
## What the Change Does
<2 to 4 sentences from the MR diff and spec>

## Critical
### <title>
- **File, Line:** path:line
- **Problem:**
- **Impact:**
- **Recommended Fix:**

## Major
…

## Minor
…

## Suggestions
<optional extras that are not findings>

## Tech Assessment
- **Risks:**
- **Scalability:**
- **Backward Compatibility:**
- **Test Coverage:**

## Verdict
**APPROVE** or **REQUEST CHANGES**
```

### Optional E2E before external QA

If UI stories are in MR scope and DevTools MCP is available:

- Run critical user journeys end to end.
- Check keyboard navigation and labels.
- Confirm a clean console and the expected API traffic.

If MCP is unavailable, record the skip reason. External QA may still run full E2E.

### Deprecation and migration

Builder verifies that migration code matches the SA deprecation ADR and the `story-tasks.md` migration tasks. Builder does not author deprecation policy. Policy gaps go to `architecture-governance`.

---

## Constitution QC

Mandatory on every increment and every MR:

| Gate | Requirement |
|------|-------------|
| Coverage | 100% meaningful coverage on the measured scope (coverage gates in constitution-core) |
| Integration | Testcontainers on Java where applicable. N/A on iOS and Android |
| API errors | RFC 7807 on HTTP APIs. N/A for client-only clones |
| Runtime | Stateless K8s on backend. No pod-local state. N/A for client-only clones |
| Static analysis | Checkstyle, PMD, SpotBugs on Java. N/A on iOS and Android. Java: also SonarQube / `sonarqube_check` per [implementation-quality-standards.md](implementation-quality-standards.md) |
| Contracts | OpenAPI where APIs are in scope; origin from `constitution-custom.mdc` |
| Stack and lifecycle | Effective constraints documented. No silent drift. |

"Approve if it improves health" does not override these gates.

---

## Limits

| Wrong | Right |
|-------|-------|
| Invoke reference `code-review-and-quality` SKILL.md | Use this file from the Lead Builder skills. |
| Waive coverage until MR | Reject the increment. Constitution requires 100% meaningful coverage per increment. |
| Skip MR audit because increments passed | Run `audit-and-approve-code` for integration and story coverage. |
| Paste the standards checklist into chat instead of `/audit` | Apply this file. Persist findings in the audit report. |
| Write a different GitLab review than the SDD report | Render both from one finding set. |
| Post the GitLab review from the agent | Print the draft. The human posts in GitLab. |
| Run the full SOLID and Git list on every `story-tasks.md` increment | Increment axes only. Full list is MR audit. |
| Profile architecture-tier performance in Builder audit | Route SLO and budget gaps to SA `production-operations`. |
| Author an ADR during audit for drift found | Route to `architecture-governance`. The audit records the finding. |
| Run E2E as the only quality gate | Unit, integration, and constitution gates stay mandatory. |
