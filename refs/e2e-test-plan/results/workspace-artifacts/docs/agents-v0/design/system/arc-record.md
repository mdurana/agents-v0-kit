# Architecture Review Committee (ARC) Record

- **Problem Source**: `user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md` and `docs/agents-v0/roadmap/finance-back-office-portal.md`
- **Pattern ADR**: `docs/agents-v0/adr/0001-modular-monolith-architecture.md` (`Pack: java`)
- **Recommendation**: Approve Option A — Modular Monolith with Asynchronous Recipe Worker (`java` backend + `react` SPA + PostgreSQL 17).

## Fitness functions

Runtime SLO targets are defined in `docs/agents-v0/design/system/nfr-slo.md`.

| Principle | Check | Threshold | On failure |
|-----------|-------|-----------|------------|
| Layer isolation & dependency hygiene | `.agents-v0/scripts/run-backend-verify.sh` (`./mvnw -B clean verify -Pci-security`) | 0 violations, coverage >= 80% | Block build / verify gate |
| Vulnerability & dependency gate | OWASP Dependency-Check & SpotBugs (`-Pci-security`) | 0 critical/high CVEs | Block build / verify gate |
| Contract & migration safety | `.agents-v0/scripts/check-migration-safety.sh` | 0 destructive DDL without ADR | Block verify gate |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md | mdurana | Approved | 2026-10-28 |
