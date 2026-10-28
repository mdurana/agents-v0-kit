# Bounded Context & Service Map

| Context | Responsibility | Integrations | Service Root | Contract | Sequence Diagram | Component Plan | Status |
|---------|----------------|--------------|--------------|----------|------------------|----------------|--------|
| Reference & Lookup Management | Versioned lookup tables and CSV/grid imports | Used by Transformation Engine | `app/backend` | `openapi/api-v1.yaml` | `docs/agents-v0/diagrams/sequences/funding-cost-run.md` | N/A: single modular monolith repo | active |
| Transformation Recipe & Run Engine | Declarative JSON recipes, Funding Cost Summary execution, SAP CSV export | Reads Lookups; emits Audit & Posting Tickets | `app/backend` | `openapi/api-v1.yaml` | `docs/agents-v0/diagrams/sequences/funding-cost-run.md` | N/A: single modular monolith repo | active |
| Governance, Ticketing & IAM | Maker-checker queues, RBAC, SoD enforcement, 13-month audit trail | Guards all mutating operations | `app/backend` | `openapi/api-v1.yaml` | `docs/agents-v0/diagrams/sequences/funding-cost-run.md` | N/A: single modular monolith repo | active |
