# Observer Skill Boundaries

Shared segregation rules for Observer skills in `skills/observer/`. Persona: [agents/observer.md](../../agents/observer.md). Artifact layout: [sdd-artifact-layout.md](sdd-artifact-layout.md).

Aligned with the [Enterprise System Constitution](../../rules/constitution-core.mdc).

---

## Model: Capture → Synthesize → Handoff

| Layer | Purpose | Skills |
|-------|---------|--------|
| **1 — Capture** | Ongoing or episodic pilot observation | `document-ai-techniques`, `/summarize` (`summarize-chat-session`), `/meeting` (`summarize-meeting`) |
| **2 — Synthesize** | Playbook feedback from accumulated observations | `provide-workflow-feedback` |
| **3 — Handoff** | Mentor seed package at pilot rotation end | `prepare-mentor-handoff` |

**Rule:** No Observer skill may **orchestrate** build, **author** SDD artifacts (`epic-spec.md`, `epic-spec.md` backlog index, `story-tasks.md`, `story-tasks.md`), **produce** architecture artifacts, **replace** Lead Builder or Builder gates, or **bypass** constitution SDD gates.

---

## Canonical source map

| Content pillar | Authoritative source | Author skill | Read by |
|----------------|---------------------|--------------|---------|
| AI technique log | `nwob-docs/observations/{YYYY-MM-DD}-ai-techniques-log.md` | `document-ai-techniques` | `provide-workflow-feedback`, `prepare-mentor-handoff` |
| Chat session summary | `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md` | `/summarize` | `document-ai-techniques`, `provide-workflow-feedback` |
| Meeting summary (parsed) | `nwob-docs/observations/{YYYY-MM-DD}-{meeting-slug}-summary.md` | `/meeting` | `document-ai-techniques`, `provide-workflow-feedback` |
| Workflow feedback | `nwob-docs/observations/{YYYY-MM-DD}-workflow-feedback.md` | `provide-workflow-feedback` | `prepare-mentor-handoff` |
| Mentor handoff package | `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md` (append same-date; rolling `## Document summary`) | `prepare-mentor-handoff` (`/handoff`) | Chapter Leads / Mentor transition |
| Meeting raw inputs | `nwob-docs/meetings/{YYYY-MM-DD}/` | Prompter upload | `/meeting` reads only |
| Value stream maps | `nwob-docs/process/{YYYY-MM-DD}-value-stream-{slug}.md` | Product Owner — `/value` | PO only — **not** Observer |

---

## Cross-persona boundaries

### Observer vs Product Owner

| Observer | Product Owner |
|----------|---------------|
| Captures pilot mechanics and AI interaction patterns | Authors `epic-spec.md`, `epic-spec.md` backlog index, presentations |
| Writes to `observations/` and reads `meetings/` | Writes to `sdd/`, `presentations/`, `process/` |
| Documents SDD adherence observed in the pod | Owns SDD truth and story anatomy |
| `provide-workflow-feedback` targets playbook iteration | `/value` maps concept-to-customer delivery process |

### Observer vs Lead Builder / Builder

| Observer | Lead Builder / Builder |
|----------|------------------------|
| Observes design and build; does not orchestrate | LB orchestrates `orchestrate-design` and `trigger-ai-build` |
| Documents techniques and blockers | LB directs AI implementation; Builder gates |
| Must not approve design or MR | Lead Builder `validate-design-package`, `review-implementation`, `audit-and-approve-code` |

### Observer vs Solution Architect

| Observer | Solution Architect |
|----------|-------------------|
| Records how SA commands/skills were invoked in the pod | Produces `architecture/` artifacts |
| Does not author ADRs or contracts | SA commands/skills own architecture substance |

---

## Capture layer deduplication

| Skill | Scope | Persist | Relationship |
|-------|-------|---------|--------------|
| `document-ai-techniques` | Running log during design/build | `observations/{date}-ai-techniques-log.md` | Primary ongoing capture |
| `/summarize` | Current chat window only | `observations/{date}-{topic}-chat-summary.md` | Episodic; reference in log, do not duplicate full turns |
| `/meeting` | Notes/transcripts from `meetings/{date}/` or paste (persist to inbox first) | `observations/{date}-{slug}-summary.md` | Episodic; reference in log |

**Rules:**

- `/summarize` ≠ `/meeting` — chat window vs meeting file inbox.
- Neither replaces `document-ai-techniques` — they feed it.
- `provide-workflow-feedback` synthesizes from capture skills; does not duplicate full logs.

---

## Intent → skill routing

| Intent | Skill / command |
|--------|-----------------|
| Ongoing AI technique and blocker capture during build | `document-ai-techniques` |
| End-of-session chat capture with token/credit metrics | `/summarize` |
| Process meeting notes or transcript files | `/meeting` |
| Sprint-end or friction-driven playbook feedback | `provide-workflow-feedback` |
| End of pilot rotation (30–60 days) | `prepare-mentor-handoff` (`/handoff`) |

---

## Per-skill boundaries

| Skill | Command | Writes | Must NOT |
|-------|---------|--------|----------|
| `document-ai-techniques` | — | `observations/{date}-ai-techniques-log.md` | Orchestrate build; author SDD; replace `/summarize` or `/meeting` |
| `summarize-chat-session` | `/summarize` | `observations/{date}-{topic}-chat-summary.md` | Summarize other chat tabs; process meeting files |
| `summarize-meeting` | `/meeting` | `observations/{date}-{slug}-summary.md` | Conflate with chat window scope |
| `provide-workflow-feedback` | — | `observations/{date}-workflow-feedback.md` | Implement playbook changes; author SDD |
| `prepare-mentor-handoff` | `/handoff` | `observations/{date}-mentor-handoff.md` (append same-date) | Synthesize without observation inputs; overwrite same-date file |

---

## Anti-rationalization

| Excuse | Correct action |
|--------|----------------|
| "Observer can run orchestrate-design to help" | Document friction; route build work to Lead Builder |
| "I'll author missing stories while observing" | Route to PO `/features` or `/backlog` |
| "`/summarize` replaces document-ai-techniques" | Per-session summary supplements the running log |
| "Paste transcript in chat — skip meetings inbox" | Persist raw input to `meetings/{date}/` before `/meeting` |
| "Value stream map belongs in observations/" | PO `/value` writes to `process/` only |
| "Skip validate-design-package — Observer reviewed design" | Observer documents; Builder gates remain mandatory |

---

## Material vs minor scope

| Change type | Required action |
|-------------|-----------------|
| **New pilot sprint** | Continue `document-ai-techniques`; `/summarize` or `/meeting` on demand |
| **Sprint retro** | `provide-workflow-feedback` after capture inputs exist |
| **Pilot rotation end** | `prepare-mentor-handoff` after log + feedback synthesized |
| **Single chat capture** | `/summarize` only |
