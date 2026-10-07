---
name: summarize-chat-session
description: >-
  Summarizes prompts and responses in the current chat window and reports token
  usage and credit cost. Use when the user invokes /summarize or requests a
  chat session summary for pilot reporting.
---

# Summarize Chat Session

## Overview

Produces a structured **Chat Session Summary** of the current agent chat window: user prompts, assistant responses, token usage, and session credit cost. Scope is the **same context window only** — not other tabs, Composer sessions, or prior chats.

Skill boundaries: [references/rules/observer-skill-boundaries.md](../../../references/rules/observer-skill-boundaries.md).

Output may feed `document-ai-techniques` or `provide-workflow-feedback` but does not replace those skills.

Meeting notes and platform transcripts from files are `summarize-meeting` (`/meeting`), not this skill.

Output skeleton: [chat-session-summary-template.md](../../../templates/observer/chat-session-summary-template.md). Artifact paths: [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md).

## When to Use

- User invokes `/summarize`.
- End of session, pilot reporting, or before handoff needs a chat capture.
- User requests token usage or credit cost for the current chat window.
- Observer needs a structured summary without full transcript duplication.

## Process

### Confirm Scope

1. **In scope:** User prompts and assistant responses visible in the **current chat window** (same context window).
2. **Out of scope:** Other chat tabs, prior sessions, background agents — unless the user explicitly pastes that content into the current thread.
3. Note identifiable agent role or persona if known (Builder, Lead Builder, PO, SA, Observer, etc.).

### Enumerate Turns

1. List exchanges in chronological order (turn 1, 2, …).
2. For each turn, identify: user prompt and corresponding assistant response.
3. Record turn count for the summary header.

### Summarize Exchanges

For each turn or logical group:

1. **User prompt (summary):** Intent, constraints, artifacts referenced.
2. **Assistant response (summary):** Actions taken, decisions, files touched, skills invoked.
3. **Notable outcomes:** Artifacts produced, blockers hit, handoffs, constitution/SDD mentions.

Keep summaries dense; do not reproduce full message text unless a short quote is essential.

### Collect Usage Metrics

Report from available sources in priority order:

1. **Cursor UI** — session or message token counts (usage panel, status bar, message metadata) when visible.
2. **Account usage / billing** — when the agent or user can access Cursor Settings → Usage or account dashboard.
3. **Unavailable** — state explicitly; do not omit the metrics section.

**Rules:**

| Source label | When to use |
| --- | --- |
| `cursor_ui` | Exact figures from IDE or session metadata |
| `billing_ui` | Exact credit cost from usage/billing views |
| `estimate` | Approximate range from conversation length only — label clearly; never present as billed amount |
| `unavailable` | No reliable source — tell user where to check (Settings → Usage, account dashboard) |

Report when available:

- Input tokens
- Output tokens
- Total tokens
- Cache read / write (or `n/a`)
- Session credit cost

### Emit Chat Session Summary

Produce output using this schema, then **persist to disk** at:

`nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md`

Use the session date or today's date (ISO `YYYY-MM-DD`). Derive `{topic}` from the primary session subject (kebab-case); fallback `chat-session`. Create `observations/` if absent. Never leave the summary chat-only.

See [chat-session-summary-template.md](../../../templates/observer/chat-session-summary-template.md).

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
| 1 | … | … | … |

### Usage metrics

| Metric | Value | Source |
|--------|-------|--------|
| Input tokens | {n or unavailable} | {cursor_ui / estimate / unavailable} |
| Output tokens | {n or unavailable} | … |
| Total tokens | {n or unavailable} | … |
| Cache read / write | {n or n/a} | … |
| Session credit cost | {amount or unavailable} | {billing_ui / unavailable} |

### Observer notes

- {Techniques observed, friction, SDD/constitution adherence — optional feed for document-ai-techniques}
```

### Optional Handoff

1. Offer to append Observer notes to `nwob-docs/observations/{YYYY-MM-DD}-ai-techniques-log.md` via `document-ai-techniques`.
2. Flag workflow friction for `provide-workflow-feedback` if evident in the session.

## Constitution Compliance

**Mandatory:** Summaries must not recommend bypassing SDD gates or mandatory constitution rules. Flag violations observed in the chat. Redact secrets, credentials, API tokens, and PII from all summary fields.

**Default-overridable:** Technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Record effective constraints mentioned in the chat as observed, not as enforcement decisions.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "I'll guess token usage" | Use `estimate` label only when necessary; never present guesses as billed amounts. |
| "I'll summarize a different chat tab" | Out of scope unless user pastes content into this thread. |
| "I'll use `/summarize` for meeting files" | Meeting notes and transcripts use `/meeting` (`summarize-meeting`). |
| "Credit cost isn't shown — skip metrics" | Metrics section is mandatory; report `unavailable` with where to check. |
| "Full transcript is better" | Structured summary is the deliverable; avoid token-wasting duplication. |
| "This replaces document-ai-techniques" | Per-session summary supplements the ongoing observation log. |
| "Chat output is enough — skip writing the summary file" | Persist to `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md` per artifact layout. |

## Red Flags

- Chat-only output without file persist.
- Summary includes other chat windows without user-provided content.
- Token or credit figures presented without source label.
- Estimates presented as exact billed costs.
- Secrets, credentials, or PII in summary output.
- Metrics section omitted when figures are unavailable.

## Verification

- [ ] Scope confirmed as current chat window only?
- [ ] All turns enumerated and summarized?
- [ ] Usage metrics section complete with source labels (`cursor_ui`, `billing_ui`, `estimate`, or `unavailable`)?
- [ ] Session credit cost reported or marked unavailable with user guidance?
- [ ] Secrets/PII redacted; SDD/constitution observations noted in Observer notes?
- [ ] Output matches Chat Session Summary schema?
- [ ] Summary persisted to `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md`?
