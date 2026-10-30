The **Local Release** (`/v0-local-release`) preparation for Story **P2-C** (`p2-c-iam-user-directory-onboarding-exports` — *IAM User Directory, Role Assignments, Onboarding & Access Review Exports*) is complete and ready for your approval.

### Release Readiness Summary
1. **Prerequisites & State:** Confirmed `"verifyPassed": true` and `"verify"` in `approvedPhases` in [p2-c-iam-user-directory-onboarding-exports.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json).
2. **Documentation & Changelog:** [README.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/README.md) and [iam-auth-sod.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/diagrams/sequences/iam-auth-sod.md) are in sync; no `CHANGELOG.md` or `Deploy` table is configured in [project-profile.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/project-profile.md).
3. **Final Native Stack Check (`cd app/backend && ./mvnw -B clean verify -Pci-security`):**
   - **Result:** `BUILD SUCCESS` (exit code `0`) against portable PostgreSQL 17.11.
   - **Tests:** `66` passed (`0` failures, `0` errors, `0` skipped), including all `8` integration scenarios in [`IamUserDirectoryOnboardingExportsTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/app/backend/src/test/java/com/example/app/iam/IamUserDirectoryOnboardingExportsTest.java) and `3` ArchUnit boundary checks in [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java).
   - **Quality & Security Gates:** JaCoCo bundle coverage check passed (`93.85%` line coverage, `>= 80%`), Checkstyle `0` violations, SpotBugs `0` bugs, OWASP Dependency-Check `0` HIGH/CRITICAL vulnerabilities across `28` dependencies.
4. **Phase Result & State:** Recorded in [p2-c-iam-user-directory-onboarding-exports.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md) and [p2-c-iam-user-directory-onboarding-exports.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json) (`activePhase: "release"`, `activeStatus: "awaiting_approval"`).

### Proposed Lessons (`## Proposed lessons`)
- `none` (verified with `check-lessons.sh --unchanged-since main`)

---

### Approval Request
Please confirm if you approve completing the **Local Release** for `p2-c-iam-user-directory-onboarding-exports`:
1. Committing the pending verification/release evidence on `feature/p2-c-iam-user-directory-onboarding-exports`,
2. Merging `feature/p2-c-iam-user-directory-onboarding-exports` (`--no-ff`) into the integration branch `main`, and
3. Approving the `release` phase and committing the final release state on `main`.
The **Local Release** (`/v0-local-release`) preparation for Story **P2-C** (`p2-c-iam-user-directory-onboarding-exports` — *IAM User Directory, Role Assignments, Onboarding & Access Review Exports*) is complete and ready for your approval.

### Release Readiness Summary
1. **Prerequisites & State:** Confirmed `"verifyPassed": true` and `"verify"` in `approvedPhases` in [p2-c-iam-user-directory-onboarding-exports.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json).
2. **Documentation & Changelog:** [README.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/README.md) and [iam-auth-sod.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/diagrams/sequences/iam-auth-sod.md) are in sync; no `CHANGELOG.md` or `Deploy` table is configured in [project-profile.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/project-profile.md).
3. **Final Native Stack Check (`cd app/backend && ./mvnw -B clean verify -Pci-security`):**
   - **Result:** `BUILD SUCCESS` (exit code `0`) against portable PostgreSQL 17.11.
   - **Tests:** `66` passed (`0` failures, `0` errors, `0` skipped), including all `8` integration scenarios in [`IamUserDirectoryOnboardingExportsTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/app/backend/src/test/java/com/example/app/iam/IamUserDirectoryOnboardingExportsTest.java) and `3` ArchUnit boundary checks in [`LayerRulesTest`](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/app/backend/src/test/java/com/example/app/architecture/LayerRulesTest.java).
   - **Quality & Security Gates:** JaCoCo bundle coverage check passed (`93.85%` line coverage, `>= 80%`), Checkstyle `0` violations, SpotBugs `0` bugs, OWASP Dependency-Check `0` HIGH/CRITICAL vulnerabilities across `28` dependencies.
4. **Phase Result & State:** Recorded in [p2-c-iam-user-directory-onboarding-exports.phase-result.md](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.phase-result.md) and [p2-c-iam-user-directory-onboarding-exports.state.json](file:///home/e2e/agents-v0-e2e/run-20261029-1629/work/portal-p2-c-iam-user-directory-onboarding-exports/docs/agents-v0/requirements/p2-c-iam-user-directory-onboarding-exports.state.json) (`activePhase: "release"`, `activeStatus: "awaiting_approval"`).

### Proposed Lessons (`## Proposed lessons`)
- `none` (verified with `check-lessons.sh --unchanged-since main`)

---

### Approval Request
Please confirm if you approve completing the **Local Release** for `p2-c-iam-user-directory-onboarding-exports`:
1. Committing the pending verification/release evidence on `feature/p2-c-iam-user-directory-onboarding-exports`,
2. Merging `feature/p2-c-iam-user-directory-onboarding-exports` (`--no-ff`) into the integration branch `main`, and
3. Approving the `release` phase and committing the final release state on `main`.
