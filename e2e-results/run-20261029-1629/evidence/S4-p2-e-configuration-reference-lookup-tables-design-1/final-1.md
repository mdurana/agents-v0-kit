The **Design** phase (`/v0-design`) for Story **P2-E** (`p2-e-configuration-reference-lookup-tables` — *Configuration Management: Reference Lookup Tables, Versions & CSV/Grid Editing*) is complete and ready for your review and approval.

### Design Artifacts Produced

1. **Feature OpenAPI 3.0.3 Contract Draft** — [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/openapi.yaml)
   - Self-contained contract defining all 6 `/api/v1/reference-tables/**` operations (`listReferenceTables`, `createReferenceTable`, `getReferenceTableById`, `listReferenceTableRows`, `updateReferenceTableRows`, `importReferenceTableCsv`), offset pagination (`page`, `limit`, `PaginationMetadata`), write-safety headers (`Idempotency-Key`, `If-Match` / `ETag`), `additionalProperties: false` on all write schemas and nested row items (`ReferenceTableCreateRequest`, `ReferenceTableRowsUpdateRequest`, `ReferenceTableCsvImportRequest`), and the RFC 7807 `ProblemDetail` (`application/problem+json`) envelope.
2. **Feature Architecture & Design Specification** — [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/design.md)
   - **Traceability**: Maps `AC-1` through `AC-7` and all NFRs (`p95 <= 400 ms` read, `p95 <= 800 ms` inline-grid staging, `p95 <= 2000 ms` CSV import up to `5000` rows / `10 MB`, 13-month retention, and `Encode.forJava()` auditability) to operations, services, cross-context ports (`L-003`), and `ADR 0011`.
   - **Data Model**: Uses existing `V3__configuration_and_seeded_definitions.sql` (`reference_tables`, `reference_table_versions`, `reference_table_rows`, `trg_reference_table_versions_immutable`, `trg_reference_table_rows_immutable`) and `V4__execution_and_governance_schema.sql` (`governance_tickets`) tables plus 24-hour Redis `Idempotency-Key` replay keys (`N/A: 
<truncated 598 bytes>
g.
3. **Architecture Decision Record** — [0011-configuration-reference-lookup-tables.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/adr/0011-configuration-reference-lookup-tables.md) (`Status: Proposed`, `Pack: java`)
   - Compares four alternatives for staged reference lookup table versions, inline-grid editing, hardened UTF-8 CSV multipart import, recipe `LOOKUP()` resolution, and value-typed `ConfigurationReadPort` / `ConfigurationCutoverPort` (`L-003`, `L-004`, `L-005`).
4. **Sequence Diagram** — [configuration-governance.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/diagrams/sequences/configuration-governance.md)
   - Added Section 3 illustrating reference table creation, inline-grid staging, validated CSV import, atomic cutover, and recipe `LOOKUP()` evaluation.
5. **Design Review Report** — [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/review.md)
   - `0` open `Critical` findings (`Status: Resolved`).
6. **Phase Result & State** — [p2-e-configuration-reference-lookup-tables.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.phase-result.md) and [p2-e-configuration-reference-lookup-tables.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

### Gate: Design Approval Required

Please review the design artifacts above and reply to **approve** the Design phase (or share any requested revisions) before proceeding to `/v0-build p2-e-configuration-reference-lookup-tables`.
The **Design** phase (`/v0-design`) for Story **P2-E** (`p2-e-configuration-reference-lookup-tables` — *Configuration Management: Reference Lookup Tables, Versions & CSV/Grid Editing*) is complete and ready for your review and approval.

### Design Artifacts Produced

1. **Feature OpenAPI 3.0.3 Contract Draft** — [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/openapi.yaml)
   - Self-contained contract defining all 6 `/api/v1/reference-tables/**` operations (`listReferenceTables`, `createReferenceTable`, `getReferenceTableById`, `listReferenceTableRows`, `updateReferenceTableRows`, `importReferenceTableCsv`), offset pagination (`page`, `limit`, `PaginationMetadata`), write-safety headers (`Idempotency-Key`, `If-Match` / `ETag`), `additionalProperties: false` on all write schemas and nested row items (`ReferenceTableCreateRequest`, `ReferenceTableRowsUpdateRequest`, `ReferenceTableCsvImportRequest`), and the RFC 7807 `ProblemDetail` (`application/problem+json`) envelope.
2. **Feature Architecture & Design Specification** — [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/design.md)
   - **Traceability**: Maps `AC-1` through `AC-7` and all NFRs (`p95 <= 400 ms` read, `p95 <= 800 ms` inline-grid staging, `p95 <= 2000 ms` CSV import up to `5000` rows / `10 MB`, 13-month retention, and `Encode.forJava()` auditability) to operations, services, cross-context ports (`L-003`), and `ADR 0011`.
   - **Data Model**: Uses existing `V3__configuration_and_seeded_definitions.sql` (`reference_tables`, `reference_table_versions`, `reference_table_rows`, `trg_reference_table_versions_immutable`, `trg_reference_table_rows_immutable`) and `V4__execution_and_governance_schema.sql` (`governance_tickets`) tables plus 24-hour Redis `Idempotency-Key` replay keys (`N/A: 
<truncated 598 bytes>
g.
3. **Architecture Decision Record** — [0011-configuration-reference-lookup-tables.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/adr/0011-configuration-reference-lookup-tables.md) (`Status: Proposed`, `Pack: java`)
   - Compares four alternatives for staged reference lookup table versions, inline-grid editing, hardened UTF-8 CSV multipart import, recipe `LOOKUP()` resolution, and value-typed `ConfigurationReadPort` / `ConfigurationCutoverPort` (`L-003`, `L-004`, `L-005`).
4. **Sequence Diagram** — [configuration-governance.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/diagrams/sequences/configuration-governance.md)
   - Added Section 3 illustrating reference table creation, inline-grid staging, validated CSV import, atomic cutover, and recipe `LOOKUP()` evaluation.
5. **Design Review Report** — [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/design/p2-e-configuration-reference-lookup-tables/review.md)
   - `0` open `Critical` findings (`Status: Resolved`).
6. **Phase Result & State** — [p2-e-configuration-reference-lookup-tables.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.phase-result.md) and [p2-e-configuration-reference-lookup-tables.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-e-configuration-reference-lookup-tables/docs/agents-v0/requirements/p2-e-configuration-reference-lookup-tables.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

### Gate: Design Approval Required

Please review the design artifacts above and reply to **approve** the Design phase (or share any requested revisions) before proceeding to `/v0-build p2-e-configuration-reference-lookup-tables`.
