I have started the Red-phase test verification run (`./mvnw -B clean verify -P!ci-security`) in the background and am waiting for it to finish.
I have started the Green-phase fast verify run (`./mvnw -B clean verify -P!ci-security`) in the background and am waiting for it to finish.
I have started the full native verification run (`./mvnw -B clean verify -Pci-security`) in the background and am waiting for it to finish.
Completed the **Build** phase (`/v0-build`) for Story **`P2-N` (`p2-n-integration-iam-cross-context-authorization-guard` — Integration: IAM Cross-Context Authorization Guard)** on branch `feature/p2-n-integration-iam-cross-context-authorization-guard`.

### Summary of Changes

1. **Contract & OpenAPI Synchronization**
   - Merged the 14 cross-context operation summaries from [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/design/p2-n-integration-iam-cross-context-authorization-guard/openapi.yaml) into [openapi/api-v1.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/openapi/api-v1.yaml) and [app/backend/src/main/resources/openapi/api-v1.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/resources/openapi/api-v1.yaml).
2. **Cross-Context Route & Instance Authorization (`AC-1`..`AC-6`)**
   - [`RbacManagementService`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/java/com/example/app/iam/service/RbacManagementService.java#L89-L243):
     - Evaluated `support.matchRoutePermission(method, requestUri)` in `evaluateRoute` before the self-service cancel check (`POST /api/v1/tickets/{id}/cancel`) so soft-deleted `governance:tickets:cancel` revokes route access immediately with `403 AUTH_FORBIDDEN` (`AC-4`).
     - Added `execution:runs:manage` (`EXECUTION_RUNS_MANAGE`) alias resolution (`AC-3`) and removed `governance:tickets:write` from the `governance:tickets:manage` alias so `View-As` roles and preparers cannot access `GET /api/v1/tickets?queueView=MANAGE` (`AC-2`, `AC-5`).
   - [`ReportRunOrchestratorService`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/java/com/example/app/exe
<truncated 2207 bytes>
ity` -> **`BUILD SUCCESS`** (`138` tests run, `0` failures, `0` errors, `0` skipped; JaCoCo coverage check passed; Checkstyle `0` violations; SpotBugs `0` bugs; OWASP Dependency-Check `0` CVEs `>= 7.0`; ArchUnit [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java) `3/3` passed).
- **Build Plan**: [plan.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/plan.md) (`AC-1`..`AC-6` all `done`)
- **Build Report**: [build-report.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/build-report.md)
- **Build Output**: [build-output.txt](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/build-output.txt)
- **Phase Result & State**: [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md), [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json) (`activePhase: "build"`, `phaseStatus: "awaiting_approval"`)

---

### Approval Gate

Please review the Build artifacts and confirm whether you approve the **Build** phase for `p2-n-integration-iam-cross-context-authorization-guard` to proceed to `/v0-verify`.
Completed the **Build** phase (`/v0-build`) for Story **`P2-N` (`p2-n-integration-iam-cross-context-authorization-guard` — Integration: IAM Cross-Context Authorization Guard)** on branch `feature/p2-n-integration-iam-cross-context-authorization-guard`.

### Summary of Changes

1. **Contract & OpenAPI Synchronization**
   - Merged the 14 cross-context operation summaries from [openapi.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/design/p2-n-integration-iam-cross-context-authorization-guard/openapi.yaml) into [openapi/api-v1.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/openapi/api-v1.yaml) and [app/backend/src/main/resources/openapi/api-v1.yaml](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/resources/openapi/api-v1.yaml).
2. **Cross-Context Route & Instance Authorization (`AC-1`..`AC-6`)**
   - [`RbacManagementService`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/java/com/example/app/iam/service/RbacManagementService.java#L89-L243):
     - Evaluated `support.matchRoutePermission(method, requestUri)` in `evaluateRoute` before the self-service cancel check (`POST /api/v1/tickets/{id}/cancel`) so soft-deleted `governance:tickets:cancel` revokes route access immediately with `403 AUTH_FORBIDDEN` (`AC-4`).
     - Added `execution:runs:manage` (`EXECUTION_RUNS_MANAGE`) alias resolution (`AC-3`) and removed `governance:tickets:write` from the `governance:tickets:manage` alias so `View-As` roles and preparers cannot access `GET /api/v1/tickets?queueView=MANAGE` (`AC-2`, `AC-5`).
   - [`ReportRunOrchestratorService`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/main/java/com/example/app/exe
<truncated 2207 bytes>
ity` -> **`BUILD SUCCESS`** (`138` tests run, `0` failures, `0` errors, `0` skipped; JaCoCo coverage check passed; Checkstyle `0` violations; SpotBugs `0` bugs; OWASP Dependency-Check `0` CVEs `>= 7.0`; ArchUnit [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java) `3/3` passed).
- **Build Plan**: [plan.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/plan.md) (`AC-1`..`AC-6` all `done`)
- **Build Report**: [build-report.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/build-report.md)
- **Build Output**: [build-output.txt](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/build/p2-n-integration-iam-cross-context-authorization-guard/build-output.txt)
- **Phase Result & State**: [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md), [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json) (`activePhase: "build"`, `phaseStatus: "awaiting_approval"`)

---

### Approval Gate

Please review the Build artifacts and confirm whether you approve the **Build** phase for `p2-n-integration-iam-cross-context-authorization-guard` to proceed to `/v0-verify`.
