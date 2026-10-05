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

Targets are the filled rows in `docs/agents-v0/design/system/nfr-slo.md`. Do not copy them here. P4 closes that table in `docs/agents-v0/design/system/slo-evidence.md`.

## Stories

| Story | Why this record covers it |
|-------|---------------------------|
| <story id> | <new service, new datastore, new security boundary, or breaking API> |

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| arc | docs/agents-v0/design/system/arc-record.md | <name> | Approved | <date> |

> The program decision is the `architecture` row, which names this file. Add an `arc` row here only when a story amends the recommendation.
> `ci/check-arc.sh` accepts that architecture row, or an `arc` row on this file, when a requirements artifact says `Material: yes`.
