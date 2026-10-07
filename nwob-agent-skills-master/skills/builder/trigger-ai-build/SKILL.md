---
name: trigger-ai-build
description: >-
  Gates on finalized SDD artifacts and design package, then directs AI-assisted
  implementation from documentation. Use when the user invokes /build, design is
  complete, validate-design-package has approved, and constitution-compliant
  build may begin.
---

# Trigger AI build

Gate on finalized SDD and an approved design package, then implement from documentation. Do not start from a partial spec. Do not vibe-code.

Boundaries: [builder-skill-boundaries.md](../../../references/rules/builder-skill-boundaries.md). Execution patterns: [build-execution-patterns.md](../../../references/rules/build-execution-patterns.md).

## When to use

- The design package from `orchestrate-design` is complete.
- Lead Builder `validate-design-package` has passed, or the user documented a waiver.
- The user requests implementation or the build phase.
- A Cursor execution plan overlay is needed after `validate-design-package`. Live todos live in `~/.cursor/plans/` only.

## Workflow

### Step 1: Confirm the SDD gate

Confirm that `nwob-docs/sdd/epic-spec.md` exists with a finalized backlog index (chronological story order).

Confirm that in-scope `{stories_dir}/{STORY_ID}/story-spec.md` (product + technical annex) and `{stories_dir}/{STORY_ID}/story-tasks.md` files exist with full task bodies. Confirm those tasks trace to stories indexed in `epic-spec.md` (via `story-spec.md`).

If `epic-spec.md` or the backlog index is missing or incomplete, stop. Route to the matching Product Owner skill. If `story-spec.md` or `story-tasks.md` is missing or incomplete, stop. Route to `co-design-solution`. If the design package is incomplete, stop. Route to `orchestrate-design`.

### Step 2: Confirm the design package

Confirm architecture artifacts are present: ADRs, `architecture.md`, `service-map.md`, OpenAPI files at `repositories/{service-name}/src/main/resources/swagger/`, catalogue entries.

Confirm that `repositories/` exists. If it is missing, run `nwob doctor`.

Confirm the design package matches effective stack and effective data lifecycle per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

If design drift or gaps appear, stop. Route to `orchestrate-design` or the matching SA skill.

### Step 3: Confirm Lead Builder sign-off

Confirm `validate-design-package` passed with design-approved for build.

If validation was skipped, require an explicit user waiver with documented risk in chat. Do not proceed on Lead Builder self-assessment alone.

### Step 4: Create the execution plan overlay

After Step 3, not before:

1. Copy [templates/lb/execution-plan-template.md](../../../templates/lb/execution-plan-template.md) into `~/.cursor/plans/` as live YAML todos. Do not persist a copy under `nwob-docs/`.
2. Every YAML todo must cite a `story-tasks.md` ID from the story annex (in `story-spec.md`) and matching body in `story-tasks.md`. This plan overlays `story-tasks.md`. It does not replace it. Use `epic-spec.md` backlog index for cross-story order when needed.
3. One todo is one `trigger-ai-build` turn and one `review-implementation` verdict. If the user groups 2 or 3 `story-tasks.md` items, still produce a verdict per ID.
4. Load [git-delivery-standards.md](../../../references/rules/git-delivery-standards.md) when suggesting conventional commit messages or branch names. Branch regex comes from `constitution-custom.mdc`. Do not draft MR title or body here. Session 4 `raise-merge-request` follows [merge-request-patterns.md](../../../references/rules/merge-request-patterns.md).

### Step 5: Load context

Apply the context hierarchy in [build-execution-patterns.md](../../../references/rules/build-execution-patterns.md):

1. Load rules: constitution, `AGENTS.md`, project `.cursor/rules/`, including `constitution-custom.mdc` when that file is present.
2. Load `nwob-docs/sdd/epic-spec.md` (backlog index) for orientation. Load `{stories_dir}/{STORY_ID}/story-spec.md` for Gherkin and technical annex; load `{stories_dir}/{STORY_ID}/story-tasks.md` for official task IDs and bodies. Gherkin and official task IDs win over overlays.
3. Load `{stories_dir}/{STORY_ID}/story-spec.md` (technical annex), then the Cursor plan under `~/.cursor/plans/`. Both sit below `story-spec.md` and `story-tasks.md`.
4. Load `nwob-docs/architecture/architecture.md`, `service-map.md`, relevant ADRs, and OpenAPI files from paths in service-map for the active scope.
5. For the current task only, load files listed in that `story-tasks.md` item plus the linked `story-spec.md` Gherkin AC.
6. Apply effective stack and data lifecycle from resolved sources. Do not infer undocumented overrides.

Do not load `references/agent-skills-main/skills/context-engineering` or `source-driven-development` when the embed applies.

### Step 6: Execute one increment

Apply the increment cycle in build-execution-patterns.

Work through the active story's `story-tasks.md` in strict order. Respect dependencies and chronological story sequencing from the `epic-spec.md` backlog index.

For each task, when behavior changes: RED, then GREEN, then REFACTOR. Constitution requires 100% meaningful coverage. Testcontainers applies on Java. That overrides the reference ~80% pyramid.

Implement one task at a time. Run the verify command from the task entry. After a significant increment, run the platform verify: `mvn clean verify` on Java, `xcodebuild test` on iOS, `./gradlew test` on Android.

