---
name: provide-workflow-feedback
description: >-
  Iterates the enterprise playbook by providing actionable ground-level feedback
  from the pilot phase. Use at sprint end or when workflow friction is encountered
  in the AI-augmented SDLC flow.
---

# Provide Workflow Feedback

## Overview

The Observer identifies friction and success in the AI-augmented Design and Develop phases and delivers actionable feedback to iterate the enterprise rollout playbook. Raw technique capture is `document-ai-techniques`; chat-window summaries are `summarize-chat-session` (`/summarize`); meeting notes and transcript summaries are `summarize-meeting` (`/meeting`).

Skill boundaries: [references/rules/observer-skill-boundaries.md](../../../references/rules/observer-skill-boundaries.md).

## When to Use

- End of weekly sprint or iteration retrospective.
- Workflow friction is encountered during design or build.
- User requests pilot feedback for playbook iteration.
- Ground-level observations of the AI-augmented SDLC flow need formalizing for Chapter Leads.

## Process

### Gather Inputs

1. Review ground-level observations from the current pilot period.
2. Incorporate relevant `/summarize` and `/meeting` outputs and `document-ai-techniques` log entries — reference, do not duplicate full logs.
3. Focus on Design phase (`orchestrate-design`, Builder co-design) and Develop phase (`trigger-ai-build`, Builder review/audit) mechanics.

### Identify Friction and Success

1. **Friction:** SDD gate confusion, skill activation gaps, handoff delays, rework loops, unclear ownership between Lead Builder and Builder.
2. **Success:** Effective skill chains, clean design-package sign-off, incremental review catching drift early, quality gate patterns that work.
3. Prioritize feedback that affects multiple squads at scale-out.

### Formulate Actionable Feedback

1. Each item: observation → impact → suggested playbook change (skill update, orchestration order, training emphasis).
2. Distinguish pilot-specific issues from systemic playbook gaps.
3. Link suggestions to existing skills in `skills/` where applicable — do not invent parallel processes.

### Share with Chapter Leads

1. Deliver feedback in a structured format suitable for playbook refinement.
2. Persist to `nwob-docs/observations/{YYYY-MM-DD}-workflow-feedback.md`.
3. Flag constitution or SDD compliance concerns separately from process UX improvements.
4. Do not implement playbook changes in this skill — document recommendations only.

**Output:** Actionable feedback at `nwob-docs/observations/{YYYY-MM-DD}-workflow-feedback.md`.

## Constitution Compliance

**Mandatory:** Feedback must not recommend bypassing SDD gates, Gherkin AC, coverage requirements, or other mandatory constitution rules. Frame compliance issues as "strengthen gate enforcement" not "skip the gate."

**Default-overridable:** Technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). When feedback touches stack choices, reference observed effective constraints, not assumed defaults.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "I'll log techniques here instead of document-ai-techniques" | Raw capture is `document-ai-techniques`; this skill produces structured playbook feedback. |
| "Friction is a one-off — skip formal feedback" | Pilot friction patterns predict scale-out failures; document them. |
| "We should change the constitution" | Flag governance concerns to Chapter Leads; this skill does not authorize constitution overrides. |
| "Negative feedback only" | Document successes equally — they define what to replicate in the playbook. |

## Red Flags

- Feedback recommends vibe-coding or partial SDD artifacts.
- Vague complaints without suggested playbook changes.
- Duplicated full observation logs instead of synthesized feedback.
- Feedback attributed to individuals rather than process mechanics.

## Verification

- [ ] Inputs from observation period reviewed (logs, `/summarize` and `/meeting` refs)?
- [ ] Friction and success items identified with impact?
- [ ] Each item has actionable playbook suggestion?
- [ ] Constitution/SDD concerns flagged separately from UX improvements?
- [ ] Output suitable for Chapter Lead playbook refinement?
