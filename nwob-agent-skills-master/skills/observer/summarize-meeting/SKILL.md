---
name: summarize-meeting
description: >-
  Processes and summarizes meeting notes and platform transcripts from Google
  Meet, Zoom, Teams, and other sources supplied as txt, md, docx, or pdf files.
  Use when the user invokes /meeting or requests meeting notes or transcript
  summarization.
---

# Summarize Meeting

Command: `/meeting`

## Overview

Produces a structured **Meeting Summary** from user-supplied meeting material: human-authored **meeting notes**, auto-generated **platform transcripts**, or **both**. Scope is file-based or pasted content in the current thread — not live meeting capture or chat-window summarization (`/summarize`).

Output may feed `document-ai-techniques` or `provide-workflow-feedback` but does not replace those skills.

Platform-specific format hints: [reference.md](reference.md). Output skeleton: [meeting-summary-template.md](../../../templates/observer/meeting-summary-template.md). Artifact paths: [sdd-artifact-layout.md](../../../references/rules/sdd-artifact-layout.md).

## When to Use

- User invokes `/meeting`.
- User provides meeting notes, a platform transcript, or both (file path, attachment, or paste).
- Pilot reporting needs structured minutes from squad ceremonies, stakeholder sessions, or architecture reviews.
- Observer needs meeting capture without full transcript duplication.

## Process

### Confirm Scope

1. **Default input root:** `nwob-docs/meetings/{YYYY-MM-DD}/` — date subfolder = meeting occurrence date. When no path is given, scan date subfolders under `nwob-docs/meetings/` and ask the prompter which folder or file if ambiguous.
2. **In scope:** Files in the meeting inbox, user-provided explicit path(s), attached file(s), or pasted meeting notes and/or transcript in the **current thread**.
3. **Out of scope:** Live meeting capture, chat-window summarization (`/summarize`), other chat tabs unless content is pasted here.
4. Note meeting context if stated (sprint retro, design review, stakeholder intake, pilot sync).
5. **Legacy paths:** If notes/transcripts exist only outside `nwob-docs/meetings/` (e.g. repo root, `docs/`), stop and instruct prompter to stage into `meetings/{YYYY-MM-DD}/` with standard names; offer to copy after explicit confirmation.
6. **Pasted content:** Offer to save raw paste to `nwob-docs/meetings/{date}/{meeting-slug}-notes.md` (or `-transcript`) before processing — do not treat chat as source of truth.

### Ingest by Format

| Format | Approach |
| --- | --- |
| `.txt`, `.md` | Read directly with file tools. |
| `.docx` | `pandoc -t plain {file}` or Python `python-docx` if available; else ask user to export plain text. |
| `.pdf` | Read tool for text PDFs; if unreadable or scanned, request text export from the source platform or user. |

**Rules:**

- Never guess or invent missing content.
- Support multiple files when the user supplies notes + transcript together.
- Record all source paths or `pasted` in the output header.

### Classify Input Type

Set `input_type` before processing:

| Value | Signals |
| --- | --- |
| `meeting_notes` | Headings, bullets, pre-written decisions/actions, attendee lists without turn-by-turn dialogue |
| `transcript` | Speaker labels, timestamps, platform headers, continuous dialogue |
| `mixed` | User supplied both notes and transcript, or a single file contains both structured minutes and dialogue |

When ambiguous, ask the user or label classification as `inferred` in Observer notes.

### Transcript Path

When `input_type` is `transcript` or transcript portion of `mixed`:

1. **Detect platform:** `google_meet`, `zoom`, `teams`, `generic`, or `unknown`. See [reference.md](reference.md).
2. **Record** `platform` and `platform_confidence` (`detected` / `inferred` / `unknown`; use `n/a` when no transcript).
3. **Normalize:** Strip boilerplate (join/leave, caption disclaimers), unify speaker labels, preserve timestamps when present, flag low-quality auto-caption segments.
4. **Summarize:** Extract topics by theme, decisions, action items (owner, due date if stated), open questions, artifacts referenced (`epic-spec.md`, ADRs, etc.). Dense summaries — no full transcript reproduction.

### Meeting Notes Path

When `input_type` is `meeting_notes` or notes portion of `mixed`:

1. **Preserve author intent** — do not over-summarize already-condensed notes.
2. **Structure** content into schema sections (topics, decisions, actions, open questions).
3. **Validate** completeness: missing owners on actions, undated decisions, unnamed participants.
4. **Enhance** only where notes are sparse (e.g., infer topic groupings from bullets).
5. **Flag gaps** when critical fields cannot be derived from the source.

