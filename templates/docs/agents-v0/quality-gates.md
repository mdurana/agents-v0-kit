# Quality gates

> CI quality thresholds. (`quality-and-testing.mdc`)

## Coverage

| Area | Minimum | CI / stretch |
|------|---------|--------------|
| Backend lines | 80% | 90% where gates require |
| Backend branches | the pack coverage report (Pack java: JaCoCo / Sonar) | |
| Frontend | 70% | raise if CI gate exists |

On a merge request, changed-line coverage under 80% fails for every pack when `DIFF_BASE` is set (`.agents-v0/ci/check-gate-metrics.sh`). Backend 80% and frontend 70% are the report check. Whole-module line coverage fails in CI only when the pack wires it (Pack `java`: JaCoCo minimum 0.80) or when `MIN_LINE_PCT` or an approved `coverage_ratchet` row is set. When the diff touches a migration or SQL file and `DIFF_BASE` is set, the same script requires a test against the database named in the profile. H2 does not satisfy that row. An expand/contract step with no down script stays legal when the rollback note is recorded. An optional `mutation_ratchet` row in `project-profile.md` checks a mutation report. It is not a default gate.

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

No new high/critical CVEs without a documented exception. Lockfiles are committed. Secret detection runs on the merge request. A service that ships produces an SBOM (CycloneDX/SPDX). A license policy is documented when compliance requires it (`security-baseline.mdc` §9).
