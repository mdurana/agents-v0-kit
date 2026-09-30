---
description: Intake phase. Turn a Jira/Confluence spec into the requirements artifact with acceptance criteria, NFRs, regulations, and the approvals table.
---

# /intake

You are entering the **Intake** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

Once `docs/requirements/<feature>.md` exists, run `sh scripts/sync-feature-state.sh docs/requirements/<feature>.md --active-phase intake --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from that file; do not recreate it. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves (`workflow-orchestration.mdc` Phase resume).

## Instructions
0. Classify **change tier** (`workflow-orchestration.mdc`): **Trivial** → `/triage` instead of full Intake; **Major** → record in the artifact and require `system-design` outputs in `/design`.
1. Launch the `requirements-analyst` subagent with the source spec (Jira/Confluence/user description).
2. **Helpers.** If `docs/requirements/<feature>.helper-brief.md` exists, launch the helper it names (`explore-researcher` unless the brief says otherwise) from this session. Pass the result into a second launch of `requirements-analyst`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
3. The analyst must follow the `spec-intake` skill and produce `docs/requirements/<feature>.md`. Record the user story as `As a [role], I want [goal], so that [benefit].` Copy the milestone row when the story belongs to a program. If that sentence still contains `<...>` placeholders, or omits `so that`, stop and ask the user to supply the missing role, goal, or benefit; do not invent them. Split the goal and each constraint into `AC-1`, `AC-2`, … and keep out of scope as its own list. Also record NFRs, regulations, security-review triggers, and open questions; add milestone/story links when the story belongs to a milestone program — `docs/milestones/<milestone>.md`. Apply the story-size budget: one surface unless the user asked for a vertical slice, and at most eight criteria (`AC-1` through `AC-8`). An oversized story stops on `## Proposed split` until the user approves the split.
4. For greenfield UI, ask "Svelte or React?" once and record the answer.
5. For UI-affecting changes, record UX requirements: WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria.
6. Resolve open questions with the user.
7. Check the **Intake gate** (`workflow-orchestration.mdc`):
   - User story recorded as `As a [role], I want [goal], so that [benefit].`
   - Acceptance criteria split from that story and its constraints (`AC-1`, `AC-2`, …), with out of scope listed separately. NFRs and regulations recorded.
   - Story size: `Surfaces:` is one of `backend`, `bff`, or `frontend`, unless `Vertical slice: yes`. At most `AC-8`. No open `## Proposed split`.
   - Open questions resolved.
   - Security-review triggers identified.
   - For UI-affecting changes: UX requirements recorded.
8. **Stop** and present the gate result to the user. Write `docs/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result). After explicit approval, record the Intake decision (Decision: `Approved`), approver, date, and requirements-artifact path in its `Delivery approvals` section. Do not advance to Design without that approval.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`, `frontend-web.mdc`, `security-baseline.mdc` §11.
