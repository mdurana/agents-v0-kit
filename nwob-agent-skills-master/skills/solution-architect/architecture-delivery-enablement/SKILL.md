---
name: architecture-delivery-enablement
description: >-
  Enables team self-service via code-as-documentation, architecture pattern
  libraries, fitness functions in CI/CD, and service catalogue entries per the
  Enterprise System Constitution. Use when user invokes /contracts or for OpenAPI/IaC
  contracts, API stability, templates, compliance gates, or catalogue onboarding.
---

# Architecture Delivery Enablement

## Overview

Enables team self-service via code-as-documentation, architecture pattern libraries, fitness functions in CI/CD, and service catalogue entries. Adapts fitness functions and module boundaries to effective topology from pattern ADR (monolith ArchUnit modules vs service boundaries). Applies organisational architecture gold standards and [constitution-core.mdc](../../../rules/constitution-core.mdc).

**Authors:** Solution Architect **or** Lead Builder (co-equal). Both may author OpenAPI. **Pod Builder MUST NOT** author OpenAPI or architecture contracts. When linking component specs from `service-map.md`, prefer `nwob-docs/sdd/components/` paths (legacy `architecture/components/` is read-only brownfield fallback).

Skill boundaries: [references/rules/solution-architect-skill-boundaries.md](../../../references/rules/solution-architect-skill-boundaries.md). Commands: [solution-architect-command-standards.md](../../../references/rules/solution-architect-command-standards.md).

## Commands

| Command | Scope | Prerequisite | Output |
|---------|-------|--------------|--------|
| `/contracts` | OpenAPI/event contracts, patterns, fitness thresholds, catalogue | `/services` outputs or accepted monolith pattern ADR | Contracts, pattern refs, fitness definitions, catalogue draft (SA **or** LB) |
| `/architecture` | Step 7 of full chain | Per command-standards | As above, within orchestrated flow |

**`/contracts` stop:** If neither `/services` sections exist in `architecture.md` / `masterplan.md` nor accepted pattern ADR for monolith scope, stop and redirect to `/services` or `/pattern`.

## When to Use

- API, event, or infra contracts as code
- API stability, versioning, and deprecation policy
- Reusable templates or accelerators for teams
- CI/CD architectural compliance gate definitions
- Service catalogue onboarding or updates

## Process

Resolve effective stack and data lifecycle per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints) before applying patterns.

Run `nwob doctor` if `repositories/` or `nwob-docs/architecture/service-map.md` is missing.

### OpenAPI persistence (`/contracts` — mandatory)

For every in-scope service with an HTTP API:

1. Read `nwob-docs/architecture/service-map.md`; resolve `{service-name-from-mapping}` from the **Logical service** column.
2. Create `repositories/{service-name}/src/main/resources/swagger/` if absent (greenfield may precede submodule init).
3. Write OpenAPI 3.0 YAML to that directory (default filename: `{service-name}-api.yaml`).
4. Update service-map **OpenAPI / contract** column with the full relative path; ensure **Component Spec** links point at `nwob-docs/sdd/components/` when present.
5. Sync catalogue **API Spec** field with the same path.
6. Do **not** store OpenAPI only in `nwob-docs/` or chat — the service repo swagger path is the design-time source of truth. SA **or** LB may author.

AsyncAPI / event schemas (when in scope): default subpath `repositories/{service-name}/src/main/resources/asyncapi/`; document in service-map.

### API Contract Design

Contract-first: define OpenAPI 3.0 before implementation. Implementation follows the contract.

**Hyrum's Law:** With sufficient API consumers, all observable behaviors become dependencies — including undocumented quirks, error text, and ordering. Design implications:

- Be intentional about what you expose.
- Do not leak implementation details in public contracts.
- Plan deprecation at design time (see Deprecation Policy below).
- Prefer additive changes over breaking modifications.

**One-Version Rule:** Avoid forcing consumers to choose between multiple versions of the same dependency. Extend rather than fork.

**REST design (Java/Spring Boot):**

