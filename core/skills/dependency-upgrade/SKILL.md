---
name: dependency-upgrade
description: Maintain phase playbook. Bump versions, run verify, confirm no new high/critical CVEs.
---

# dependency-upgrade

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Identify the target dependency/CVE (OWASP Dependency-Check, Dependabot, Snyk).
2. Bump the version in the build file; regenerate the lockfile.
3. Run `mvn -B clean verify` (Java) or the frontend script; fix breakages with the smallest diff and bounded attempts (≤ 3 per failure).
4. Re-run OWASP Dependency-Check; confirm no new high/critical CVEs. Document any exception.
5. Produce/refresh SBOM (CycloneDX/SPDX) when compliance requires.
6. If the upgrade changes behavior or topology, sync docs (`doc-sync` skill).
7. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `security-baseline.mdc` §9: dependency scanning; SBOM when required; no new high/critical CVEs without documented exception.
- [ ] `quality-and-testing.mdc`: `mvn -B clean verify` green; coverage maintained.
- [ ] `ai-agent-conduct.mdc`: smallest diff; no commits without approval.
- [ ] `architecture-and-diagrams.mdc`: docs updated if topology changed.
- [ ] `workflow-orchestration.mdc`: routed to Verify after upgrade.