Route to Lead Builder `review-implementation` after each increment. Do not advance until the increment is approved.

AI implements within documented artifacts only. Cursor todos must not invent work missing from `story-tasks.md`.

If UI stories are in scope, follow the frontend branch in build-execution-patterns. Use SwiftUI, Compose, or React/Svelte per `constitution-custom.mdc`. Do not assume React or Svelte.

### Step 7: Enforce quality gates

Per [constitution-core.mdc](../../../rules/constitution-core.mdc) and project rules:

1. 100% meaningful coverage on the measured scope. Testcontainers for Java integration tests; N/A on iOS/Android.
2. RFC 7807 error format on APIs; N/A for client-only clones.
3. Checkstyle, PMD, SpotBugs on Java; N/A on iOS/Android. Java increments also follow SonarQube guidance in [implementation-quality-standards.md](../../../references/rules/implementation-quality-standards.md).
4. Stateless K8s on backend. No pod-local state. N/A for client-only clones.
5. OpenAPI contracts where APIs are in scope (origin from `constitution-custom.mdc`).

### Step 8: Stop when a gate fails

If artifacts are missing, design drift appears, quality gates fail, or Lead Builder gates fail, stop implementation.

Route to Lead Builder `orchestrate-design`, the matching SA skill, a PO skill, or Lead Builder `review-implementation`. Do not patch forward without documented alignment. Do not infer architecture, stack, or data lifecycle that is not in the sources.

### Step 9: Hand off after the last increment

After all `story-tasks.md` items for the active story complete, route to Builder `raise-merge-request` (Session 4). That skill drafts MR title, body, and branch names from merge-request-patterns only. The human opens the MR in GitLab. Do not commit, push, draft the MR body here, or self-audit.

After the human opens the MR, a **peer** developer runs Lead Builder `audit-and-approve-code` (`/audit`) on `MR_BRANCH` before external QA. The Sessions 1–4 author must not self-audit. Do not declare the build complete until audit passes, or until the user documents a waiver.

## Constitution compliance

Mandatory: SDD build gate (`epic-spec.md` + in-scope `story-spec.md` + `story-tasks.md`; story order from epic-spec backlog index). Pre-build and per-increment gates. Ordered `story-tasks.md` execution. 100% meaningful coverage. Java: Testcontainers, Checkstyle, PMD, SpotBugs, `mvn`. iOS: XCTest/`xcodebuild`. Android: Gradle. RFC 7807 on APIs. Stateless K8s on backend.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Implementation must use effective constraints from sources.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| SDD is mostly done. We can start coding | Constitution forbids implementation without finalized `epic-spec.md`, in-scope `story-spec.md`, and `story-tasks.md` (order from epic-spec backlog index). |
| We can fill in tasks during build | `story-tasks.md` must exist before build. Ad-hoc tasks are untraceable. |
| AI can infer the architecture | Undocumented architecture produces drift and ARC violations. |
| We will add tests at the end | 100% meaningful coverage is mandatory. Platform harnesses run from the start. |
| This story is small enough to skip the gate | No exception for scope size. |
| Reference TDD pyramid allows 80% unit tests | 70/20/10 is a mix hint. The numeric gate is 100% meaningful coverage. |
| Skip `review-implementation` for this increment | Per-increment sign-off is required before the next task. |
| The Cursor plan replaces `story-tasks.md` | The execution plan overlays `story-tasks.md`. Every YAML todo cites a `story-tasks.md` ID. |
| Write the execution plan under `nwob-docs/sdd/` | The live overlay is `~/.cursor/plans/` only. |
| Execute from epic-spec index alone | Bodies and verify commands live in per-story `story-tasks.md`. |

## Red flags

- Implementation started without `epic-spec.md`, in-scope `story-spec.md` + `story-tasks.md`, or `validate-design-package` approval.
- Tasks executed out of order, or without traceability to `epic-spec.md` backlog index stories.
- Full codebase loaded into context instead of the current task file set.
- Quality gates skipped or deferred.
- Stack or data lifecycle chosen during build without documentation in sources or ADRs.
- Design package ignored. AI invents architecture not in `nwob-docs/architecture/`.
- MR sent to QA without `audit-and-approve-code`.
- Execution plan written under `nwob-docs/` or used as the task list instead of `story-tasks.md`.

## Verification

- [ ] `nwob-docs/sdd/epic-spec.md` with backlog index present and finalized?
- [ ] In-scope `story-spec.md` (with annex) and `story-tasks.md` present with full bodies?
- [ ] `validate-design-package` passed, or user waiver documented?
- [ ] Execution plan in `~/.cursor/plans/` with every YAML todo citing a `story-tasks.md` ID?
- [ ] Design package under `nwob-docs/architecture/` reviewed and aligned with effective constraints?
- [ ] All `story-tasks.md` items completed in order with `review-implementation` per increment?
- [ ] 100% meaningful coverage on the measured scope, with Java Testcontainers where applicable?
- [ ] RFC 7807 on APIs; Java static analysis (Checkstyle, PMD, SpotBugs) or mobile N/A?
- [ ] No undocumented stack or data lifecycle overrides introduced during build?
- [ ] Platform verify passes (`mvn clean verify`, `xcodebuild test`, or `./gradlew test`)?
- [ ] `audit-and-approve-code` passed before QA handoff?
