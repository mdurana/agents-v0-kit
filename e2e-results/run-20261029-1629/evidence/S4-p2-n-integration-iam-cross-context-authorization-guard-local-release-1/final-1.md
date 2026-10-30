Local release preparation for **Story `P2-N` (`p2-n-integration-iam-cross-context-authorization-guard` — Cross-Context Integration: IAM Cross-Context Authorization Guard)** is complete and at the approval gate (`phase: release`, `status: awaiting_approval`).

### Verification & Release Readiness Summary
1. **Prerequisites & State:**
   - Confirmed `"verifyPassed": true` and `"verify"` in `approvedPhases` in [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json).
   - Target integration branch resolved via `resolve-integration-branch.sh`: `main`.
   - Phase result recorded in [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md).
2. **Final Native Stack Check (`cd app/backend && ./mvnw -B clean verify -Pci-security`):**
   - **BUILD SUCCESS** (`Exit: 0`).
   - `138` tests run across `33` test classes (`6/6` in [`IamCrossContextAuthorizationGuardIntegrationTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/iam/IamCrossContextAuthorizationGuardIntegrationTest.java), `3/3` in [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java), `5/5` in [`OpenApiContractCatalogTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/api/OpenApiContractCatalogTest.java)), `0` failures, `0` errors, `0` skipped.
   - JaCoCo coverage check passed (`91.25%` overall line coverage, `88.65%` changed-class line coverage), Checkstyle `0` violations, SpotBugs + FindSecBugs `0` bugs, OWASP Dependency-Check `0` CVEs $\ge 7.0$.
3. **Lessons Check (`check-lessons.sh --unchanged-since main`):**
   - `OK` ([lessons.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/lessons.md) untouched on the story branch).

---

### Proposed Lessons (Accept or Reject)
Please state whether you **accept** or **reject** the following proposed lesson (any `P-<n>` without an explicit accept will be marked `rejected`):

- **`P-1`** · `pending` · `build` · **Trigger:** `other` · **What happened:** Self-service route bypasses in `RbacManagementService.evaluateRoute` (such as `POST /api/v1/tickets/{id}/cancel` for ticket requesters/owners) skipped `support.matchRoutePermission`, so soft-deleting the mapped `permissions` row (`is_active = false`) did not revoke route access on the next request · **Do instead:** Verify that the matched route permission exists and is active (`is_active = true`, `deleted_at IS NULL`) before applying any self-service or instance-level route shortcut · **Scope:** Java backend route-authorization guards and `IamAuthorizationPort` implementations in `app/backend/`

---

### Approval Request
Please confirm if you approve completing the local release:
1. Committing the pending delivery evidence and state updates on `feature/p2-n-integration-iam-cross-context-authorization-guard`,
2. Merging `feature/p2-n-integration-iam-cross-context-authorization-guard` (`--no-ff`) into `main`, and
3. Recording `release` approval (and any accepted lessons in `docs/agents-v0/lessons.md`) and committing the release state on `main`.
Local release preparation for **Story `P2-N` (`p2-n-integration-iam-cross-context-authorization-guard` — Cross-Context Integration: IAM Cross-Context Authorization Guard)** is complete and at the approval gate (`phase: release`, `status: awaiting_approval`).

### Verification & Release Readiness Summary
1. **Prerequisites & State:**
   - Confirmed `"verifyPassed": true` and `"verify"` in `approvedPhases` in [p2-n-integration-iam-cross-context-authorization-guard.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.state.json).
   - Target integration branch resolved via `resolve-integration-branch.sh`: `main`.
   - Phase result recorded in [p2-n-integration-iam-cross-context-authorization-guard.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/requirements/p2-n-integration-iam-cross-context-authorization-guard.phase-result.md).
2. **Final Native Stack Check (`cd app/backend && ./mvnw -B clean verify -Pci-security`):**
   - **BUILD SUCCESS** (`Exit: 0`).
   - `138` tests run across `33` test classes (`6/6` in [`IamCrossContextAuthorizationGuardIntegrationTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/iam/IamCrossContextAuthorizationGuardIntegrationTest.java), `3/3` in [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java), `5/5` in [`OpenApiContractCatalogTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/app/backend/src/test/java/com/example/app/api/OpenApiContractCatalogTest.java)), `0` failures, `0` errors, `0` skipped.
   - JaCoCo coverage check passed (`91.25%` overall line coverage, `88.65%` changed-class line coverage), Checkstyle `0` violations, SpotBugs + FindSecBugs `0` bugs, OWASP Dependency-Check `0` CVEs $\ge 7.0$.
3. **Lessons Check (`check-lessons.sh --unchanged-since main`):**
   - `OK` ([lessons.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-n-integration-iam-cross-context-authorization-guard/docs/agents-v0/lessons.md) untouched on the story branch).

---

### Proposed Lessons (Accept or Reject)
Please state whether you **accept** or **reject** the following proposed lesson (any `P-<n>` without an explicit accept will be marked `rejected`):

- **`P-1`** · `pending` · `build` · **Trigger:** `other` · **What happened:** Self-service route bypasses in `RbacManagementService.evaluateRoute` (such as `POST /api/v1/tickets/{id}/cancel` for ticket requesters/owners) skipped `support.matchRoutePermission`, so soft-deleting the mapped `permissions` row (`is_active = false`) did not revoke route access on the next request · **Do instead:** Verify that the matched route permission exists and is active (`is_active = true`, `deleted_at IS NULL`) before applying any self-service or instance-level route shortcut · **Scope:** Java backend route-authorization guards and `IamAuthorizationPort` implementations in `app/backend/`

---

### Approval Request
Please confirm if you approve completing the local release:
1. Committing the pending delivery evidence and state updates on `feature/p2-n-integration-iam-cross-context-authorization-guard`,
2. Merging `feature/p2-n-integration-iam-cross-context-authorization-guard` (`--no-ff`) into `main`, and
3. Recording `release` approval (and any accepted lessons in `docs/agents-v0/lessons.md`) and committing the release state on `main`.
