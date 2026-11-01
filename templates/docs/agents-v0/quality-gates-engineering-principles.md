# Quality gate engineering principles

> Toolchain wiring guidance. Referenced by `quality-and-testing.mdc` §Tooling —
> "wire before heavy coding." Thresholds: `docs/agents-v0/quality-gates.md`.

## Principle

Wire the quality toolchain **before** heavy coding, not after. A failing gate
early in the build is cheaper than a retrofit at merge time. Gates run in CI and
must fail the build on breach. Establish a **green baseline** (the profile Backend verify command; Pack `java`: `./mvnw -B clean
verify -Pci-security` from the backend root, or the frontend build/test script) before the first edit; Build starts
only from green.

## Toolchain (Java pipeline example)

| Tool | Purpose | Wired where |
|------|---------|-------------|
| JaCoCo | Coverage reporting (line + branch) | `./mvnw -B clean test jacoco:report` from the backend root; report at `target/site/jacoco/index.html` |
| SonarQube | Quality gate (coverage, complexity, duplication) | CI analysis step; `sonar.qualitygate` fail on breach |
| Checkstyle | Style and structural rules (config starter: `core/java/starters/maven/checkstyle.xml`) | `verify` phase |
| SpotBugs | Static bug analysis (correctness, injection) | `verify` phase |
| OWASP Dependency-Check | CVE scanning of dependencies | CI scan; no new high/critical CVEs. Lockfiles committed. Secret detection locally (the kit's staged scan on the onboard commit; the repo's own CI, if any). SBOM for a service that ships (`security-baseline.mdc` §9) |
| OpenAPI contract diff | No breaking drift vs the approved contract | `verify` phase (starter: `core/java/starters/maven/contract-conformance.xml`) |
| ArchUnit | Layer boundaries (domain ≠ web, DTO-only edge, constructor injection) | `test`/`verify` (starter: `core/java/starters/maven/archunit/LayerRulesTest.java`) |

Frontend and non-Java equivalents (ESLint, pytest-cov, Coverlet, go test -cover, lockfile audit) follow the
same principle and thresholds in `docs/agents-v0/quality-gates.md`.

## Wiring steps

1. Add the plugins/parent config first (for Java, starter: `core/java/starters/maven/quality-plugins.xml`,
   adapt to the repo's parent POM; for other stacks, wire per that pack's `scaffold-service`).
2. Configure the quality gate so a failing threshold **fails the build**, not
   just warns.
3. Confirm the profile Backend verify command runs coverage, style, static checks, the contract diff, and the layer check named in that pack's `pack.json`. The `java` example is `./mvnw -B clean verify -Pci-security` from the backend root.
4. Add the CVE scan to CI; document any accepted exceptions.
5. Record the repo's actual thresholds in `docs/agents-v0/quality-gates.md` if they differ
   from the defaults (the repository wins, per `ai-agent-conduct.mdc`).

## Limits

Thresholds are the source of truth in `docs/agents-v0/quality-gates.md`; do not restate
them here where they may drift.