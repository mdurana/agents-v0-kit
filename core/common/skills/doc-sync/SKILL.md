---
name: doc-sync
description: Maintain phase playbook. Sync README, architecture, network, and sequence diagrams when behavior or topology changes.
---

# doc-sync

Maintain phase playbook for the `maintenance-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Identify what changed: behavior (API/events/auth) or topology (services/ports/dependencies).
2. Write `docs/agents-v0/maintain/<id>/helper-brief.md` (`helper: docs-author`, `outputs:`, `return:`, `ask:`) to draft doc updates from the diff. Do not launch the helper (`workflow-orchestration.mdc` Helper Subagents). Review the draft the main session brings back.
3. Update, from the commit being documented, not from plan-time wishes:
   - `README.md` — build/run/test/CI commands.
   - `docs/agents-v0/network.md` — ports and dependencies. Set Status to `built` and add a file citation only for a process the commit shows. Leave `planned` rows as planned.
   - `docs/agents-v0/architecture.md` — system context. Copy a network row only when its Status is `built` and its citation is in this commit. Do not describe a `planned` row as running.
   - `docs/agents-v0/diagrams/sequences/<service>.md` — non-trivial flows.
   This is a maintenance note or the docs-only follow-up merge request. It is not an edit inside the feature's code merge (`architecture.md` and `network.md` are shared files).
4. Use Mermaid conventions from `architecture-and-diagrams.mdc` (camelCase IDs, quoted edge labels, ≤ ~50 nodes).
5. Review the drafted changes for accuracy; apply with the smallest diff.
5a. When `docs/agents-v0/onboarding/report.md` exists, run `sh .agents-v0/scripts/check-onboarding-docs.sh`. Code changes move lines, so a `path:line` citation that no longer resolves must be re-pointed to the code it described, or the statement marked `UNVERIFIED`. Update the module document's `commit:` only when you re-read the code it describes.
6. Do not commit without explicit user approval. Do not push: the hook refuses it; the user pushes.

## Rule-compliance checklist
- [ ] `project-delivery-core.mdc`: mandated docs updated (README, architecture, network, sequences).
- [ ] `architecture-and-diagrams.mdc`: Mermaid conventions; diagram locations.
- [ ] `ai-agent-conduct.mdc`: no unsolicited scratch notes; no commits without approval.
- [ ] `workflow-orchestration.mdc`: Release gate docs requirement satisfied.
