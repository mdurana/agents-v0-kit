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

JaCoCo, SonarQube, Checkstyle, SpotBugs, OWASP Dependency-Check, plus the OpenAPI contract diff (`maven/contract-conformance.xml`) and ArchUnit layer rules (`maven/archunit/LayerRulesTest.java`) where wired.

## CVE policy

No new high/critical CVEs without a documented exception. Lockfiles are committed. Secret detection runs on the merge request. A service that ships produces an SBOM (CycloneDX/SPDX). A license policy is documented when compliance requires it (`security-baseline.mdc` §9).
