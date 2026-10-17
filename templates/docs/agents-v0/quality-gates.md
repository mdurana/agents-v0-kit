# Quality gates

> CI quality thresholds. (`quality-and-testing.mdc`)

## Coverage

| Area | Minimum | CI / stretch |
|------|---------|--------------|
| Backend lines | 80% | 90% where gates require |
| Backend branches | the pack coverage report (Pack java: JaCoCo / Sonar) | |
| Frontend | 70% | raise if CI gate exists |

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
