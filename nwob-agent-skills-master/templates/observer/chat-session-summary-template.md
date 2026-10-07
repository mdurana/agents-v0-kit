# Chat Session Summary Template

Canonical output skeleton for `summarize-chat-session` (`/summarize`). Replace placeholders.

```markdown
## Chat Session Summary

| Field | Value |
|-------|-------|
| Session scope | Current chat window |
| Agent / role | {e.g. Builder, Lead Builder, Observer, unknown} |
| Turn count | {n} |
| Summary generated | {ISO-8601 timestamp} |

### Exchange summary

| # | User prompt (summary) | Assistant response (summary) | Notable outcomes |
|---|----------------------|------------------------------|------------------|
| 1 | {Intent, constraints, artifacts referenced} | {Actions taken, decisions, files touched, skills invoked} | {Artifacts produced, blockers, handoffs} |

### Usage metrics

| Metric | Value | Source |
|--------|-------|--------|
| Input tokens | {n or unavailable} | {cursor_ui / estimate / unavailable} |
| Output tokens | {n or unavailable} | {cursor_ui / estimate / unavailable} |
| Total tokens | {n or unavailable} | {cursor_ui / estimate / unavailable} |
| Cache read / write | {n or n/a} | {cursor_ui / n/a} |
| Session credit cost | {amount or unavailable} | {billing_ui / unavailable} |

### Observer notes

- {Techniques observed, friction, SDD/constitution adherence}
```

## Field Notes

| Field | Guidance |
| --- | --- |
| `Agent / role` | Use `unknown` when not identifiable. |
| Usage `Source` | Required for every metric row. Never present `estimate` as billed amount. |
| Persist path | `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md` — mandatory on every `/summarize`. |
| `{topic}` | Kebab-case from primary session subject; fallback `chat-session`. |
