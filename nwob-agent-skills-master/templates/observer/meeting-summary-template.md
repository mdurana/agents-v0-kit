# Meeting Summary Template

Canonical output skeleton for `summarize-meeting` (`/meeting`). Replace placeholders; omit **Gaps and conflicts** when none.

```markdown
## Meeting Summary

| Field | Value |
|-------|-------|
| Source file(s) | {path(s) or pasted} |
| Input type | {meeting_notes / transcript / mixed} |
| Platform | {google_meet / zoom / teams / n/a / generic / unknown} |
| Platform confidence | {detected / inferred / unknown / n/a} |
| Meeting title | {from content or unknown} |
| Date / duration | {if extractable or unknown} |
| Participants | {speakers or attendees identified} |
| Summary generated | {ISO-8601 timestamp} |

### Topics discussed

- {Themed bullet}
- {Themed bullet}

### Decisions

- {Decision — brief context}

### Action items

| # | Action | Owner | Due | Context | Source |
|---|--------|-------|-----|---------|--------|
| 1 | {Action description} | {Owner or TBD} | {Due date or TBD} | {Brief context} | {notes / transcript / both} |

### Open questions

- {Unresolved question}

### Artifacts referenced

- {e.g., nwob-docs/sdd/epic-spec.md, epic-spec.md backlog index, tasks.md, ADR-001}

### Gaps and conflicts

- {Missing info, unresolved items, or notes-vs-transcript conflicts}

### Observer notes

- {AI/SDLC techniques, workflow friction, SDD/constitution signals, blockers}
```

## Field Notes

| Field | Guidance |
| --- | --- |
| `Input type` | Required. Drives processing path. |
| `Platform` | Use `n/a` for meeting-notes-only input. |
| `Source` (action items) | Required when `input_type` is `mixed`; optional otherwise. |
| `Gaps and conflicts` | Omit entire section when empty. |
