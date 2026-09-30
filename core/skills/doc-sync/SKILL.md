---
name: doc-sync
description: Maintain phase playbook. Sync README, architecture, network, and sequence diagrams when behavior or topology changes.
---

# doc-sync

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Identify what changed: behavior (API/events/auth) or topology (services/ports/dependencies).
2. Launch the `docs-author` subagent to draft doc updates from the diff.
3. Update:
   - `README.md` — build/run/test/CI commands.
   - `docs/architecture.md` — system context.
   - `docs/network.md` — ports and dependencies.
   - `docs/diagrams/sequences/<service>.md` — non-trivial flows.
4. Use Mermaid conventions from `architecture-and-diagrams.mdc` (camelCase IDs, quoted edge labels, ≤ ~50 nodes).
5. Review the drafted changes for accuracy; apply with the smallest diff.
6. Do not commit or push without explicit user approval.

## Rule-compliance checklist
- [ ] `project-delivery-core.mdc`: mandated docs updated (README, architecture, network, sequences).
- [ ] `architecture-and-diagrams.mdc`: Mermaid conventions; diagram locations.
- [ ] `ai-agent-conduct.mdc`: no unsolicited scratch notes; no commits without approval.
- [ ] `workflow-orchestration.mdc`: Release gate docs requirement satisfied.
