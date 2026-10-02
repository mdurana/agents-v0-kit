# Onboarding report

> Copy to `docs/agents-v0/onboarding/report.md` at the start of `/v0-onboard`. Every factual statement in the onboarding documents cites code in backticks (`path/File.java:42`) or says `UNVERIFIED`. `sh .agents-v0/scripts/check-onboarding-docs.sh` rejects a citation that does not resolve and any `TEMPLATE:` line left behind.

commit: <full sha of the tree this report describes>
Date: <YYYY-MM-DD>
Scope: <roots and modules documented; what is out of scope and why>
Confidence: <high | medium | low, per area, with the reason>

## Summary

<!-- TEMPLATE: one paragraph — what the system does, the stack, the size, who owns it. -->

## Produced

| Document | Path | Notes |
|----------|------|-------|
| Project profile | `docs/agents-v0/project-profile.md` | commands, Layout, contracts |
| Repository map | `docs/agents-v0/repo-map.md` | generated |
| Inventories and baseline | `docs/agents-v0/discovery/` | generated; read the cited lines before relying on a row |
| Architecture, network | `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md` | as-is |
| Context map | `docs/agents-v0/design/system/context-map.md` | contexts as they exist today |
| Inherited decisions | `docs/agents-v0/adr/0000-inherited-decisions.md` | |
| Flows | `docs/agents-v0/diagrams/sequences/` | the flows the user named |
| Modules | `docs/agents-v0/onboarding/modules/` | one file per module |

## Modules

| Module | Document | Owner | Confidence |
|--------|----------|-------|------------|
| <!-- TEMPLATE: module name --> | <!-- docs/agents-v0/onboarding/modules/name.md --> | <!-- CODEOWNERS or UNVERIFIED --> | <!-- high / medium / low --> |

## Baseline

<!-- TEMPLATE: result of the baseline audit and the numbers from docs/agents-v0/discovery/baseline.md (tests, failures, coverage, CVEs). List the known_failures and coverage_ratchet rows you propose. A person approves them; do not add them to the profile before that. -->

## Security baseline

<!-- TEMPLATE: summary of docs/agents-v0/discovery/security-baseline.md: unannotated endpoints, permit-all or CSRF/CORS findings, literal secrets in config (names only). List what needs /v0-maintain triage. Fix nothing during onboarding. -->

## Open questions and UNVERIFIED items

| # | Question or unknown | Where it matters | Owner |
|---|---------------------|------------------|-------|
| <!-- TEMPLATE: 1 --> | | | |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| onboard | docs/agents-v0/onboarding/report.md, docs/agents-v0/onboarding/modules/ | | | |
