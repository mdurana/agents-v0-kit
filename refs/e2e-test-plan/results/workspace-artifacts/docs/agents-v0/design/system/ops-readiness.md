# Operational Readiness

- **Build-and-Run Ownership**: Finance Platform Engineering (`finance-platform-oncall`).
- **Error Budget Policy**: If 28-day API availability drops below 99.9% or a maker-checker SoD bypass occurs, freeze non-P0 feature releases until remediation and regression tests are merged.
- **Database Maintenance & Operation**: Flyway-managed forward-only schema migrations (`app/backend/src/main/resources/db/migration`), automated daily backups, and 13-month online partition retention for audit tables.
- **P5 Release Readiness Checklist**: Deferred to Milestone P5 (`p5-release-readiness.md`).
