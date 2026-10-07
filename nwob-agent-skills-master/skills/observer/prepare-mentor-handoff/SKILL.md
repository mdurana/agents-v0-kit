---
name: prepare-mentor-handoff
description: >-
  Packages accumulated pilot observations into a mentor-ready seed deployment
  package for the next squad wave. Use when the user invokes /handoff or the
  Observer completes the pilot rotation period (30–60 days).
---

# Prepare Mentor Handoff

Command: `/handoff`

## Overview

At the end of the pilot rotation, the Observer synthesizes accumulated observations into a package that enables deployment as the "Seed" to train the next wave of squads, then transition to Mentor for existing teams. Ongoing capture is `document-ai-techniques`; playbook feedback is `provide-workflow-feedback`; per-session chat capture is `summarize-chat-session` (`/summarize`); meeting notes and transcript summaries are `summarize-meeting` (`/meeting`).

Skill boundaries: [references/rules/observer-skill-boundaries.md](../../../references/rules/observer-skill-boundaries.md).

Output skeleton: [mentor-handoff-template.md](../../../templates/observer/mentor-handoff-template.md). Artifact paths: [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md).

## When to Use

- User invokes `/handoff`.
- Observer completes the pilot rotation period (typically 30–60 days).
- User requests mentor seed package or handoff artifact for scale-out.
- Organizational scale-out requires packaged learnings from the Pilot Builder Pod.
- Transition from Observer to Mentor role is imminent.

## Process

### Confirm Handoff Readiness

1. Verify `document-ai-techniques` observation log has sufficient coverage of design and build phases.
2. Verify `provide-workflow-feedback` items exist for major sprint cycles (or document gaps).
3. Collect relevant `/summarize` session summaries and `/meeting` summaries if they add unique pilot reporting value.
4. If inputs are thin, stop and route to `document-ai-techniques` or request additional observation time.

### Synthesize Core Themes

1. **AI techniques:** Top patterns for directing AI during design and build; anti-patterns that caused rework.
2. **Blocker resolutions:** Recurring blockers and proven resolution playbooks.
3. **Workflow mechanics:** What worked in Lead Builder → Builder orchestration and skill chains.
4. **Playbook feedback:** Consolidated recommendations from `provide-workflow-feedback` with disposition (adopted, pending, rejected).

### Produce Mentor Seed Package Entry

Structure each invocation's entry:

1. **Executive summary** — pilot outcomes, readiness for scale-out, key risks.
2. **Technique playbook** — reusable AI interaction patterns with skill references.
3. **Blocker playbook** — resolution strategies linked to skills and SDD artifacts.
4. **Training outline** — suggested agenda for seeding the next squad (design workshop, build cadence, Observer role).
5. **Open items** — unresolved playbook feedback, constitution gaps observed, follow-up for Chapter Leads.

### Handoff

1. Resolve path: `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md` (today's date unless user specifies occurrence date).
2. **If file exists:** read current content; insert new `## Handoff entry — {ISO-8601 timestamp}` block immediately after `## Document summary` (reverse-chronological); preserve all prior entries — do **not** overwrite.
3. **If file absent:** create from [mentor-handoff-template.md](../../../templates/observer/mentor-handoff-template.md).
4. **Regenerate `## Document summary`** at top — synthesize gist of entire document (all entries combined): pilot readiness, top techniques, top blockers, open risks, playbook disposition highlights. Update header metadata (`Last updated`, `Entry count`).
5. Persist; never chat-only.
6. Chat response leads with document summary; cite file path and whether created or appended.
7. Deliver package to Chapter Leads and designated Mentor transition stakeholders.
8. Redact secrets, credentials, PII, and individual attribution — focus on process mechanics.
9. Observer role transitions to Mentor per organizational cadence when pilot rotation completes.

**Output:** Mentor-ready seed deployment package at `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md`.

## Constitution Compliance

**Mandatory:** Seed package must reinforce SDD gates, story anatomy, Gherkin AC, and mandatory constitution rules as non-negotiable for scaled squads. Do not package workarounds that bypass gates.

**Default-overridable:** Technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Document effective constraints observed in the pilot; distinguish pilot project overrides from enterprise defaults.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "I'll synthesize from memory" | Handoff requires `document-ai-techniques` and feedback inputs — memory is insufficient evidence. |
| "I'll run `/summarize` on every chat" | Session summaries supplement; they do not replace the observation log. |
| "Playbook feedback can wait" | Consolidated feedback is a required handoff section for Chapter Leads. |
| "Skip training outline — they'll figure it out" | Seed deployment requires explicit training structure for the next wave. |
| "I'll overwrite — latest handoff is enough" | Same-date re-invocations append; prior synthesis may contain unique inputs. |
| "Document summary can wait until final handoff" | Regenerate on every invocation for quick access to full-file gist. |
| "Chat output is enough — skip writing the file" | Persist per artifact layout; append when same-date file exists. |

## Red Flags

- Handoff produced without observation log or sprint feedback inputs.
- Package recommends SDD or constitution bypasses as "pilot learnings."
- Secrets, credentials, or PII in handoff artifact.
- Duplicate full chat transcripts instead of synthesized playbooks.
- Same-date file overwritten without reading prior content.
- `## Document summary` stale or missing after append.
- Chat-only output without file persist.

## Verification

- [ ] Inputs from `document-ai-techniques`, `provide-workflow-feedback`, and relevant `/summarize` and `/meeting` outputs gathered?
- [ ] Core themes synthesized (techniques, blockers, workflow, playbook feedback)?
- [ ] Mentor seed package entry includes executive summary, playbooks, training outline, open items?
- [ ] Same-date file detected and appended (not overwritten)?
- [ ] `## Document summary` present and reflects all entries?
- [ ] New entry includes timestamp and invocation metadata?
- [ ] No secrets/PII; constitution and SDD gates reinforced?
- [ ] Package persisted to `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md`?
- [ ] Handoff delivered for Mentor transition?
