# Model routing matrix (agents-v0)

The kit routes by **role**, not by vendor. Each row lists the model ID per platform. Provider-qualified Kilo IDs are examples — adapt them to your `kilo.json` providers (`kilo`, `anthropic`, `openrouter`, `google`, ...). Claude Code uses model aliases. The agent frontmatter carries all three (`model:`, `model_kilo:`, `model_claude:`) and each tool's adapter emits its own.


| Role        | Purpose                                                | Cursor ID                | Kilo ID (`provider/model`)           | Claude Code |
| ----------- | ------------------------------------------------------ | ------------------------ | ------------------------------------ | ----------- |
| **Plan**    | requirements, architecture, UX design, security review | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`    |
| **Build**   | services, BFF, frontend, tests, maintenance, release   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`    |
| **Review**  | code review                                            | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`    |
| **Explore** | repo exploration sub-tasks                             | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `haiku`     |
| **Debug**   | runtime failure root-cause                             | `grok-4.7-xhigh`         | `x-ai/grok-4.7`                | `sonnet`    |
| **Schemas** | schema/unit-test sub-tasks                             | `composer-2.5`           | `z-ai/glm-5.3-flash` | `sonnet`    |
| **Docs**    | doc drafting sub-tasks                                 | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `haiku`     |


## Task execution architecture

```mermaid
flowchart TD
    plan["Plan role — system design, requirements, security review"]
    build["Build role — multi-file diffs, terminal loops"]
    review["Review role — code review"]
    schemas["Schemas sub-tasks — contracts and unit tests"]
    explore["Explore sub-tasks — repo mapping"]
    debug["Debug sub-tasks — stack isolation"]
    docs["Docs sub-tasks — doc drafting"]
    plan --> build
    plan --> schemas
    plan --> docs
    build --> debug
    build --> explore
    review --> build
```



## Kit agent mapping (16 agents)


| Kit agent            | Role    | `model:` (cursor)        | `model_kilo:`                        | `model_claude:` |
| -------------------- | ------- | ------------------------ | ------------------------------------ | --------------- |
| requirements-analyst | Plan    | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |
| solution-architect   | Plan    | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |
| ux-designer          | Plan    | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |
| security-reviewer    | Plan    | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |
| code-reviewer        | Review  | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |
| backend-engineer     | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| bff-engineer         | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| frontend-engineer    | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| test-engineer        | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| maintenance-engineer | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| release-manager      | Build   | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `sonnet`        |
| explore-researcher   | Explore | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `haiku`         |
| debug-investigator   | Debug   | `grok-4.7-xhigh`         | `x-ai/grok-4.7`                | `sonnet`        |
| schema-author        | Schemas | `composer-2.5`           | `z-ai/glm-5.3-flash` | `sonnet`        |
| docs-author          | Docs    | `composer-2.5`           | `z-ai/glm-5.3-flash`                 | `haiku`         |
| orchestrator         | Plan    | `claude-sonnet-5-5-high` | `anthropic/claude-sonnet-5.5`   | `sonnet`        |


## Skill-launched tasks (no agent file)


| Skill                               | Purpose                          | Cursor ID        | Kilo ID                              | Claude Code |
| ----------------------------------- | -------------------------------- | ---------------- | ------------------------------------ | ----------- |
| spec-intake, bugfix-triage          | repo exploration                 | `composer-2.5`   | `z-ai/glm-5.3-flash`                 | `haiku`     |
| bugfix-triage                       | runtime failure root-cause       | `grok-4.7-xhigh` | `x-ai/grok-4.7`                | `sonnet`    |
| contract-first-design, quality-gate | schemas + single-file unit tests | `composer-2.5`   | `z-ai/glm-5.3-flash` | `sonnet`    |
| ux-design                           | UX spec authoring                | `composer-2.5`   | `z-ai/glm-5.3-flash`                 | `haiku`     |
| doc-sync                            | doc drafting                     | `composer-2.5`   | `z-ai/glm-5.3-flash`                 | `haiku`     |


## Notes

- Chat-mode / picker models (Plan, Ask, Debug in Cursor; model switch in Kilo and Claude Code) cannot be enforced by the kit in any tool — the agent frontmatter and command routing hold regardless of the picker.
- A subagent file carries one model per tool; matrix fallbacks are manual.
- `/deliver` prefers the `orchestrator` (Plan role), which launches phase agents so Plan/Build routing holds regardless of the picker.
- Rules and skills reference roles and `docs/model-routing-matrix.md`, never tool-specific model IDs; only this matrix and the adapters carry concrete IDs.
- `scripts/validate-kit.sh` checks each agent's Cursor ID against its exact matrix row and requires the `model_kilo:`/`model_claude:` fields; it does not verify live model availability in any tool.

