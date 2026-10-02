# Model routing matrix (agents-v0)

The kit routes by **role**. Each row lists the Cursor model ID for that role. Agent frontmatter carries `model:`; `scripts/validate-kit.sh` checks it against this matrix. Live model availability in Cursor is not verified.

Role IDs and defaults match `templates/.cursor/model-config.json.example` (copy to `.cursor/model-config.json` on the target repo).


| Role                 | Purpose                                                          | Cursor ID                                                  |
| -------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------- |
| **Plan**             | program planning, requirements, architecture                     | `claude-sonnet-5-5-high`                                   |
| **Build**            | services, BFF, frontend, tests, maintenance, release             | `composer-2.5[fast=false]`                                 |
| **Build (critical)** | units that hit a security-review trigger, and sagas or consumers | `claude-sonnet-5-5-high`                                   |
| **Review**           | code review and security review, independent of the Build role   | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| **Explore**          | repo exploration sub-tasks                                       | `glm-5p3-flash[reasoning=high]`                            |
| **Debug**            | runtime failure root-cause                                       | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| **Schemas**          | schema/unit-test sub-tasks                                       | `composer-2.5[fast=false]`                                 |
| **Docs**             | doc drafting sub-tasks                                           | `gemini-3.8-flash[reasoning_effort=high]`                  |
| **Documenter**       | brownfield onboard as-is documentation                           | `gemini-3.8-flash[reasoning_effort=high]`                  |
| **Orchestrator**     | `/v0-deliver`, `/v0-status`, `/v0-onboard` session routing       | `gemini-3.8-flash[reasoning_effort=high]`                  |
| **UX Designer**      | UX design                                                        | `gemini-3.8-flash[reasoning_effort=high]`                  |




## Task execution architecture

```mermaid
flowchart TD
    plan["Plan role — program planning, requirements, architecture"]
    build["Build role — multi-file diffs, terminal loops"]
    critical["Build (critical) — security-trigger and saga units"]
    review["Review role — code and security review"]
    schemas["Schemas sub-tasks — contracts and unit tests"]
    explore["Explore sub-tasks — repo mapping"]
    debug["Debug sub-tasks — stack isolation"]
    docs["Docs sub-tasks — doc drafting"]
    documenter["Documenter — onboard as-is"]
    orchestrator["Orchestrator — phase routing"]
    plan --> build
    plan --> critical
    plan --> schemas
    plan --> docs
    build --> debug
    build --> explore
    review --> build
    review --> critical
    orchestrator --> plan
    orchestrator --> build
    documenter --> explore
```





## Critical units

The Build role is a fast, inexpensive model. Some units are where a wrong answer is costly: authentication and authorization, uploads, public routes, sagas, and event consumers. A unit is **critical** when the requirements artifact lists a security-review trigger for it, or when the story implements a saga or a consumer (`implement-messaging`). `/v0-build` launches the build agent for a critical unit, and `/v0-maintain` the maintenance agent for a fix that touches one, with the **Build (critical)** row: pass the **Plan** model ID as the launch override. The agent file is unchanged. Other units stay on the Build role.

## Independence of the reviewers

A reviewer should not be the model that wrote the code. The Review role uses `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` (see `.cursor/model-config.json` `review`), not the Build model. The test author (`test-engineer`) stays on the Build role; the Review role judges its tests in the code review.

## Kit agent mapping (19 agents)


| Kit agent            | Role         | `model:` (Cursor)                                          |
| -------------------- | ------------ | ---------------------------------------------------------- |
| program-planner      | Plan         | `claude-sonnet-5-5-high`                                   |
| requirements-analyst | Plan         | `claude-sonnet-5-5-high`                                   |
| solution-architect   | Plan         | `claude-sonnet-5-5-high`                                   |
| ux-designer          | UX Designer  | `gemini-3.8-flash[reasoning_effort=high]`                  |
| codebase-documenter  | Documenter   | `gemini-3.8-flash[reasoning_effort=high]`                  |
| orchestrator         | Orchestrator | `gemini-3.8-flash[reasoning_effort=high]`                  |
| security-reviewer    | Review       | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| code-reviewer        | Review       | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| design-reviewer      | Review       | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| backend-engineer     | Build        | `composer-2.5[fast=false]`                                 |
| bff-engineer         | Build        | `composer-2.5[fast=false]`                                 |
| frontend-engineer    | Build        | `composer-2.5[fast=false]`                                 |
| test-engineer        | Build        | `composer-2.5[fast=false]`                                 |
| maintenance-engineer | Build        | `composer-2.5[fast=false]`                                 |
| release-manager      | Build        | `composer-2.5[fast=false]`                                 |
| explore-researcher   | Explore      | `glm-5p3-flash[reasoning=high]`                            |
| debug-investigator   | Debug        | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| schema-author        | Schemas      | `composer-2.5[fast=false]`                                 |
| docs-author          | Docs         | `gemini-3.8-flash[reasoning_effort=high]`                  |




## Skill-launched tasks (no agent file)


| Skill                               | Purpose                          | Cursor ID                                                  |
| ----------------------------------- | -------------------------------- | ---------------------------------------------------------- |
| spec-intake, bugfix-triage          | repo exploration                 | `glm-5p3-flash[reasoning=high]`                            |
| bugfix-triage                       | runtime failure root-cause       | `grok-4.7[context=500k,reasoning_effort=xhigh,fast=false]` |
| contract-first-design, quality-gate | schemas + single-file unit tests | `composer-2.5[fast=false]`                                 |
| ux-design                           | UX spec authoring                | `gemini-3.8-flash[reasoning_effort=high]`                  |
| doc-sync                            | doc drafting                     | `gemini-3.8-flash[reasoning_effort=high]`                  |




## Notes

- Chat-mode / picker models in Cursor cannot be enforced by the kit — agent frontmatter and command routing hold regardless of the picker.
- The Build (critical) override is applied by the launcher (`/v0-build`), not by a second agent file. The override ID is the `plan` value in `.cursor/model-config.json` when that file exists, otherwise the Plan row above.
- Copy `templates/.cursor/model-config.json.example` to `.cursor/model-config.json` to remap role IDs. `scripts/install.sh` rewrites each installed agent's `model:` from that file using `core/model-roles.tsv`. Env overrides: `KIT_MODEL_PLAN`, `KIT_MODEL_BUILD`, `KIT_MODEL_REVIEW`, `KIT_MODEL_EXPLORE`, `KIT_MODEL_DEBUG`, `KIT_MODEL_SCHEMAS`, `KIT_MODEL_DOCS`, `KIT_MODEL_DOCUMENTER`, and `KIT_MODEL_ORCHESTRATOR`. Kit source agents keep the IDs in this matrix.
- `/v0-deliver` prefers the `orchestrator` agent (Orchestrator role), which launches phase agents so role routing holds regardless of the picker.
- Rules and skills reference roles and `docs/agents-v0/model-routing-matrix.md`, not concrete model IDs in prose.

