# Quality gate engineering principles

> Toolchain wiring guidance. Referenced by `quality-and-testing.mdc` §Tooling —
> "wire before heavy coding." Thresholds: `docs/agents-v0/quality-gates.md`. One-page
> summary: `docs/quality-quick-reference.md`.

## Principle

Wire the quality toolchain **before** heavy coding, not after. A failing gate
early in the build is cheaper than a retrofit at merge time. Gates run in CI and
must fail the build on breach. Establish a **green baseline** (`./mvnw -B clean
verify` from the backend root, or the frontend build/test script) before the first edit; Build starts
only from green.

## Toolchain (Java pipeline)

| Tool | Purpose | Wired where |
|------|---------|-------------|
| JaCoCo | Coverage reporting (line + branch) | `./mvnw -B clean test jacoco:report` from the backend root; report at `target/site/jacoco/index.html` |
| SonarQube | Quality gate (coverage, complexity, duplication) | CI analysis step; `sonar.qualitygate` fail on breach |
| Checkstyle | Style and structural rules (config starter: `maven/checkstyle.xml`) | `verify` phase |
| SpotBugs | Static bug analysis (correctness, injection) | `verify` phase |
| OWASP Dependency-Check | CVE scanning of dependencies | CI scan; no new high/critical CVEs (`security-baseline.mdc` §9) |
| OpenAPI contract diff | No breaking drift vs the approved contract | `verify` phase (starter: `maven/contract-conformance.xml`) |
| ArchUnit | Layer boundaries (domain ≠ web, DTO-only edge, constructor injection) | `test`/`verify` (starter: `maven/archunit/LayerRulesTest.java`) |

Frontend equivalents (ESLint, coverage provider, lockfile audit) follow the
same principle and thresholds in `docs/agents-v0/quality-gates.md`.

## Wiring steps

1. Add the plugins/parent config first (starter: `maven/quality-plugins.xml`,
   adapt to the repo's parent POM).
2. Configure the quality gate so a failing threshold **fails the build**, not
   just warns.
3. Confirm `./mvnw -B clean verify` from the backend root runs coverage, style, static checks, the
   contract diff, and layer rules.
4. Add the CVE scan to CI; document any accepted exceptions.
5. Record the repo's actual thresholds in `docs/agents-v0/quality-gates.md` if they differ
   from the defaults (the repository wins, per `ai-agent-conduct.mdc`).

## Limits

Thresholds are the source of truth in `docs/agents-v0/quality-gates.md`; do not restate
them here where they may drift.