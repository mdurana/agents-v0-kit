# Discovery: <Program Name>

<!-- Optional: record a preferred backend stack id (java, dotnet, node, python, go).
     Omit or delete this line if undecided; /v0-architecture binds the pack later. -->
Stack preference: dotnet

## Problem

Describe the current operational bottleneck, manual workflow, or business gap.
State who is impacted and what fails or degrades under current volume.

## Success metric

<!-- Use concrete numbers or ranges (e.g., "10-50 MB", "p95 under 250 ms").
     Avoid placeholder tokens: <...>, [...], TBD, TODO, FIXME, XX, XXX, __, ??? -->
- End-to-end processing completes in under 5 minutes for batch payloads of 10-50 MB.
- Zero unrecoverable record drops during schema validation and ingestion.

## Options

### Option 1: Monolithic synchronous ingestion service

Single service handling upload, validation, transformation, and reporting in-process.
- Pros: Simple initial deployment, single deployable unit.
- Cons: Long-running uploads block worker threads; tight coupling between ingestion and reporting.

### Option 2: Staged pipeline with asynchronous worker processing

Separate ingestion API and background worker pipeline with durable job state and versioned configuration.
- Pros: Isolates upload spikes from processing; supports both batch and scheduled ingestion cleanly.
- Cons: Requires job status tracking and idempotent retry handling.

## Chosen option

Option 2 (Staged pipeline with asynchronous worker processing), because it decouples payload upload from validation and supports incremental rollout of ingestion modes and reporting without re-architecting the core service.

## In scope

<!-- Every leaf bullet must belong to a single delivery horizon (Now, Next, or Later)
     and is copied verbatim into the roadmap.
     - Use flat bullets for standalone deliverables.
     - Use a parent category bullet with indented sub-bullets when grouping related use cases
       or splitting a capability across horizons (e.g., Now vs. Next vs. Later). -->
- Core schema validation and canonical record persistence
- Role-based operator dashboard for job status and error inspection
- **Ingestion Modes:**
  - Manual and scheduled CSV/JSON batch file upload
  - Near-real-time webhook and event-stream ingestion
- **Report Definition Lifecycle:**
  - Static pre-packaged compliance report generation
  - Self-service custom report builder and export templates
- **Ticketed Configuration Lifecycle:**
  - Create and validate configuration change tickets before activation
  - Approval workflow and immutable audit trail for configuration updates
  - One-click rollback to a previous approved ticket version

## Out of scope

- Native iOS and Android mobile applications
- Direct third-party ERP write-back integrations
- Legacy archive migration prior to fiscal year 2024