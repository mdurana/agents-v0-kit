# Milestone: P2 — MVP Core Features

Roadmap: docs/agents-v0/roadmap/finance-back-office-portal.md
Architecture: docs/agents-v0/architecture.md

## Goal

Deliver the MVP Funding Cost Summary transformation pipeline, SAP CSV export, and maker-checker posting endorsement.

## Stories

| Story ID | User story | Feature artifact | Status | Dependency | Surface | Size |
|----------|-----------|------------------|--------|------------|---------|------|
| P2-A | As a finance preparer, I want to trigger a Funding Cost Summary transformation run and download the generated SAP commission CSV, so that monthly settlement outputs are validated and auditable. | docs/agents-v0/requirements/p2-a-funding-cost-sap-export.md | planned | P1-A, P1-B | backend | 4 |
| P2-B | As a finance approver, I want to endorse and approve SAP_REPORT_POSTING tickets with Segregation of Duties enforcement, so that no single operator can self-approve ledger postings. | docs/agents-v0/requirements/p2-b-sap-posting-ticket-governance.md | planned | P2-A | backend | 4 |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| plan | docs/agents-v0/milestones/plan.md, docs/agents-v0/milestones/p2-mvp-core-features.md, docs/agents-v0/design/system/context-map.md, docs/agents-v0/roadmap/finance-back-office-portal.md | mdurana | Approved | 2026-10-28 |