- Resource-oriented URLs: `/api/v1/{resource}/{id}`
- Validate only at system boundaries (`@Valid` on request DTOs)
- Consistent error semantics via RFC 7807 at every boundary
- Pagination: `page`, `limit`, `total`, `totalPages` in list metadata
- Filtering via query parameters; PATCH for partial updates
- OpenAPI spec auto-generated at build per Contracts and quality in constitution-core

### Code as Documentation

Design and implementation stay aligned via executable, verifiable artefacts.

1. **Identify Artefacts:** API contracts, infra topology, event schemas, security policies, data models.
2. **Embed in Code:** OpenAPI 3.0, Terraform/CDK, AsyncAPI, schema migrations (default: Liquibase), policy-as-code — adapt to effective stack.
3. **Automate Validation:** Contract tests, schema linting, OPA/Checkov, OpenAPI diff in CI.
4. **Reject Drift:** Fail builds when implementation diverges from declared contracts.
5. **Deprecate Manual Docs:** Link wiki pages to generated docs from code.

**Output:** Source-of-truth file list, CI automation, consumer discovery path (Swagger UI, catalog sync).

### Architecture Pattern Library

Common patterns published as reusable accelerators teams adopt without bespoke SA design.

1. **Identify Patterns:** Logging, API error format, auth middleware, DB layout, event envelope, K8s baseline, testing baseline.
2. **Package:** Starter repos, Helm charts, Terraform modules, archetypes.
3. **Document:** Quick-start, configuration, extension points, when *not* to use.
4. **Version & Govern:** Semver, changelog, deprecation policy; SA **or** LB curates, teams contribute.

**Pattern — API Error Format (RFC 7807):** All API errors MUST follow Problem Details with:
- `timestamp` — when the error occurred
- `status` — HTTP status code
- `error_code` — internal domain code (e.g., `ERR_USER_NOT_FOUND`)
- `message` — human-readable description
- `trace_id` — Datadog trace ID by default; OTel span ID when OTel is in effective stack

Map domain exceptions to precise 4xx codes (400, 401, 403, 404, 409). Never use 500 for validation failures or business logic violations.

**Pattern — Entity Baseline:** See `distributed-systems-architecture` for soft-delete entity rules (`created_at`, `updated_at`, `deleted_at`). Pattern library links to that skill; do not duplicate lifecycle policy here.

**Pattern — Testing (adapt to effective stack):** Default: JUnit 5 + Mockito; Testcontainers for PostgreSQL, Kafka, and Redis. 100% line and branch coverage unconditionally required per coverage gates in constitution-core.

**Output:** Pattern scope, accelerator location, self-service steps, customization boundaries.

### Deprecation Policy

1. **Additive first:** New fields optional; old fields retained until sunset.
2. **Semver:** Breaking changes require major version bump (`/api/v2/`).
3. **Catalogue sync:** Set `Status: Deprecated` with sunset date and replacement link.
4. **Contract versioning:** OpenAPI `deprecated: true` on fields; AsyncAPI event version in schema.
5. **Compulsory deprecation:** Requires ADR via `architecture-governance`.

### Architecture Fitness Functions

Define gate **thresholds** — SA **or** LB specifies what must pass; Builder authors pipeline YAML.

| Principle | Fitness Function | Threshold | On Failure |
| --- | --- | --- | --- |
| No cyclic deps | ArchUnit rule | Zero cycles | Block merge |
| Unit test coverage | JaCoCo (`mvn verify`) | 100% line + branch | Block merge |
| Code quality | SonarQube | Zero critical smells | Block merge |
| API contract | OpenAPI spec generation at build | Spec generated | Block merge |
| Integration parity | Testcontainers | PostgreSQL, Kafka, Redis | Block merge |
| Breaking API change | OpenAPI diff | No unapproved breaking changes | Block merge |

