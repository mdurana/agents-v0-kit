---
name: document-ai-techniques
description: >-
  Captures ground-level AI interaction patterns and blocker resolutions during
  the Builder Pod sequence. Use when observing Lead Builder and Builder workflows
  throughout design and build phases.
---

# Document AI Techniques

## Overview

The Observer captures operational mechanics of the AI-augmented SDLC as they happen in the Pilot Builder Pod. This includes how the Lead Builder and Builders direct AI during design and build, and how the pod resolves blockers. Output feeds organizational scale-out; formal mentor packaging is `prepare-mentor-handoff`, not this skill.

Skill boundaries: [references/rules/observer-skill-boundaries.md](../../../references/rules/observer-skill-boundaries.md).

Chat-window capture with token and credit reporting is `summarize-chat-session` (`/summarize`). Meeting notes and transcript processing is `summarize-meeting` (`/meeting`). Neither replaces this skill.

## When to Use

- Ongoing throughout the Builder Pod sequence (design and build phases).
- Lead Builder or Builder workflows are active and observable.
- User requests documentation of AI techniques or blocker resolutions from the pilot.
- Ground-level operational mechanics need recording for future propagation.

## Process

### Confirm Observation Context

1. Identify the pod phase: design (`orchestrate-design`), build (`trigger-ai-build`), or adjacent PO/SA activity.
2. Note which roles are active (Lead Builder, Builder, SA coordination).
3. Do not interrupt orchestration — observe and document.

### Capture AI Techniques

1. Record how AI is prompted, scoped, and directed (context loading, skill invocation, artifact references).
2. Note effective patterns: what worked, what produced rework, what quality gates caught issues.
3. Record AI interaction patterns with enough detail for replication by future squads.

### Document Blocker Resolutions

1. When a blocker occurs, capture: symptom, root cause (if identified), resolution steps, and which skills or artifacts were involved.
2. Distinguish process blockers (SDD gaps, missing design package) from technical blockers (build failures, test gaps).
3. Link resolutions to constitution or SDD adherence where relevant.

### Maintain Running Log

1. Append observations chronologically to `nwob-docs/observations/{YYYY-MM-DD}-ai-techniques-log.md` (create on first entry for the date).
2. Cross-reference `/summarize` and `/meeting` outputs when available — do not duplicate full chat transcripts or meeting transcripts.
3. Defer synthesis for mentor deployment to `prepare-mentor-handoff`.

**Output:** Documented AI interaction patterns and resolution strategies at `nwob-docs/observations/{YYYY-MM-DD}-ai-techniques-log.md`.

## Constitution Compliance

**Mandatory:** Document whether observed workflows respect SDD gates (`epic-spec.md`, `epic-spec.md` backlog index, `story-tasks.md` / `story-tasks.md` before build), Gherkin AC traceability, and constitution quality expectations. Flag violations observed; do not recommend bypassing mandatory rules in documented patterns.

**Default-overridable:** Technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Record **effective constraints** as observed in pod sources; do not assume constitution defaults when overrides are documented.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "I'll capture everything in `/summarize`" | `/summarize` is per chat window; this skill maintains the ongoing pilot observation log across sessions. |
| "I'll synthesize the mentor package here" | Mentor packaging is `prepare-mentor-handoff`; this skill captures raw operational mechanics. |
| "Blockers aren't worth documenting" | Blocker resolutions are primary scale-out knowledge for the next squad wave. |
| "I'll document after the sprint" | Real-time capture preserves prompt patterns and context that memory loses. |

## Red Flags

- Observation log recommends skipping SDD or constitution gates.
- Full chat transcripts pasted instead of structured technique notes.
- Mentor handoff synthesis attempted in this skill.
- Secrets, credentials, or PII recorded in observation logs.

## Verification

- [ ] Observation context (phase, roles) recorded?
- [ ] AI techniques and interaction patterns documented with replication detail?
- [ ] Blocker resolutions captured with symptom, steps, and skill/artifact links?
- [ ] Running log updated; mentor synthesis deferred to `prepare-mentor-handoff`?
- [ ] No secrets/PII; constitution and SDD adherence noted where observed?
