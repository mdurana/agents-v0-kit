# agent-skills-main → nwob Mapping

Maps reference skills in [references/agent-skills-main](../agent-skills-main/skills/) to nwob personas and skills. **Do not** import reference skills as parallel workflows when an nwob skill or embed already covers the intent.

Persona boundaries: Product Owner — [product-owner-skill-boundaries.md](product-owner-skill-boundaries.md); Solution Architect — [solution-architect-skill-boundaries.md](solution-architect-skill-boundaries.md), [solution-architect-command-standards.md](solution-architect-command-standards.md); Lead Builder — [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md); Builder — [builder-skill-boundaries.md](builder-skill-boundaries.md); Observer — [observer-skill-boundaries.md](observer-skill-boundaries.md).

---

## Define phase

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `interview-me` | **Embed** | `/problem` — [intent-interview-patterns.md](intent-interview-patterns.md) |
| `idea-refine` | **Embed** | `/ideate` — [ideation-frameworks.md](ideation-frameworks.md) |
| `spec-driven-development` | **Exclude** | PO chain: `/problem` → `/ideate` → `/roadmap` → `/features`; Builder: `co-design-solution` → `story-tasks.md`; LB: `orchestrate-design` → `story-tasks.md`. Do not invoke as SA skill. |

## Plan phase

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `planning-and-task-breakdown` | **Embed** | Vertical slicing → `/features`; implementation tasks → [task-breakdown-patterns.md](task-breakdown-patterns.md) in `co-design-solution` |
| `doubt-driven-development` | **User-orchestrated** | Optional checkpoint in [builder-skill-boundaries.md](builder-skill-boundaries.md) and [lead-builder-skill-boundaries.md](lead-builder-skill-boundaries.md); not embedded in LB/Builder skills |

## Build phase

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `incremental-implementation` | **Embed** | [build-execution-patterns.md](build-execution-patterns.md) in Builder `trigger-ai-build` |
| `test-driven-development` | **Embed** | Builder `trigger-ai-build` via [build-execution-patterns.md](build-execution-patterns.md); validated by Lead Builder `review-implementation` / `audit-and-approve-code` |
| `source-driven-development` | **Embed** | [build-execution-patterns.md](build-execution-patterns.md) in `trigger-ai-build`; contracts → SA `architecture-delivery-enablement` |
| `frontend-ui-engineering` | **Embed** | Frontend branch in [build-execution-patterns.md](build-execution-patterns.md) during `trigger-ai-build` — not SA |
| `api-and-interface-design` | **Embed** | SA `architecture-delivery-enablement` + `distributed-systems-architecture` |
| `code-simplification` | **Embed** | [builder-quality-patterns.md](builder-quality-patterns.md) in `audit-and-approve-code` |
| `deprecation-and-migration` | **Embed** | SA `architecture-governance` + `architecture-delivery-enablement`; Builder implements migration |

## Verify phase

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `code-review-and-quality` | **Embed** | [builder-quality-patterns.md](builder-quality-patterns.md) in `review-implementation`, `audit-and-approve-code` |
| `browser-testing-with-devtools` | **Align** | Builder optional E2E — [builder-quality-patterns.md](builder-quality-patterns.md) |
| `debugging-and-error-recovery` | **Embed** | [builder-quality-patterns.md](builder-quality-patterns.md) in `review-implementation` |
| `performance-optimization` | **Borrow** | SA SLOs/budgets → `production-operations`; code fixes → [builder-quality-patterns.md](builder-quality-patterns.md) |
| `security-and-hardening` | **Borrow** | SA platform/policy → SA skills; impl controls → [builder-quality-patterns.md](builder-quality-patterns.md) |

## Ship phase

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `shipping-and-launch` | **Borrow** | SA `production-operations` (go-live checklist) — not PO |
| `ci-cd-and-automation` | **Borrow (gates only)** | SA `architecture-delivery-enablement` (fitness thresholds); Lead Builder/Builder authors pipeline YAML |
| `git-workflow-and-versioning` | **Align** | Law: [git-delivery-standards.md](git-delivery-standards.md). Draft schema: [merge-request-patterns.md](merge-request-patterns.md) (`raise-merge-request`; human opens/updates MR). Hygiene: [builder-quality-patterns.md](builder-quality-patterns.md) in `audit-and-approve-code` |

## Cross-cutting

| Reference skill | nwob action | nwob target |
|-----------------|-------------|-------------|
| `using-agent-skills` | **Borrow** | [AGENTS.md](../../AGENTS.md) orchestration + persona docs |
| `context-engineering` | **Embed** | Context hierarchy in [build-execution-patterns.md](build-execution-patterns.md); session setup via Cursor rules / skills config |
| `documentation-and-adrs` | **Embed** | SA `architecture-governance` |

---

## Solution Architect disposition summary

