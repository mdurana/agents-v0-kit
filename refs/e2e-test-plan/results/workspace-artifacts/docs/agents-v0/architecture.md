# Program Architecture: Finance Back Office Portal

## C4 Context

```mermaid
flowchart LR
  prep["Finance Preparer (Person)"]
  approver["Finance Approver (Person)"]
  admin["Platform Administrator (Person)"]
  portal["Finance Back Office Portal (System)"]
  idp["Enterprise Identity Provider (External System)"]
  sap["Downstream SAP Archive Consumer (External System)"]
  smtp["Enterprise Mail Relay (External System)"]

  prep -->|"HTTPS / sync: upload CSV, trigger run, submit ticket"| portal
  approver -->|"HTTPS / sync: review preview, approve/reject ticket"| portal
  admin -->|"HTTPS / sync: manage lookups, schedules, RBAC"| portal
  portal -->|"OIDC HTTPS / sync: authenticate operator"| idp
  portal -->|"Object Archive / async: write approved SAP CSV"| sap
  portal -->|"SMTP / async: send ticket & job notifications"| smtp
```

## C4 Container

```mermaid
flowchart TB
  spa["Web Console SPA (Container)"]
  api["Portal BFF & Core Service (Container)"]
  worker["Transformation Job Worker (Container)"]
  db["Operational Relational Store (Container)"]
  cache["Session & Lock Store (Container)"]
  store["Artifact Object Store (Container)"]

  spa -->|"HTTPS JSON / sync"| api
  api -->|"SQL TCP / sync"| db
  api -->|"TCP / sync: session & execution lock"| cache
  api -->|"In-process queue / async: enqueue job"| worker
  worker -->|"SQL TCP / sync: read recipe & lookups, update run"| db
  worker -->|"HTTPS / sync: read source CSV, write draft & exception CSV"| store
```

## Data flow

```mermaid
flowchart TB
  spa["Web Console SPA"]
  api["Portal BFF & Core Service"]
  worker["Transformation Job Worker"]
  db["Operational Relational Store"]
  cache["Session & Lock Store"]
  store["Artifact Object Store"]

  spa -->|"HTTPS / Multipart CSV & REST JSON"| api
  api -->|"JDBC / Domain Entities & Audit Events"| db
  api -->|"RESP / Session Cookie & Execution Lock"| cache
  api -->|"Internal Event / JobRunCommand"| worker
  worker -->|"JDBC / Lookup Grid & Recipe AST"| db
  worker -->|"Stream / Source CSV, Draft SAP CSV, Exceptions CSV"| store
```

## Data models

### Conceptual

```mermaid
erDiagram
  LOOKUP_TABLE ||--o{ LOOKUP_VERSION : has
  REPORT_DEFINITION ||--o{ TRANSFORMATION_RECIPE : uses
  REPORT_DEFINITION ||--o{ TRANSFORMATION_RUN : executes
  TRANSFORMATION_RUN ||--o{ GOVERNANCE_TICKET : endorsed_by
  OPERATOR ||--o{ AUDIT_LOG_ENTRY : generates
```

### Logical

```mermaid
erDiagram
  LOOKUP_TABLE {
    uuid id PK
    string code
    string name
    string description
    string status
  }
  LOOKUP_VERSION {
    uuid id PK
    uuid lookup_table_id FK
    int version_number
    jsonb columns_schema
    jsonb rows_data
    string created_by
  }
  TRANSFORMATION_RECIPE {
    uuid id PK
    string report_type
    int version_number
    string status
    jsonb input_schema
    jsonb mapping_rules
    string created_by
  }
  TRANSFORMATION_RUN {
    uuid id PK
    uuid recipe_id FK
    string report_type
    string report_period
    string status
    int input_row_count
    int output_row_count
    int exception_row_count
    string draft_csv_ref
    string exception_csv_ref
    string initiated_by
  }
```

### Physical

```mermaid
erDiagram
  lookup_tables {
    uuid id PK "Flyway V2, 13m retention, soft-delete via status"
    varchar code "UNIQUE NOT NULL"
    varchar name "NOT NULL"
    varchar status "NOT NULL DEFAULT ACTIVE"
    timestamptz created_at "NOT NULL"
  }
  lookup_versions {
    uuid id PK "Flyway V2, immutable"
    uuid lookup_table_id FK "NOT NULL"
    int version_number "NOT NULL"
    jsonb columns_schema "NOT NULL"
    jsonb rows_data "NOT NULL"
    timestamptz created_at "NOT NULL"
  }
  transformation_recipes {
    uuid id PK "Flyway V3, immutable versions"
    varchar code "UNIQUE NOT NULL"
    varchar report_type "NOT NULL"
    int version_number "NOT NULL"
    varchar status "NOT NULL"
    jsonb schema_definition "NOT NULL"
    timestamptz created_at "NOT NULL"
  }
  transformation_runs {
    uuid id PK "Flyway V4, 13m retention"
    varchar report_type "NOT NULL"
    varchar report_period "NOT NULL"
    varchar status "NOT NULL"
    text output_csv "NULL"
    timestamptz created_at "NOT NULL"
  }
```

## State machine

```mermaid
stateDiagram-v2
  [*] --> JOB_QUEUED: Trigger Run (HTTP 202)
  JOB_QUEUED --> RUNNING: Worker Dequeues
  JOB_QUEUED --> CANCELLED: Preparer/Admin Cancels
  RUNNING --> SUCCESS: All Rows Transformed
  RUNNING --> FAILED: Validation / Timeout / Rule Error
  RUNNING --> CANCELLED: Operator Cancels
  SUCCESS --> [*]
  FAILED --> [*]
  CANCELLED --> [*]
```

## Failure domains and degradation

| Dependency | What degrades | What halts | Validation |
|------------|---------------|------------|------------|
| Session / Lock Store | Active user sessions fail closed (HTTP 401) | New authenticated API calls and ticket cutovers | Integration test simulating store unavailability |
| Relational Database | All read/write endpoints return RFC 7807 `503` | Run submissions, lookup edits, ticket approvals | HikariCP readiness health check & Testcontainers |
| Artifact Object Store | CSV preview and download endpoints return `503` | Transformation worker file archival | Storage health indicator |

## MVP and future state

- **MVP State**: Single modular monolith (`app/backend` + `app/frontend`) handling `UPLOAD_ONLY` CSV ingestion, versioned lookup tables, transformation recipes, and the 5 seeded Funding Cost Summary SAP commission CSV exports.
- **Future State Trigger**: Extract `Transformation Job Worker` into an independent worker deployment if concurrent batch files exceed 50 MB or scheduled S3 polling (`S3_POLL`) introduces sustained CPU contention on the BFF tier.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| architecture | docs/agents-v0/architecture.md, docs/agents-v0/network.md, docs/agents-v0/adr/0001-modular-monolith-architecture.md, docs/agents-v0/design/system/context-map.md, docs/agents-v0/design/system/nfr-slo.md, docs/agents-v0/design/system/threat-model.md, docs/agents-v0/design/system/ops-readiness.md, docs/agents-v0/design/system/arc-record.md, docs/agents-v0/design/system/architecture-review.md | mdurana | Approved | 2026-10-28 |
