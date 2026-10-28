# Roadmap: finance-back-office-portal

Discovery: user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md (sha256: 76f926b5d668198946d0739e3029a89b3610275df749b33883a2397c479b5022)

## Problem

Finance teams frequently handle heterogeneous, high-volume financial inputs (e.g., funding costs, merchant settlements, partner billing, fee reconciliations) that must be transformed into strictly formatted enterprise outputs (such as SAP-compliant CSVs) under strict regulatory scrutiny. Today, these operations suffer from structural operational limitations:

* **Siloed Point Solutions & Tool Proliferation:** Without a standardized operational platform, every new financial workflow requires either a standalone engineering project or fragile desktop spreadsheet macros, creating technical debt and operational silos across back-office desks.  
* **Engineering Bottlenecks for New Business Models:** Introducing new partner schemes, promotional commission matrices, or ad-hoc reconciliation reports requires developer code cycles to alter data models, delaying time-to-market for business initiatives.  
* **Operational Integrity & Audit Vulnerabilities:** Ad-hoc transformation scripts lack automated validation against reference tables, immutable run histories, and deterministic exception logging, increasing the risk of calculation discrepancies reaching general ledgers.  
* **Inconsistent Governance & Maker-Checker Gaps:** Multi-department financial operations lack a unified Segregation of Duties (SoD) framework, permitting single-operator mutations and untracked report generation across unmonitored channels.  
* **Configuration Drift During In-Flight Cycles:** Dynamic parameters (recipes, lookup grids, schedules) lack staging lifecycles and runtime execution locks, exposing in-flight calculations to runtime corruption.

While the immediate operational need is transforming the **Funding Cost Summary into five standard SAP commission reports (MVP)**, the underlying business problem is the absence of an extensible, multi-tenant financial operations console capable of onboarding future financial ingestion, reconciliation, and posting use cases.

## Success metric

| Dimension | Metric | Target |
| :---- | :---- | :---- |
| **Pipeline Performance** | End-to-end transformation latency | < 60 minutes from job trigger to draft CSV and exception artifact availability (standard files of a couple of < 50 MB, up to max row limits). |
| **Extensibility & Onboarding** | Time-to-onboard new report use case | Reduced from 2–3 developer sprints to < 2 hours for business analysts using the Report Builder and ticketed governance. |
| **Maker-Checker Compliance** | Audit-governed posting rate | 100% of generated SAP and enterprise ledger postings backed by an approved SAP_REPORT_POSTING ticket. |
| **Runtime Configuration Safety** | In-flight execution collision rate | 0 configuration cutovers executed while targeted definitions have jobs in JOB_QUEUED or RUNNING status. |
| **Platform Authorization & SoD** | Unauthorized API access rate | 0% unmapped route access (fail-closed); 100% adherence to production SoD conflict matrices across all roles and actions. |
| **Data Governance & Retention** | Online audit log retention | 100% immutable retention of system mutations, access requests, and recipe publishes stored online for 13 months. |

## Chosen option

**Option 3: Extensible Finance Back Office Portal with Pluggable Engines & Built-in Report Builder**  
Option 3 satisfies the operational requirements of the Funding Cost Summary MVP while solving the broader enterprise problem of financial operational scaling. By treating report transformations, lookup dependencies, and approval routing as modular, configuration-driven entities, the platform handles the 5 seeded commission reports on day one while empowering finance teams to define, test, and deploy new financial operational pipelines through governed, ticketed self-service.

## Now

**1. MVP Implementation: Funding Cost Summary Pipeline**