| Reference skill | SA action |
|-----------------|-----------|
| `documentation-and-adrs` | Embed → `architecture-governance` |
| `api-and-interface-design` | Embed → `architecture-delivery-enablement`, `distributed-systems-architecture` |
| `deprecation-and-migration` | Embed → `architecture-governance`, `architecture-delivery-enablement` |
| `performance-optimization` | Borrow SLO/budget patterns → `production-operations`; N+1/caching → `distributed-systems-architecture` |
| `security-and-hardening` | Borrow platform tier → `distributed-systems-architecture`; policy patterns → `architecture-delivery-enablement` |
| `ci-cd-and-automation` | Borrow gate definitions → `architecture-delivery-enablement` |
| `shipping-and-launch` | Borrow go-live gates → `production-operations` |
| `spec-driven-development` | **Exclude** — PO + Lead Builder own SDD |
| `frontend-ui-engineering` | **Exclude** — Builder `trigger-ai-build` only |
| `planning-and-task-breakdown` | **Route** — `/features` + `co-design-solution` |

---

## Builder disposition summary

| Reference skill | Builder action |
|-----------------|----------------|
| `code-review-and-quality` | Embed → [builder-quality-patterns.md](builder-quality-patterns.md) in `review-implementation`, `audit-and-approve-code` |
| `debugging-and-error-recovery` | Embed → `builder-quality-patterns.md` in `review-implementation` |
| `code-simplification` | Embed → `builder-quality-patterns.md` in `audit-and-approve-code` |
| `git-workflow-and-versioning` | Align → law [git-delivery-standards.md](git-delivery-standards.md); draft schema [merge-request-patterns.md](merge-request-patterns.md) in `raise-merge-request` and `resolve-review-comments` (no GitLab CLI); MR hygiene in `audit-and-approve-code` |
| `browser-testing-with-devtools` | Align → optional E2E in `builder-quality-patterns.md` |
| `performance-optimization` | Borrow code tier → `review-implementation` / `audit-and-approve-code` |
| `security-and-hardening` | Borrow impl tier → `review-implementation` / `audit-and-approve-code` |
| `deprecation-and-migration` | Align — SA decides; Builder executes migration tasks |
| `doubt-driven-development` | User-orchestrated only — does not replace Builder gates |
| `incremental-implementation` | **Exclude** — Builder `trigger-ai-build` |
| `test-driven-development` | **Exclude** — Builder `trigger-ai-build`; Builder validates outcomes |
| `source-driven-development` | **Exclude** — Builder `trigger-ai-build` |
| `frontend-ui-engineering` | **Exclude** — Builder `trigger-ai-build` |
| `planning-and-task-breakdown` | **Embed** → [task-breakdown-patterns.md](task-breakdown-patterns.md) in `co-design-solution` |

---

## PO-specific rules

1. Never write to `docs/ideas/` or `docs/intent/` — use `nwob-docs/sdd/` and `nwob-docs/presentations/`.
2. Never collapse `epic-spec.md` backlog index (PO stories) and `story-tasks.md` / `story-tasks.md` into one artifact.
3. Reference "ideate" triggers route to nwob `/ideate`, not reference `idea-refine` skill file.

## Lead Builder-specific rules

1. Never author product stories or Gherkin AC in `story-tasks.md` without traceability to `epic-spec.md` backlog index.
2. Never collapse `epic-spec.md` backlog index and `story-tasks.md` / `story-tasks.md` into one artifact.
3. Never invoke reference skills directly when an embed exists — use [task-breakdown-patterns.md](task-breakdown-patterns.md) and [build-execution-patterns.md](build-execution-patterns.md).
4. Never start `trigger-ai-build` without Lead Builder `validate-design-package` sign-off (or documented user waiver).
5. `doubt-driven-development` is user-orchestrated only — LB/Builder personas do not spawn adversarial reviewers.
6. Never store architecture in `docs/` — use `nwob-docs/architecture/` per [sdd-artifact-layout.md](sdd-artifact-layout.md).

## Builder-specific rules

1. Never invoke reference skills directly when an embed exists — use [builder-quality-patterns.md](builder-quality-patterns.md).
2. Never author `story-tasks.md` except from `co-design-solution`; never author `story-tasks.md` except from `orchestrate-design`. Never author ADRs or OpenAPI contracts.
3. Never orchestrate `orchestrate-design` or `trigger-ai-build` — co-design and gate only.
4. Never store architecture in `docs/architecture.md` — use `nwob-docs/architecture/` per [sdd-artifact-layout.md](sdd-artifact-layout.md).
5. `doubt-driven-development` is user-orchestrated only — Builder personas do not spawn adversarial reviewers.

## SA-specific rules

1. Never author `epic-spec.md`, `epic-spec.md` backlog index, or `story-tasks.md` / `story-tasks.md` — read for constraints only.
2. Never store ADRs in `docs/adr/` — use `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md`.
3. Never invoke reference SA-related skills directly when nwob SA skill covers intent.
4. Never write pipeline YAML or application code in SA skills — define thresholds and patterns only.
