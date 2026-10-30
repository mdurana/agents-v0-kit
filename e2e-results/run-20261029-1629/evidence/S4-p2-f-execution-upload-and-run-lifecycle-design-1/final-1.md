The **Design** phase (`/v0-design p2-f-execution-upload-and-run-lifecycle`) for Story **P2-F** (`Surfaces: backend`, `Material: no`, `Milestone: P2 — MVP / Core Features`) is complete and ready for your review and approval.

### Produced Artifacts

- **OpenAPI 3.0.3 Feature Contract Draft**: [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/openapi.yaml)
  - Self-contained contract for `listReportRuns` (`GET /api/v1/runs`), `initiateReportRun` (`POST /api/v1/runs`, `multipart/form-data` & `application/json`), `getReportRunById` (`GET /api/v1/runs/{id}`), and `cancelReportRun` (`POST /api/v1/runs/{id}/cancel`).
  - Enforces `additionalProperties: false` on all write request schemas (`ReportRunInitiateRequest`, `ReportRunCancelRequest`), `Idempotency-Key` headers on mutating POST operations, `ETag` concurrency headers, and RFC 7807 `ProblemDetail` (`application/problem+json`) error responses.
- **Design Specification**: [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/design.md)
  - Full traceability across `AC-1` through `AC-7` and all NFRs, sequence and bounded-context component diagrams, data model (`report_runs`, `run_artifacts`, S3 `sources` bucket, Redis idempotency & worker leases, `N/A: no schema migration required`), 4-operation authorization matrix with BOLA `{id}` lookup rules and VAPT `F4`/`F8`/`F9`/`F10` threat-model notes, failure modes covering `AC-5` (`Kind: edge`) and `AC-6` & `AC-7` (`Kind: negative`) plus slow/partial-failure S3 compensation, observability, and rollout.
- **Architecture Decision Record**: [0012-execution-upload-and-run-lifecycle.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/adr/0012-execution-upload-and-run-lifecycle.md)
  - `Status: Proposed`, `Pack: java`, comparing four alternatives for `< 50 MB` source CSV validation, `Asia/Manila` previous-month `YYYY-MM` period enforcement, S3 `sources` streaming, and distributed-lease asynchronous run execution with PostgreSQL optimistic-lock fallback (`L-003`, `L-004`, `L-005`).
- **Independent Design Review**: [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/review.md)
  - `0` open `Critical` findings (`Status: Resolved`).
- **Phase Result & State**: [p2-f-execution-upload-and-run-lifecycle.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/requirements/p2-f-execution-upload-and-run-lifecycle.phase-result.md) & [p2-f-execution-upload-and-run-lifecycle.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/requirements/p2-f-execution-upload-and-run-lifecycle.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

### Gate: Design Approval Required

Please confirm whether you **approve** the Design artifacts for `p2-f-execution-upload-and-run-lifecycle` so I can mark `ADR 0012` as `Accepted`, record the `design` approval in `p2-f-execution-upload-and-run-lifecycle.state.json`, and proceed to `/v0-build`.
The **Design** phase (`/v0-design p2-f-execution-upload-and-run-lifecycle`) for Story **P2-F** (`Surfaces: backend`, `Material: no`, `Milestone: P2 — MVP / Core Features`) is complete and ready for your review and approval.

### Produced Artifacts

- **OpenAPI 3.0.3 Feature Contract Draft**: [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/openapi.yaml)
  - Self-contained contract for `listReportRuns` (`GET /api/v1/runs`), `initiateReportRun` (`POST /api/v1/runs`, `multipart/form-data` & `application/json`), `getReportRunById` (`GET /api/v1/runs/{id}`), and `cancelReportRun` (`POST /api/v1/runs/{id}/cancel`).
  - Enforces `additionalProperties: false` on all write request schemas (`ReportRunInitiateRequest`, `ReportRunCancelRequest`), `Idempotency-Key` headers on mutating POST operations, `ETag` concurrency headers, and RFC 7807 `ProblemDetail` (`application/problem+json`) error responses.
- **Design Specification**: [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/design.md)
  - Full traceability across `AC-1` through `AC-7` and all NFRs, sequence and bounded-context component diagrams, data model (`report_runs`, `run_artifacts`, S3 `sources` bucket, Redis idempotency & worker leases, `N/A: no schema migration required`), 4-operation authorization matrix with BOLA `{id}` lookup rules and VAPT `F4`/`F8`/`F9`/`F10` threat-model notes, failure modes covering `AC-5` (`Kind: edge`) and `AC-6` & `AC-7` (`Kind: negative`) plus slow/partial-failure S3 compensation, observability, and rollout.
- **Architecture Decision Record**: [0012-execution-upload-and-run-lifecycle.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/adr/0012-execution-upload-and-run-lifecycle.md)
  - `Status: Proposed`, `Pack: java`, comparing four alternatives for `< 50 MB` source CSV validation, `Asia/Manila` previous-month `YYYY-MM` period enforcement, S3 `sources` streaming, and distributed-lease asynchronous run execution with PostgreSQL optimistic-lock fallback (`L-003`, `L-004`, `L-005`).
- **Independent Design Review**: [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/design/p2-f-execution-upload-and-run-lifecycle/review.md)
  - `0` open `Critical` findings (`Status: Resolved`).
- **Phase Result & State**: [p2-f-execution-upload-and-run-lifecycle.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/requirements/p2-f-execution-upload-and-run-lifecycle.phase-result.md) & [p2-f-execution-upload-and-run-lifecycle.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-f-execution-upload-and-run-lifecycle/docs/agents-v0/requirements/p2-f-execution-upload-and-run-lifecycle.state.json) (`activePhase: "design"`, `activeStatus: "awaiting_approval"`).

---

### Gate: Design Approval Required

Please confirm whether you **approve** the Design artifacts for `p2-f-execution-upload-and-run-lifecycle` so I can mark `ADR 0012` as `Accepted`, record the `design` approval in `p2-f-execution-upload-and-run-lifecycle.state.json`, and proceed to `/v0-build`.