* **Seeded Definitions:** Five standard commission report types: *Cashout Offline*, *Cashout Online*, *Cashin Offline*, *Cashin Online*, and *Real Time*.  
* **Operational Constraints:** Upload-only source ingestion for MVP, source files of a couple of < 50 MB, platform-wide Asia/Manila timezone, and mandatory report period format (YYYY-MM) for the previous calendar month.  
* **Execution Lifecycle:** Preparer selects definition, uploads source CSV, and initiates run; returns HTTP 202; job cycles through JOB_QUEUED, RUNNING, to terminal states SUCCESS, FAILED, or CANCELLED.  
* **Engine Safeguards:** Execution of approved, active JSON recipes, runtime row/timeout limits, and deterministic exceptions file generation on rule failure.  
* **Artifact Inspection:** In-portal draft preview, draft SAP CSV download, exceptions file download, full-text run filtering, and persistent run detail views.  
* **Downstream Handoff:** Endorsement creates an SAP_REPORT_POSTING ticket; approval archives the file in the designated bucket (with _v2 / timestamp collision handling) and records the event via a log-only SAP connector; rejection/cancellation closes the ticket without invalidating the SUCCESS run.

**3. Pluggable Ingestion & Schedule Architecture (MVP Upload & Scheduling)**

* **Ingestion Modes:** Current delivery is UPLOAD_ONLY.  
* **Schedule Governance:** Admin management of automated run frequencies; updates require SCHEDULE_CHANGE tickets with mandatory cron warning acknowledgments.  
* **Seeded Monthly Run:** Seeded Funding Cost definitions run on the 1st day of each month (Asia/Manila) and ingest the previous month's uploaded data.  
* **Runtime Execution Freeze:** Immediate lock on ticket approvals when targeted report definitions have runs in JOB_QUEUED or RUNNING status.  
* **Effective Timing:** Precise effective_at hour scheduling in Asia/Manila, blocking invalid, locked, or next-schedule windows.

**4. Configuration Management & Reference Data (MVP Seeded Definitions & Lookups)**

* **Managed Lookups:** Dedicated UI to create, version, upload by CSV-import, and inline-grid-edit reference tables used by transformation recipes.  
* **Ticketed Configuration Lifecycle:**  
  * REPORT_DEFINITION_CREATE & REPORT_DEFINITION_CHANGE (seeded reports in the Funding Cost pipeline)  
  * RECIPE_VERSION_PUBLISH  
  * REFERENCE_TABLE_CREATE & REFERENCE_TABLE_CHANGE  
  * SCHEDULE_CHANGE

**5. Universal Governance & Ticketing System**

* **Queue Views:** **To Do**, **My Requests**, **All**, and **Manage** (admin).  
* **Ticket Metadata:** Ticket \#, Type, Title, Requester, Date Modified, Date Created, and Status (PENDING_APPROVAL, APPROVED, REJECTED, CANCELLED).  
* **Ticket Actions & Auditing:** Approve, reject, cancel (maker or admin), reassign, change owner, comment, file attachment, and direct artifact downloads (source, preview, draft, archive, exception files).  
* **Cross-Domain Orchestration:** Unified workflow schema governing operational postings, configuration changes, and access provisioning.

**6. Identity and Access Management (IAM)**

* **Authentication & Session Management:** Google OIDC via BFF in production (mock login for local/test); Redis-backed httpOnly session cookies configured to fail-closed on cache unavailability.  
* **Fine-Grained RBAC:** Explicit operation-to-permission mapping denying all unregistered endpoints; full role and permission CRUD with soft-delete revival.  
* **User Management & Directory:** User filtering, role assignments with optional expiry, self-lock protection, and directory lookups (Google Workspace in prod; mock directory locally).  
* **Self-Service Onboarding:** Zero-role landing view directing users to "Role Apply" to submit an IAM_ROLE_APPLICATION ticket.  
* **Security Controls:** Segregation of Duties (strict in prod; relaxed in non-prod), administrative "View As" permission overlay/clearance, and user/role CSV access review exports.

**7. Audit, Notifications, and Shell UI**

