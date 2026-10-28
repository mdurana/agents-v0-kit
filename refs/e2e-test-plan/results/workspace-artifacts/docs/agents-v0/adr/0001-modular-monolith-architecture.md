# ADR 0001: Modular Monolith with Asynchronous Recipe Worker

- Status: Accepted
- Deciders: mdurana
- Date: 2026-10-28
- Pack: java

## Context

The Finance Back Office Portal must support 5 seeded Funding Cost Summary SAP commission report transformations at MVP launch while providing governed lookup tables, maker-checker ticketing (`SAP_REPORT_POSTING`, `RECIPE_VERSION_PUBLISH`, `REFERENCE_TABLE_CHANGE`, `SCHEDULE_CHANGE`), RBAC with Segregation of Duties (SoD), and an immutable 13-month audit log.

## Patterns considered

| Dimension | Option A: Modular Monolith + Async Worker (`java` + `react`) | Option B: Distributed Microservices Mesh |
|-----------|-------------------------------------------------------------|------------------------------------------|
| **Cost** | Single deployable backend + SPA + relational DB + session cache; minimal infrastructure footprint. | High infrastructure and operational overhead (service mesh, per-service DBs, distributed tracing). |
| **Security** | Single fail-closed BFF/API boundary, unified RBAC & SoD enforcement, transactional audit logging. | Multiple network hops requiring mTLS, token propagation, and cross-service SoD synchronization. |
| **Reliability** | ACID database transactions across ticket approvals, runtime execution locks, and recipe version cutovers. | Eventual consistency risks between ticketing, lookup tables, and job execution locks. |
| **Operability** | Single build/verify pipeline (`./mvnw -B clean verify -Pci-security`), straightforward container deployment. | Complex multi-repo orchestration and cross-service contract coordination for a single team. |

## Alternatives considered

- **Option B (Distributed Microservices Mesh)**: Rejected for MVP because transactional consistency between maker-checker tickets, runtime execution locks (`JOB_QUEUED` / `RUNNING`), and lookup table versions is simpler and safer inside a single modular monolith with clear package boundaries.

## Decision

Adopt **Option A: Modular Monolith with Asynchronous Recipe Worker** using `Pack: java` (Java 21 / Spring Boot 3.4 backend + React 19 TypeScript Vite SPA, PostgreSQL 17, Flyway migrations).