### Mixed Path

When `input_type` is `mixed`:

1. Treat **notes as primary** for decisions and action items when present.
2. Use **transcript** to fill gaps, add context, attribute speakers, or resolve ambiguity.
3. **Reconcile** conflicts explicitly — e.g., notes say "decided X" but transcript shows debate unresolved.
4. Never silently merge contradictory sources; document every material conflict in **Gaps and conflicts**.
5. Set action-item `Source` to `notes`, `transcript`, or `both`.

### Observer Notes

Capture pilot-relevant signals:

- AI/SDLC techniques mentioned
- Workflow friction in design or build phases
- Constitution or SDD adherence signals
- Blockers and resolution discussions

Optional feed for `document-ai-techniques`.

### Emit Meeting Summary

Produce output using this schema, then **persist to disk** at:

`nwob-docs/observations/{YYYY-MM-DD}-{meeting-slug}-summary.md`

Use the meeting occurrence date from content or the source folder name. Derive `{meeting-slug}` from meeting title or source filename (kebab-case). Never leave the summary chat-only.

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

- {Themed bullets}

### Decisions

- {Decision — context}

### Action items

| # | Action | Owner | Due | Context | Source |
|---|--------|-------|-----|---------|--------|
| 1 | … | … | … | … | {notes / transcript / both} |

### Open questions

- {Unresolved items}

### Artifacts referenced

- {epic-spec.md, epic-spec.md backlog index, ADRs, etc.}

### Gaps and conflicts

- {Missing info, unresolved items, notes-vs-transcript conflicts — omit section if none}

### Observer notes

- {Pilot observation signals}
```

Omit the **Gaps and conflicts** section when there are no gaps or conflicts.

### Optional Handoff

1. Offer to append Observer notes to the pilot observation log (`document-ai-techniques`).
2. Flag workflow friction for `provide-workflow-feedback` if evident in the meeting.

## Constitution Compliance

**Mandatory:** Summaries must not recommend bypassing SDD gates or mandatory constitution rules. Flag violations observed in the meeting. Redact secrets, credentials, API tokens, and PII from all summary fields.

**Default-overridable:** Technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Record effective constraints mentioned in the meeting as observed, not as enforcement decisions.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| "I'll use `/summarize` for this file" | `/summarize` is chat-window only; meeting files use `/meeting`. |
| "I'll reproduce the full transcript" | Structured summary is the deliverable; avoid token-wasting duplication. |
| "Meeting notes are already done — skip processing" | Still structure, validate, and add Observer notes. |
| "I'll merge conflicting notes and transcript silently" | Conflicts must appear in Gaps and conflicts. |
| "Platform doesn't matter for notes" | Set platform to `n/a`; still classify `input_type` correctly. |
| "This replaces document-ai-techniques" | Per-meeting summary supplements the ongoing observation log. |
| "Chat output is enough — skip writing the summary file" | Persist to `nwob-docs/observations/{YYYY-MM-DD}-{slug}-summary.md` per artifact layout. |
| "I'll read the transcript from wherever it is" | Read from `nwob-docs/meetings/{YYYY-MM-DD}/` only; stage legacy files first. |

## Red Flags

- Chat-window content summarized without user-provided meeting files or paste.
- Full transcript reproduced instead of structured summary.
- `input_type` not classified.
- Platform labeled without confidence when transcript is present.
- Material notes-vs-transcript conflicts hidden or merged silently.
- Action items missing owners when stated in source.
- Secrets, credentials, or PII in summary output.

## Verification

- [ ] Scope confirmed as user-provided meeting notes and/or transcript (not chat window)?
- [ ] File(s) ingested or pasted content processed?
- [ ] `input_type` classified (`meeting_notes`, `transcript`, or `mixed`)?
- [ ] Platform and confidence recorded when transcript present (`n/a` for notes-only)?
- [ ] Correct processing path applied (notes, transcript, or mixed reconciliation)?
- [ ] Action items include owners when stated in source; `Source` column set for mixed input?
- [ ] Gaps and conflicts surfaced for mixed input or incomplete notes?
- [ ] Observer notes present; secrets/PII redacted?
- [ ] Output matches Meeting Summary schema?
- [ ] Summary persisted to `nwob-docs/observations/{YYYY-MM-DD}-{meeting-slug}-summary.md`?
