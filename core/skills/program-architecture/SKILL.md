---
name: program-architecture
description: Program architecture playbook. C4 through operations and the ARC pack after an approved roadmap and before any milestone stories.
---

# program-architecture

Playbook for the `solution-architect` during `/v0-architecture` (`workflow-orchestration.mdc` Architecture).

## Steps
1. Read the problem source. For a program, that is the approved roadmap and the discovery file at its `Discovery:` path. For a Major story with no roadmap, that is `docs/agents-v0/requirements/<feature>.md`. Do not invent a roadmap for that story. Read `docs/agents-v0/project-profile.md` and, on a brownfield repo, the as-is `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, and onboard module notes. Do not delete as-is citations.
2. **C4.** Add `## C4 Context` and `## C4 Container` to `docs/agents-v0/architecture.md`. People, systems, and containers only. No product, database, or broker names.
3. **Pattern.** Write `docs/agents-v0/adr/<NN>-<slug>.md` with at least two real options, why one won, and Status `Proposed` (then `Accepted` when the architecture row is approved). This is where technology is chosen. When an Accepted ADR already records the decision, leave it. A new decision supersedes it: Status `Superseded by ADR <NN>` on the old file, and the new decision in the next file. Run `sh .agents-v0/ci/check-adr.sh`.
4. **Platform.** Extend `docs/agents-v0/network.md` with the target topology. Label target rows so they stay distinct from as-is rows.
5. **Services.** Update `docs/agents-v0/design/system/context-map.md` (one row per context: purpose, service root when known, owner, sync or async). Add sequence diagrams for the critical flows under `docs/agents-v0/diagrams/sequences/`.
6. **Contracts.** Record the catalog shape (one file per service root, or `openapi/api-v1.yaml`). Do not write `docs/agents-v0/design/<feature>/openapi.yaml`.
7. **Operations.** Update `docs/agents-v0/design/system/nfr-slo.md` and `docs/agents-v0/design/system/threat-model.md`. The SLO numbers live only in `nfr-slo.md`. Async, messaging, and cache appear only when the problem source or the pattern ADR justifies them.
8. **ARC.** Fill `docs/agents-v0/design/system/arc-record.md`. Name the discovery file or the requirements artifact, and name the pattern ADR. Do not copy their text. Name the recommendation. Point `## Fitness functions` at `docs/agents-v0/design/system/nfr-slo.md`. Do not copy those rows.
9. Stop for one explicit approval. Append only the `architecture` row on `docs/agents-v0/architecture.md`. Its Artifacts cell names every pack path, including `docs/agents-v0/design/system/arc-record.md`. Do not add an `arc` row. That row is only for a later story that amends the recommendation.

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | architecture | docs/agents-v0/architecture.md, docs/agents-v0/design/system/arc-record.md, and the other pack paths | &lt;name&gt; | Approved | &lt;date&gt; |

10. Do not write milestone stories. `/v0-plan` does that after the `architecture` row exists.

## Rule-compliance checklist
- [ ] C4 sections name no product technology.
- [ ] The pattern ADR has two real options. An Accepted ADR was superseded, not rewritten, when the decision changed. `ci/check-adr.sh` passes.
- [ ] As-is onboard text was kept.
- [ ] No feature OpenAPI draft and no story rows were written.
- [ ] The `architecture` row names the ARC file. No `arc` row was added.
