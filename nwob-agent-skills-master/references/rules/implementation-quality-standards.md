# Implementation Quality Standards

Authoritative detail for code quality, defensive design, and testing standards. Mandated by `constitution-core.mdc`. Load during build increments (`review-implementation`) and final MR audit (`audit-and-approve-code`).

Stack-specific DI style, test naming (`tc001_...`), and coverage numeric targets live in `constitution-custom.mdc`. Audit checklist rows live in [builder-quality-patterns.md](builder-quality-patterns.md).

---

## Code quality principles

### SOLID

Classes and modules **must** respect:

| Principle | Rule |
|-----------|------|
| Single responsibility | One reason to change per class |
| Open/closed | Extend via polymorphism without editing closed code |
| Liskov substitution | Subtypes substitute parents without breaking callers |
| Interface segregation | Small client-specific interfaces |
| Dependency inversion | Depend on abstractions, not concretions at module boundaries |

### Clean code

- **Intention-revealing names.** Names say *what*, not *how*.
- **DRY.** Eliminate duplicate logic across components.
- **Dead code.** Remove commented-out blocks.
- **Guard clauses.** Early returns flatten nested conditionals.

### Size limits

| Limit | Rule |
|-------|------|
| Method length | **Should** stay under 20 lines (ideally under 10) |
| Parameters | **Must not** exceed 4. Introduce a parameter object when more are needed |

### Dependency injection

- Dependencies **must** be immutable and injected via constructors (or stack-equivalent in `constitution-custom.mdc`)
- Field-level injection is **forbidden** where constructor injection is supported
- Excessive constructor dependencies or test mocks (for example 10+) signal a design flaw and **must** be flagged in review

### File layout

Class files **should** order members: static constants → injected dependencies → public methods → private helpers.

### Engineering quality standards

- **Formatting.** No trailing whitespace. Java/backend uses 4-space indent. On mobile, the project formatter (detekt, SwiftFormat, or equivalent) wins when it differs.
- **Booleans.** Fields and properties use `is`, `has`, or `can` prefixes where applicable.

Java naming, packages, and comments: follow project conventions in `constitution-custom.mdc` and this document. Backend tests and JaCoCo/Sonar gates: see Coverage and Sonar sections below.

---

## Defensive design

| Area | Rule |
|------|------|
| Null and edge cases | Boundary logic **must** handle null inputs, empty collections, and parameter limits explicitly (for example `Optional` or language-equivalent at API boundaries) |
| Layer separation | Persistence or domain models **must not** be exposed directly through external interfaces; use presentation DTOs or API shells |
| Input validation | External inputs **must** be validated at the API or controller boundary before business logic executes |
| Exception handling | Caught exceptions **must** be logged with contextual parameters. Domain exceptions **must** map to standardized error structures via a global handler |
| Logging | **Must** use parameterized logging (not string concatenation). Logging sensitive data (secrets, credentials, PII) is **forbidden**. Log metadata or placeholders only. |

---

## Testing standards

| Area | Rule |
|------|------|
| Continuous execution | **Must** execute tests continuously during development; deferring testing to end-of-sprint is **forbidden** |
| Meaningful coverage | **Must** meet 100% meaningful coverage on the measured scope in `constitution-custom.mdc`. Tests **must** assert behavior and edge cases. Assertion-free, getter-only, and coverage-counter-only tests are **forbidden** |
| Structure | **Must** structure each test with explicit **Arrange**, **Act**, and **Assert** sections. Combining Act and Assert is acceptable when it simplifies flow (for example exception assertions) |
| State vs interaction | **Must** prefer state-based assertions over interaction-based verification of internal collaborators |
| Mocking boundaries | **Must** mock only dependencies outside team control (third-party APIs); **must not** over-mock internal domain methods |
| Assertion integrity | Every test **must** include meaningful assertions on outcomes. Assertion-free execution paths are **forbidden** |
| Integration fidelity | Integration tests **must** use orchestrated real dependencies (for example Testcontainers on Java, emulators or device farms on mobile) where production parity matters. Not in-memory substitutes unless `constitution-custom.mdc` approves them. |
| Test naming | Format and numeric identifiers (`tc001_...`) are stack-defined in `constitution-custom.mdc` when configured |
| Platform harnesses | JaCoCo, Testcontainers, Checkstyle, PMD, SpotBugs, and `mvn` are Java-only. iOS: XCTest and `xcodebuild`. Android: Gradle. Mark JVM-only gates N/A on mobile clones |
| Java Sonar | Java diffs **must** pass SonarQube Quality Gate / `sonarqube_check` as well as JaCoCo (thresholds and custom rules in `constitution-custom.mdc` when configured) |

### Test pyramid (mix hint)

70% unit / 20% integration / 10% E2E is a **mix hint** by test count. The numeric gate is **100% meaningful coverage**. Do not treat the pyramid as permission to drop below 100%.

---

## Review scope

| Phase | What applies |
|-------|--------------|
| Increment (`review-implementation`) | Correctness, security, performance, design fidelity, quality gates for the **changed slice** only |
| Final MR audit (`/audit`) | Full checklist including SOLID, clean code, defensive design, tests. See [builder-quality-patterns.md](builder-quality-patterns.md). |

Do **not** run the full SOLID / naming / Git checklist on every `story-tasks.md` increment.

---

## When to load this file

| Trigger | Consumer |
|---------|----------|
| Per-increment review | `review-implementation` |
| MR audit standards clusters | `audit-and-approve-code` |
| Implementation during build | `trigger-ai-build` (when writing or reviewing tests/code) |