* **Audit Logging:** Append-only, 13-month online retention logging workspace emails, event types, search queries, and expandable JSON mutation payloads.  
* **Shell UX:** GCash design token implementation; dynamic navigation menus filtered by permission sets; RFC 7807 problem detail modals with correlation IDs.  
* **Dashboard & Alerts:** In-app notification bell with asynchronous local SMTP email delivery; empty-state Dashboard UI backed by widget APIs (my_open_runs, recent_runs, my_todo_count, awaiting_approval, failed_scheduled_jobs).

## Next

**3. Pluggable Ingestion & Schedule Architecture (S3 Integration)**

* **Ingestion Modes:** S3_POLL and S3_OR_UPLOAD are the next integration; the minute scheduler and S3 polling stay dormant behind app.scheduler.enabled until then.

## Later

**2. Extensible Report Builder & Custom Financial Use Cases**

* **Later Onboarding:** Other report use cases are added later through this Report Builder. They are not part of the five seeded Funding Cost definitions.  
* **Visual Schema & Mapping Designer:** Operator UI to configure arbitrary tabular input schemas, define column data types, enforce field constraints, and map input attributes to target output formats.  
* **Declarative Expression Engine:** Low-code formula canvas supporting row-level arithmetic, string manipulations, conditional logic (IF/THEN/ELSE), date formatting, and relational joins against reference tables.  
* **Multi-Domain Use Case Expansion:** Capabilities to support operational financial pipelines beyond funding costs, including:  
  * Merchant fee calculations and commission reconciliations.  
  * Marketing campaign cash payouts and incentive distribution extracts.  
  * Partner billing dispute audits and discrepancy isolation files.  
  * Ad-hoc operational accounting extracts and custom GL summaries.  
* **Pre-Flight Sandbox Harness:** Interactive dry-run environment allowing operators to test custom definitions with sample files, inspect line-by-line calculation traces, and validate formulas before submitting tickets.  
* **Recipe Versioning:** Compilation of builder configurations into immutable JSON recipe versions submitted via RECIPE_VERSION_PUBLISH tickets.

**4. Configuration Management & Reference Data (Custom Report Definitions)**

* **Ticketed Configuration Lifecycle:**  
  * REPORT_DEFINITION_CREATE & REPORT_DEFINITION_CHANGE (custom reports added later through the Report Builder)

## Out of scope

* **Transactional ERP Ledger Mutations:** Direct bidirectional writing to SAP financial ledgers via RFC/BAPI (the SAP connector is strictly log-only; actual ledger ingestion relies on downstream systems consuming archived CSVs).  
* **Non-MVP Production Financial Pipelines:** Production execution of non-funding-cost pipelines at initial launch (the platform provides the extensible engine and builder, but live pipelines are limited to the MVP Funding Cost Summary definitions until subsequent rollouts).  
* **Arbitrary SQL / Direct DB Execution:** User-supplied, unparsed SQL querying against core production transactional databases (all builder workflows execute strictly via validated, sandboxed JSON recipes).  
* **BI Visualizations & Graphical Dashboards:** Drag-and-drop analytics charts, pivot tables, and BI metrics (the platform focuses on data transformation, validation, and tabular CSV generation; dashboard widgets are limited to operational counts and empty-state placeholders).  
* **Real-Time Event Stream Processing:** Sub-second event ingestion (e.g., Apache Kafka / Apache Flink streaming); transformations are triggered via batch file uploads or S3 object drops.  
* **Multi-Region Timezone Conversions:** Support for multi-region runtime conversions (all system scheduling, effective dates, and transformations remain fixed to Asia/Manila).  
* **Mobile Form Factors:** Native mobile applications (iOS/Android) or dedicated responsive mobile layouts (optimized strictly for desktop finance operator environments).

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| roadmap | docs/agents-v0/roadmap/finance-back-office-portal.md, user-requirements/Finance-Back-Office-Portal-Discovery-Requirements.md | mdurana | Approved | 2026-10-28 |

> The `roadmap` row covers the sequence. The discovery file has no kit approval row.
> `/v0-architecture` runs next and does not write stories. `/v0-plan` then reads this file and does not add a theme it does not name.
