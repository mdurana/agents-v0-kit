---
name: system-design
description: Major-tier system design when no program architecture row exists. Record the missing decision in the feature design. Do not run /v0-architecture.
---

# system-design

Use this only for a **Major** story that has no `Approved` `architecture` row (`workflow-orchestration.mdc`). A new program writes the pack in `/v0-architecture` before any backlog.

## Steps
1. When `docs/agents-v0/architecture.md` has an `Approved` `architecture` row, cite that file and `docs/agents-v0/design/system/arc-record.md`. Do not rewrite them or an Accepted ADR under `docs/agents-v0/adr/`. A changed decision supersedes that ADR.
2. When that row is absent, record the missing architecture decision in the feature ADR and threat-model notes from the requirements artifact. Do not invent a roadmap, do not run `/v0-architecture`, and do not write under `.agents-v0/packs/`. Stop for the user to approve that note before feature contracts.
3. Do not write a second copy of those steps here.

## Rule-compliance checklist
- [ ] An existing `architecture` row was cited, or the feature ADR and threat-model notes record the gap.
- [ ] `architecture-and-diagrams.mdc` and `security-baseline.mdc` §11 are addressed by that pack.
- [ ] Async, messaging, and cache are justified (`project-delivery-core.mdc`).
