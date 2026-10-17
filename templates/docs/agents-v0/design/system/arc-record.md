# ARC record

Roadmap: <docs/agents-v0/roadmap/<program>.md, or N/A when this story has no roadmap>
Discovery: <the Discovery path recorded on that roadmap, or N/A>

## Problem

<Path of the discovery file, or of the Major story's requirements artifact. Do not copy the text.>

## Options

<Path of the pattern ADR under docs/agents-v0/adr/. Do not copy the options.>

## Recommendation

<option name from that ADR>

## Diagrams

<Mermaid or a path under docs/agents-v0/diagrams/>

## Fitness functions

Latency, availability, and RPO/RTO targets are the filled rows in `docs/agents-v0/design/system/nfr-slo.md`. Do not copy them here. P4 closes that table in `docs/agents-v0/design/system/slo-evidence.md`.

Structural fitness functions say what must stay true about the shape of the system, how a test or CI job proves it, and what happens when it fails. A row names a real check (for example an ArchUnit rule, see `core/java/starters/maven/archunit/LayerRulesTest.java`, a contract diff, or a dependency rule) or says `planned: <milestone>`.

| Principle | Check | Threshold | On failure |
|-----------|-------|-----------|------------|
| <e.g. no cyclic dependencies between modules> | <e.g. ArchUnit rule> | <e.g. zero cycles> | <e.g. block merge> |

## Stories

| Story | Why this record covers it |
|-------|---------------------------|
| <story id> | <new service, new datastore, new security boundary, or breaking API> |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| arc | docs/agents-v0/design/system/arc-record.md | <name> | Approved | <date> |

> The program decision is the `architecture` row, which names this file. Add an `arc` row here only when a story amends the recommendation. When that recommendation changes, the accepted pattern ADR stays. `## Options` names the successor. The old ADR's status is `Superseded by ADR <NN>`.
> `.agents-v0/ci/check-arc.sh` accepts that architecture row, or an `arc` row on this file, when a requirements artifact says `Material: yes`.
