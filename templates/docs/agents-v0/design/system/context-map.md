# System context map

> Produced by `program-architecture` (program) or `system-design` (Major story). Also the service map: one row per bounded context, with the paths a reader needs to find its code, contract, flows, and component plan.

## Bounded contexts

| Context | Responsibility | Integrations | Service root | Contract | Sequence diagram | Component plan | Status |
|---------|----------------|--------------|--------------|----------|------------------|----------------|--------|
| | | | | | | | |

> **Integrations:** name called contexts by their Context-column name (or unique 4+ char first-word alias) so plan-phase integration-pair traceability checks detect them; backtick code spans (`...`) are ignored. **Service root:** the profile's `Service roots` entry, or `.` for a single-service repo. **Contract:** `openapi/<service>-v1.yaml` (or `openapi/api-v1.yaml`), or `N/A: no HTTP API`. **Sequence diagram:** `docs/agents-v0/diagrams/sequences/<service>.md`. **Component plan:** `docs/agents-v0/design/system/components/<service>.md` (from `_component.template.md`), or `N/A: <reason>`. **Status:** `planned`, `active`, or `deprecated`.

## Sync vs async

(Document request/response vs events per boundary.)
