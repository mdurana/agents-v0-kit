# Mentor Handoff Template

Canonical output skeleton for `prepare-mentor-handoff` (`/handoff`). Replace placeholders.

On same-date re-invocation: **append** a new `## Handoff entry` block; **regenerate** `## Document summary` from the full file.

```markdown
# Mentor handoff — {YYYY-MM-DD}

| Field | Value |
|-------|-------|
| Pilot artifact | nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md |
| Last updated | {ISO-8601 timestamp} |
| Entry count | {n} |

## Document summary

- {Gist bullet — pilot readiness and scale-out posture}
- {Gist bullet — top AI techniques}
- {Gist bullet — top blockers / resolutions}
- {Gist bullet — playbook feedback disposition}
- {Gist bullet — key open items / risks}

## Handoff entry — {ISO-8601 timestamp}

| Field | Value |
|-------|-------|
| Invocation | {n} of {date} |
| Inputs reviewed | {document-ai-techniques log, workflow-feedback, summarize/meeting refs} |

### Executive summary

{Pilot outcomes, readiness for scale-out, key risks}

### Technique playbook

{Reusable AI interaction patterns with skill references}

### Blocker playbook

{Resolution strategies linked to skills and SDD artifacts}

### Training outline

{Suggested agenda for seeding the next squad}

### Open items

{Unresolved playbook feedback, constitution gaps, follow-up for Chapter Leads}
```

## Field Notes

| Field | Guidance |
| --- | --- |
| `Document summary` | **Regenerated** on every `/handoff` invocation from all entries combined. 3–7 dense bullets. |
| Entry order | Reverse-chronological — newest entry immediately after `## Document summary`. |
| Same-date file exists | Read current content; append entry; do **not** overwrite prior entries. |
| Chat response | Lead with document summary; cite path and whether created or appended. |
