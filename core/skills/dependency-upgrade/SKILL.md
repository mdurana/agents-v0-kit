---
name: dependency-upgrade
description: Maintain phase playbook. Bump versions with a before/after graph diff, read the release notes, confirm no new high/critical CVEs.
---

# dependency-upgrade

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`, `/maintain`). The record is the maintenance note `docs/maintain/<id>/note.md`.

## Steps
1. **Target.** Name each dependency, the CVE IDs it clears, and from → to versions under Acceptance in the note (OWASP Dependency-Check, Dependabot, Snyk).
2. **Size the bump.** A major version bump, a framework or parent change (Spring Boot, a build plugin chain), or a change that needs code edits beyond version numbers is not a Trivial change. If it needs design or touches many call sites, stop and say it is a feature (`/intake`). Patch and minor bumps stay here.
3. **Baseline and graph.** Run the full verify command, then `sh scripts/collect-dependency-graphs.sh` and keep the output as the "before" copy (`docs/discovery/`, copied to `docs/maintain/<id>/graph-before.txt`).
4. **Release notes.** Read the release notes between the two versions. Write the breaking changes and security fixes that matter to this repo in the note, with the link.
5. Bump the version in the build file; regenerate the lockfile.
6. Run the full verify command; fix breakages with the smallest diff and bounded attempts (≤ 3 per failure). Each attempt appends a card to `docs/build/<id>/build-report.md`; run `sh scripts/check-attempt-budget.sh docs/build/<id>/build-report.md` before the next one.
7. **Graph diff.** Run the graph script again and diff it against the "before" copy. Every transitive dependency that changed is listed in the note. An unexpected major jump in a transitive dependency is a stop.
8. Re-run OWASP Dependency-Check; confirm the target CVEs are gone and there are no new high/critical CVEs. Document any exception. For a license-restricted program, check the new dependencies' licenses.
9. Produce/refresh SBOM (CycloneDX/SPDX) when compliance requires.
10. If the upgrade changes behavior or topology, sync docs (`doc-sync` skill).
11. Run `sh ci/classify-change.sh <base>` and paste it into the note. A version-only change is Trivial-eligible; anything else is `standard`.
12. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `security-baseline.mdc` §9: dependency scanning; SBOM when required; no new high/critical CVEs without documented exception.
- [ ] `quality-and-testing.mdc`: `mvn -B clean verify` green; coverage maintained.
- [ ] `ai-agent-conduct.mdc`: smallest diff; no commits without approval.
- [ ] Release notes read; graph diff recorded in the note; no major bump slipped into a maintenance change.
- [ ] `architecture-and-diagrams.mdc`: docs updated if topology changed.
- [ ] `workflow-orchestration.mdc`: classifier output in the note; routed to the right Verify.
