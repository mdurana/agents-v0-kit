---
name: program-architecture
description: Program architecture playbook. C4 through operations and the ARC pack after an approved roadmap and before any milestone stories.
---

# program-architecture

Playbook for the `solution-architect` during `/v0-architecture` (`workflow-orchestration.mdc` Architecture).

## Steps
1. Read the problem source. For a program, that is the approved roadmap and the discovery file at its `Discovery:` path. For a Major story with no roadmap, that is `docs/agents-v0/requirements/<feature>.md`. Do not invent a roadmap for that story. Read `docs/agents-v0/project-profile.md` and, on a brownfield repo, the as-is `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, and onboard module notes. Do not delete as-is citations.
2. **C4.** Add `## C4 Context` and `## C4 Container` to `docs/agents-v0/architecture.md`. People, systems, and containers only. No product, database, or broker names. Label every edge with its protocol and say sync or async.
3. **Pattern.** Write `docs/agents-v0/adr/<NN>-<slug>.md` with at least two real options, why one won, and Status `Proposed` (then `Accepted` when the architecture row is approved). This is where technology is chosen. Fill `## Patterns considered` and compare the options on cost, security, reliability, and operability. Pick the topology from the forces, not from habit: a modular monolith fits one team and unclear boundaries, separate services fit clear bounded contexts and independent scaling, serverless fits bursty event work, sync-only integration fits simple CRUD with no cross-service writes. A brownfield decomposition names its migration pattern (strangler fig, adapter, dual write, or flag-controlled cutover). When an Accepted ADR already records the decision, leave it. A new decision supersedes it: Status `Superseded by ADR <NN>` on the old file, and the new decision in the next file. Run `sh .agents-v0/ci/check-adr.sh`.
4. **Platform.** Extend `docs/agents-v0/network.md` with the target topology: a `## Target topology` Mermaid flowchart with zones, protocol-labelled edges, and the security boundaries. Label target rows so they stay distinct from as-is rows.
5. **Services.** Fill `docs/agents-v0/design/system/context-map.md`, which is also the service map (one row per context: responsibility, integrations, service root, contract, sequence diagram, component plan, status). Then add to `docs/agents-v0/architecture.md`:
   - `## Data flow`: the C4 Container diagram with the same node IDs and edges relabelled `transport / payload`.
   - `## Data models`: `### Conceptual`, `### Logical` (erDiagram, every field, PK and FK), `### Physical` (erDiagram, every field with its type, migration owner, retention and soft delete).
   - `## State machine`: a `stateDiagram-v2` for each aggregate with a lifecycle.
   - `## Failure domains and degradation`: one row per dependency, with what degrades, what halts, and how it is validated.
   - `## MVP and future state`: the simplest topology that meets today's requirements, and the trigger for each later change.
   Add sequence diagrams for the critical flows (success and the timeout or error path) under `docs/agents-v0/diagrams/sequences/`. For each context write `docs/agents-v0/design/system/components/<service>.md` from `docs/agents-v0/design/system/_component.template.md`, or put `N/A: <reason>` in the Component plan cell (a single-service repo usually does). A component plan links its parent and never contradicts it. A section that does not apply says `N/A: <reason>`; do not delete the heading.
6. **Contracts.** Record the catalog shape (one file per service root, or `openapi/api-v1.yaml`). Do not write `docs/agents-v0/design/<feature>/openapi.yaml`. Record the deprecation rule once: additive changes first, `deprecated: true` plus a sunset date before a removal, and a new major version or an ADR for a breaking change.
7. **Operations.** Update `docs/agents-v0/design/system/nfr-slo.md` and `docs/agents-v0/design/system/threat-model.md`. The SLO numbers live only in `nfr-slo.md`. Fill `docs/agents-v0/design/system/ops-readiness.md`: build-and-run ownership, the error budget policy, database maintenance and operation, and leave the readiness checklist for P5. Async, messaging, and cache appear only when the problem source or the pattern ADR justifies them.
8. **ARC.** Fill `docs/agents-v0/design/system/arc-record.md`. Name the discovery file or the requirements artifact, and name the pattern ADR. Do not copy their text. Name the recommendation. Point `## Fitness functions` at `docs/agents-v0/design/system/nfr-slo.md` for the SLO targets, and fill the structural table (principle, check, threshold, on failure) with checks that exist or `planned: <milestone>`. Do not copy the SLO rows.
9. Run `sh .agents-v0/ci/check-architecture-pack.sh` and fix what it reports. It does not replace the review in the next step.
10. **Independent review.** The main session launches `design-reviewer` on the pack. It writes `docs/agents-v0/design/system/architecture-review.md`. Fix each Critical finding, mark it `Resolved` after the reviewer re-checks, and run the check again.
11. Stop for one explicit approval. Append only the `architecture` row on `docs/agents-v0/architecture.md`. Its Artifacts cell names every pack path, including `docs/agents-v0/design/system/arc-record.md` and `docs/agents-v0/design/system/architecture-review.md`. Do not add an `arc` row. That row is only for a later story that amends the recommendation.

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | architecture | docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md, and the other pack paths | &lt;name&gt; | Approved | &lt;date&gt; |

12. Do not write milestone stories. `/v0-plan` does that after the `architecture` row exists.

## Governance after approval
- A later story that changes the recommendation is a **material** change: supersede the pattern ADR and add an `arc` row (`contract-first-design` step 7b). A pattern library tweak or a threshold change is minor: update the pack in a docs-only change, no `arc` row.
- Deprecating a service or contract is advisory (warn consumers, `Status: deprecated` in the context map) or compulsory (an ADR, a dated plan, consumers migrated first).
- When a story, an incident, or `doc-sync` shows the code drifted from the pack (a contract violation, a failed fitness function, an unexpected dependency), correct the pack or the code early. A material correction goes back through `/v0-architecture`.

## Rule-compliance checklist
- [ ] C4 sections name no product technology.
- [ ] The pattern ADR has two real options and a filled `Patterns considered` table. An Accepted ADR was superseded, not rewritten, when the decision changed. `ci/check-adr.sh` passes.
- [ ] Data flow reuses the C4 Container nodes. Data models, state machine, failure domains, and MVP and future state are written or `N/A: <reason>`.
- [ ] `network.md` has a target topology diagram. As-is onboard text was kept.
- [ ] The context map is the service map, and each context has a component plan or `N/A: <reason>`.
- [ ] `ops-readiness.md` names an owner and an error budget policy. The ARC record has a structural fitness function row.
- [ ] No feature OpenAPI draft and no story rows were written.
- [ ] `ci/check-architecture-pack.sh` passes and `architecture-review.md` has no open Critical.
- [ ] The `architecture` row names the ARC file and the review. No `arc` row was added.
