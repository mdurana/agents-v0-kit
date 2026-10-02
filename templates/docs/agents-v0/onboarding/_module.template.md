# Module: <name>

> Copy to `docs/agents-v0/onboarding/modules/<name>.md`. Every factual statement ends with a backticked citation (`path/File.java:42`), or says `UNVERIFIED`. Configuration is described by key name only; never write a value.

commit: <full sha of the tree this document describes>
Root: <path>
Owner: <from CODEOWNERS, or UNVERIFIED>

## Purpose

<!-- TEMPLATE: what this module does and for whom, in two or three sentences. -->

## Public surface

| Endpoint, event, or UI route | Cited at | Authorization |
|------------------------------|----------|---------------|
| <!-- TEMPLATE: e.g. POST /api/v1/orders --> | <!-- `path/File.java:42` --> | <!-- the annotation or config that enforces it, or UNVERIFIED --> |

## Data owned

<!-- TEMPLATE: entities, tables, and the latest migration, from docs/agents-v0/discovery/entities.txt and migrations.txt. -->

## Depends on and used by

<!-- TEMPLATE: other modules, services, brokers, and outbound APIs, from docs/agents-v0/discovery/messaging.txt and outbound.txt. -->

## Configuration

<!-- TEMPLATE: the key names and environment variables this module reads, from docs/agents-v0/discovery/config.txt. Names only. -->

## Security notes

<!-- TEMPLATE: authentication, authorization, session, upload, and secret handling as the code does it today. Do not fix anything here. -->

## Tests

<!-- TEMPLATE: where the tests are, what they cover, and what is not covered. -->

## Hotspots and debt

<!-- TEMPLATE: large or complex classes, known workarounds, dead code, TODO clusters, each with a citation. -->

## UNVERIFIED and open questions

<!-- TEMPLATE: what could not be determined from the code, one line each. Repeat each in the report's open questions. -->
