# Quality gates

> CI quality thresholds. (`quality-and-testing.mdc`)

## Coverage

| Area | Minimum | Notes |
|------|---------|-------|
| Changed lines | 80% | Checked during Verify (`quality-gate` skill) |
| Backend lines | 80% | 90% where gates require |
| Backend branches | the pack coverage report (Pack java: JaCoCo / Sonar) | |
| Frontend | 70% | raise if CI gate exists |

During `/v0-verify`, `test-engineer` (`quality-gate` skill) and the stack's native coverage tool check changed-line coverage (default 80%) and whole-module line coverage (Backend 80%, Frontend 70%, or the Whole-module lines row in `docs/agents-v0/quality-gates.md`). Pack `java` wires a fixed JaCoCo bundle minimum of 0.80 in `core/java/starters/maven/quality-plugins.xml`. A `coverage_ratchet` row in `project-profile.md` is a dated waiver record with a valid approver and unexpired removal date. When the diff touches a migration or SQL file, tests must verify against the target database engine rather than relying only on H2/in-memory substitutes. An expand/contract step with no down script stays legal when the rollback note is recorded. An optional `mutation_ratchet` row in `project-profile.md` checks a mutation report.

## Complexity and size (Java)

| Metric | Limit |
|--------|-------|
| Cognitive complexity | ≤ 15 / method |
| Method length | target ≤ 20, max ≤ 30 lines |
| Class size | < ~300 lines |
| Duplication | < ~3% (Sonar) |

## Tooling

The reporting toolchain is determined by the bound pack's `pack.json` (Pack `java`: JaCoCo, Checkstyle, SpotBugs, OWASP Dependency-Check, ArchUnit; Pack `dotnet`: Coverlet, xUnit; Pack `node`: Jest; Pack `python`: pytest-cov; Pack `go`: go test -cover). Thresholds and principles apply across all packs. Java starter wiring includes OpenAPI contract diff (`core/java/starters/maven/contract-conformance.xml`) and ArchUnit layer rules (`core/java/starters/maven/archunit/LayerRulesTest.java`).

## CVE policy

No new high/critical CVEs without a documented exception. Lockfiles are committed. Secret detection runs locally (the kit's staged scan on the onboard commit); the merge request is scanned only by the repo's own CI, if it has one. A service that ships produces an SBOM (CycloneDX/SPDX). A license policy is documented when compliance requires it (`security-baseline.mdc` §9).