1. **Derive Principles:** From pattern-selection ADR, other ADRs, gold standards, and constitution.
2. **Adapt to topology:** Monolith — ArchUnit module boundaries; microservices — service boundary and contract rules per accepted pattern ADR.
3. **Define Thresholds:** As table above; add latency/error regression per `production-operations`.
3. **Implement:** ArchUnit, JaCoCo, SonarQube, OpenAPI generation, contract tests, OPA/Checkov.
4. **Integrate CI/CD:** Run on every PR; block merge on failure. Pipeline implementation is Builder scope (SA/LB define thresholds only).

### Team-Owned Service Catalogue

| Field | Content |
| --- | --- |
| Service Name | |
| Owning Team / Tech Lead | |
| Status | Active / Deprecated / Experimental |
| Dependencies | Upstream and downstream |
| API Spec | Link to OpenAPI |
| Runbook / SLAs | Links |

Prefer CI/CD or metadata pipelines to auto-sync from OpenAPI, IaC tags, or K8s labels.

## Artifact Outputs

| Artifact | Canonical path |
| --- | --- |
| Service map (logical → repo path) | `nwob-docs/architecture/service-map.md` |
| OpenAPI specs | `repositories/{service-name}/src/main/resources/swagger/{spec-file}.yaml` |
| AsyncAPI / event schemas | `repositories/{service-name}/src/main/resources/asyncapi/` (when in scope) |
| Catalogue metadata | Rows in `service-map.md` + pattern library or org catalogue sync |
| Fitness function definitions | Documented in design package; enforced in CI |

When linking to architecture or sequence diagrams from contracts or catalogue, reference **Mermaid** artifacts only — do not introduce PlantUML.

## Must NOT

- Write GitHub Actions or pipeline YAML (define thresholds only)
- Design frontend components or React/Svelte patterns
- Author `story-tasks.md` or full task bodies from this skill (SDD via `/define` / `/features`; annex + tasks via `co-design-solution` / `/orchestrate-design`)
- Treat OpenAPI authorship as SA-exclusive (LB is co-equal)
- Invoke reference `api-and-interface-design` or `ci-cd-and-automation` directly — patterns embedded here

## Constitution Compliance

**Mandatory:**

- RFC 7807 error payloads with `trace_id` in pattern library.
- 100% line and branch coverage per coverage gates in constitution-core.
- OpenAPI spec auto-generated at build/runtime per Contracts and quality in constitution-core.

**Default-overridable (constitution sections 2 and 5):**

- Schema migrations default to **Liquibase** for PostgreSQL; adapt when overridden.
- Entity baseline per `distributed-systems-architecture` when effective lifecycle is soft-delete.
- Per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "Wiki docs are good enough for API contracts" | Manual docs drift; code-as-documentation with CI validation is the single source of truth. |
| "100% coverage is unrealistic" | Constitution section 3 requires 100% line and branch coverage unconditionally; fitness functions enforce it. |
| "Teams can adopt patterns informally" | Unpublished patterns create inconsistency; pattern library enables self-service without SA bottleneck. |
| "I'll write the GitHub Actions workflow here" | SA/LB defines gate definitions; pipeline authoring is Builder scope. |
| "Only SA may write OpenAPI" | SA and LB are co-equal; either may author OpenAPI under `/contracts`. |

## Red Flags

- API contracts maintained only in wiki or Confluence, not as machine-readable code.
- JaCoCo or SonarQube fitness functions not blocking merge on failure.
- Service catalogue entries missing ownership, dependencies, or API spec links.
- Breaking API change without semver bump or deprecation ADR.

## Verification

- [ ] Pattern-selection ADR topology reflected in fitness functions and module/service boundaries?
- [ ] Contracts and infra defined as machine-readable code with CI validation?
- [ ] Hyrum's Law and additive-change policy documented for public APIs?
- [ ] Effective stack resolved; migration tool and Testcontainers targets match effective stack?
- [ ] RFC 7807 and entity baseline patterns link to distributed-systems skill?
- [ ] JaCoCo 100% coverage, SonarQube, and OpenAPI generation fitness functions defined?
- [ ] OpenAPI files written to `repositories/{service-name}/src/main/resources/swagger/` for every in-scope API?
- [ ] service-map.md updated with exact OpenAPI paths?
