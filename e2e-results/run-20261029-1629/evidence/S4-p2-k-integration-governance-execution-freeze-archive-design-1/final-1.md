The **Design** phase (`/v0-design`) for story **P2-K (`p2-k-integration-governance-execution-freeze-archive`)** is complete and ready for your review at the **Design Gate**.

### Artifacts Produced
- **OpenAPI 3.0.3 Feature Contract Draft**: [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/openapi.yaml)
  - Self-contained OpenAPI `3.0.3` specification covering all 7 integration operations (`approveGovernanceTicket`, `rejectGovernanceTicket`, `cancelGovernanceTicket`, `downloadTicketLinkedRunArtifact`, `endorseReportRun`, `approveSapPostingForRun`, `downloadRunArtifact`).
  - Enforces `additionalProperties: false` on all 4 write request schemas (`TicketDecisionRequest`, `TicketRejectRequest`, `ReportRunEndorseRequest`, `SapPostingApproveRequest`), optimistic concurrency (`If-Match` / `ETag` + `version`), and RFC 7807 `ProblemDetails` responses (`EXECUTION_FREEZE_ACTIVE`, `SOD_MAKER_CHECKER_VIOLATION`, `VIEW_AS_MUTATION_FORBIDDEN`, `PRECONDITION_FAILED`, `CONCURRENCY_CONFLICT`, `VALIDATION_ERROR`, `ARTIFACT_STORAGE_ERROR`).
- **Architecture Decision Record**: [0016-integration-governance-execution-freeze-archive.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/adr/0016-integration-governance-execution-freeze-archive.md) (`Status: Proposed`, `Pack: java`)
  - Compares 4 architectural options and selects **Option A: Synchronous In-Transaction Cross-Context Port Orchestration** across [`ExecutionFreezePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/src/main/java/com/gxi/portal/execution/ExecutionFreezePort.java), [`ExecutionArchivePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/src/main/java/com/gxi/portal/execution/ExecutionArchivePort.jav
<truncated 1030 bytes>
iveService.java)), with S3 compensating `deleteObject` on mid-transaction failure (`AC-3`, `AC-5`) and `@Transactional(noRollbackFor = ContractProblemException.class)` for durable refusal auditing (`L-004`/`L-005`).
- **Feature Design Document**: [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/design.md)
  - Full `AC-1`..`AC-7` and NFR traceability table, 3 Mermaid diagrams (component/port boundary diagram + 2 sequence diagrams), data model and index/trigger inventory, authorization matrix for all 7 `operationId`s, VAPT `F4`/`F8`/`F9`/`F10` controls, `Events: N/A: no event contract`, failure modes (`AC-5`, `AC-6`, `AC-7`), observability, and rollout plan.
- **Design Review Report**: [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/review.md) (`agent: design-reviewer`, verdict **PASS**, `0` open `Critical` findings)
- **Phase Result & State**:
  - [p2-k-integration-governance-execution-freeze-archive.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.phase-result.md)
  - [p2-k-integration-governance-execution-freeze-archive.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.state.json) (`lastApproved: "intake"`, `activePhase: "design"`, `activeStatus: "awaiting_approval"`)

---

### Gate Request
Please review the design artifacts above and reply with your approval (e.g., **"Approve design"**) or any requested revisions before we proceed to `/v0-build p2-k-integration-governance-execution-freeze-archive`.
The **Design** phase (`/v0-design`) for story **P2-K (`p2-k-integration-governance-execution-freeze-archive`)** is complete and ready for your review at the **Design Gate**.

### Artifacts Produced
- **OpenAPI 3.0.3 Feature Contract Draft**: [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/openapi.yaml)
  - Self-contained OpenAPI `3.0.3` specification covering all 7 integration operations (`approveGovernanceTicket`, `rejectGovernanceTicket`, `cancelGovernanceTicket`, `downloadTicketLinkedRunArtifact`, `endorseReportRun`, `approveSapPostingForRun`, `downloadRunArtifact`).
  - Enforces `additionalProperties: false` on all 4 write request schemas (`TicketDecisionRequest`, `TicketRejectRequest`, `ReportRunEndorseRequest`, `SapPostingApproveRequest`), optimistic concurrency (`If-Match` / `ETag` + `version`), and RFC 7807 `ProblemDetails` responses (`EXECUTION_FREEZE_ACTIVE`, `SOD_MAKER_CHECKER_VIOLATION`, `VIEW_AS_MUTATION_FORBIDDEN`, `PRECONDITION_FAILED`, `CONCURRENCY_CONFLICT`, `VALIDATION_ERROR`, `ARTIFACT_STORAGE_ERROR`).
- **Architecture Decision Record**: [0016-integration-governance-execution-freeze-archive.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/adr/0016-integration-governance-execution-freeze-archive.md) (`Status: Proposed`, `Pack: java`)
  - Compares 4 architectural options and selects **Option A: Synchronous In-Transaction Cross-Context Port Orchestration** across [`ExecutionFreezePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/src/main/java/com/gxi/portal/execution/ExecutionFreezePort.java), [`ExecutionArchivePort`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/src/main/java/com/gxi/portal/execution/ExecutionArchivePort.jav
<truncated 1030 bytes>
iveService.java)), with S3 compensating `deleteObject` on mid-transaction failure (`AC-3`, `AC-5`) and `@Transactional(noRollbackFor = ContractProblemException.class)` for durable refusal auditing (`L-004`/`L-005`).
- **Feature Design Document**: [design.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/design.md)
  - Full `AC-1`..`AC-7` and NFR traceability table, 3 Mermaid diagrams (component/port boundary diagram + 2 sequence diagrams), data model and index/trigger inventory, authorization matrix for all 7 `operationId`s, VAPT `F4`/`F8`/`F9`/`F10` controls, `Events: N/A: no event contract`, failure modes (`AC-5`, `AC-6`, `AC-7`), observability, and rollout plan.
- **Design Review Report**: [review.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/design/p2-k-integration-governance-execution-freeze-archive/review.md) (`agent: design-reviewer`, verdict **PASS**, `0` open `Critical` findings)
- **Phase Result & State**:
  - [p2-k-integration-governance-execution-freeze-archive.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.phase-result.md)
  - [p2-k-integration-governance-execution-freeze-archive.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-k-integration-governance-execution-freeze-archive/docs/agents-v0/requirements/p2-k-integration-governance-execution-freeze-archive.state.json) (`lastApproved: "intake"`, `activePhase: "design"`, `activeStatus: "awaiting_approval"`)

---

### Gate Request
Please review the design artifacts above and reply with your approval (e.g., **"Approve design"**) or any requested revisions before we proceed to `/v0-build p2-k-integration-governance-execution-freeze-archive`.
