---
description: Intake phase. Turn a Jira/Confluence spec into the requirements artifact with acceptance criteria, NFRs, regulations, and the approvals table.
---

# /intake

You are entering the **Intake** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

Once `docs/requirements/<feature>.md` exists, run `sh scripts/sync-feature-state.sh docs/requirements/<feature>.md --active-phase intake --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from that file; do not recreate it. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves (`workflow-orchestration.mdc` Phase resume).

## Instructions
0. Classify **change tier** (`workflow-orchestration.mdc`): **Trivial** → `/triage` instead of full Intake; **Major** → record in the artifact and require `system-design` outputs in `/design`.
1. Launch the `requirements-analyst` subagent with the source spec (Jira/Confluence/user description).
2. The analyst must follow the `spec-intake` skill and produce `docs/requirements/<feature>.md` (acceptance criteria, NFRs, regulations, security-review triggers, open questions; milestone/story links when the story belongs to a milestone program — `docs/milestones/<milestone>.md`).
3. For greenfield UI, ask "Svelte or React?" once and record the answer.
4. For UI-affecting changes, record UX requirements: WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria.
5. Resolve open questions with the user.
6. Check the **Intake gate** (`workflow-orchestration.mdc`):
   - Acceptance criteria, NFRs, and regulations recorded.
   - Open questions resolved.
   - Security-review triggers identified.
   - For UI-affecting changes: UX requirements recorded.
7. **Stop** and present the gate result to the user. After explicit approval, record the Intake decision (Decision: `Approved`), approver, date, and requirements-artifact path in its `Delivery approvals` section. Do not advance to Design without that approval.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`, `frontend-web.mdc`, `security-baseline.mdc` §11.
