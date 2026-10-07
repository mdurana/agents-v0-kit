# SDD Artifact Layout & Discovery Protocol

Canonical standard for where agents read and write SDD, architecture, observation, and presentation artifacts. Applies to **every** agent and skill invocation in this repository.

Full cross-agent workflow: [README.md — Agent Orchestration Workflow](../../README.md#agent-orchestration-workflow). Agent rules: [AGENTS.md](../../AGENTS.md).

---

## Artifact root

Default root: **`nwob-docs/`** at the project repository root.

### External artifact mapping (brownfield)

When docs-as-code already lives elsewhere, initialize with `nwob init --no-scaffold-docs` and map paths in **`.nwob/artifact-paths.json`** (gitignored — not committed).

| Item | Location |
|------|----------|
| Live mapping | `.nwob/artifact-paths.json` |
| Example template | `references/samples/artifact-paths.example.json` in the nwob-agent-skills repo (empty-string placeholders; canonical paths not required) |
| Init option | `.nwob/init-options.json` → `"scaffold_nwob_docs": false` |

**Mapping is SDD-only.** Allowed keys:

| Key | Required | Default |
|-----|----------|---------|
| `spec` | **yes** | `nwob-docs/sdd/epic-spec.md` |
| `stories_dir` | no | `nwob-docs/sdd/stories/` |

`spec` must be non-empty before validation passes. `stories_dir` may be omitted; resolve falls back to the default above. Architecture, presentations, meetings, observations, and other non-SDD artifacts use the **fixed default layout** under `nwob-docs/` (not mappable).

**Obsolete keys:** `plan` and `tasks` (formerly `epic-plan.md` / `epic-tasks.md`) are **not** allowed. CLI warns when they appear in older mappings — delete them and fold content into `epic-spec.md` / per-story `story-tasks.md`.

The bundled example leaves path values empty so projects are not forced onto the default `nwob-docs/` layout. `nwob init` / `nwob config paths --init` write `.nwob/artifact-paths.json` with `spec` and `stories_dir` populated when missing; brownfield users edit that file to point at existing docs. Do not leave `spec` empty in the live mapping.

CLI:

```bash
nwob config paths --init       # create .nwob/artifact-paths.json with SDD keys if missing
nwob config paths --show       # print resolved SDD paths
nwob config paths --validate   # check mapping JSON; require non-empty spec
```

**Phase 0 resolution order:**

1. Load `.nwob/artifact-paths.json` `paths` object when present.
2. For each SDD **key** (`spec`, `stories_dir`), use the mapped relative path when set.
3. When a key is absent from the mapping, use the default path from the table above.
4. Non-SDD artifacts (architecture, meetings, presentations, …) always use the fixed `nwob-docs/` paths in the folder tree below.

Agents read and write SDD artifacts at **resolved paths in place**. Do not stop Phase 0 to demand copy into `nwob-docs/` when mapping points at existing files. Offer migration into `nwob-docs/` only when the prompter explicitly requests it.

**Lazy create:** When a skill needs a missing artifact, create parent directories and the file at the **resolved** path (mapped or default).

---

## Folder tree

```
repositories/                     # local clone workspace (outside nwob-docs/; gitignored except README/.gitkeep)
├── README.md
└── {service-name}/               # one clone per logical service (not committed)
    └── src/main/resources/swagger/   # OpenAPI specs (/contracts)
        └── {spec-file}.yaml

nwob-docs/
├── sdd/                          # SDD core (PO + SA/LB co-equal + Builder / Pod Builder)
│   ├── epic-spec.md              # Problem, vision, roadmap, HL US/TS, chronological backlog index (mapping key: spec)
│   ├── masterplan.md             # Dual twin of architecture/architecture.md (SA ∨ LB; derived from epic-spec)
│   ├── components/               # Per-container plans (flat; derived from epic-spec)
│   │   └── {component-name}-plan.md
│   └── stories/                  # Per-story product + technical annex + tasks
│       └── {STORY_ID}/
│           ├── story-spec.md     # Product anatomy + technical co-design annex
│           └── story-tasks.md    # Builder / Pod Builder: full task bodies for this story
├── architecture/                 # System-level arch docs (SA ∨ LB; dual with sdd/masterplan.md)
│   ├── architecture.md           # Dual twin of sdd/masterplan.md
│   ├── network.md
│   ├── service-map.md            # logical service → repositories/ path; links sdd/components/
│   └── adr/
│       └── ADR-NNN-kebab-title.md
├── diagrams/
│   └── sequences/                # Per-service sequence diagrams
├── meetings/                     # Observer raw meeting inputs (upload inbox)
│   └── {YYYY-MM-DD}/             # Date subfolder = meeting occurrence date
│       ├── {meeting-slug}-notes.{md|txt|docx|pdf}
│       └── {meeting-slug}-transcript.{txt|md|docx|pdf}
├── observations/                 # Observer parsed outputs; Lead Builder /audit report
│   └── audit-report.md           # Lead Builder audit-and-approve-code
├── process/                      # Product Owner delivery-process artifacts (/value)
└── presentations/                # Product Owner deck outputs + intake record
    ├── intake-record.md          # Delivery params (initial: /problem; updates: /intake)
    └── {deck-name}.html|.md      # Rendered decks (/present, /deck)
```

Cursor execution plans (`trigger-ai-build` session overlays) live in `~/.cursor/plans/` only. They are **not** SDD artifacts and must not be written under `nwob-docs/`.

**Do not generate:** `epic-plan.md`, `epic-tasks.md`, `story-plan.md`, `sdd/components/{component-name}/` folders, `sdd/components/component.md`, or nested `component-spec.md` / `component-{id}-plan.md` twins.

**Legacy (read-only):** Existing `epic-plan.md`, `epic-tasks.md`, `story-plan.md`, nested `sdd/components/{id}/`, and `architecture/components/` MAY be read on brownfield; **MUST NOT** receive new writes. Migrate content into consolidated paths when the prompter requests it.

---

## Standard naming convention (mandatory)

### SDD (mappable via `.nwob/artifact-paths.json`)

| Artifact | Default path | Mapping key | Owner role/skill |
|----------|--------------|-------------|------------------|
| Epic specification | `nwob-docs/sdd/epic-spec.md` | `spec` (required) | PO **or** SA **or** LB — `/define`, `/problem`, `/ideate`, `/roadmap`, `/features`, `/backlog` |
| Story spec (per story) | `nwob-docs/sdd/stories/{STORY_ID}/story-spec.md` | under `stories_dir` (optional) | PO `/features`, `/backlog`; SA/LB `/define`, `/features`, `/orchestrate-design`; Builder / Pod Builder `co-design-solution` (technical annex sections; flag material AC for PO) |
| Story tasks (per story) | `nwob-docs/sdd/stories/{STORY_ID}/story-tasks.md` | under `stories_dir` (optional) | Builder / Pod Builder — `co-design-solution`; SA/LB via `/orchestrate-design` / `co-design-solution` |
| Masterplan | `nwob-docs/sdd/masterplan.md` | fixed under `sdd/` (not a mapping key) | SA **or** LB — `/c4` … `/ops`, `/architecture`, `/orchestrate-design` (dual twin of `architecture.md`; derived from `epic-spec.md`) |
| Component plan | `nwob-docs/sdd/components/{component-name}-plan.md` | fixed under `sdd/` (not a mapping key) | SA **or** LB — `/services`, `/ops`, `/orchestrate-design` (derived from `epic-spec.md`) |

### Dual-persist alias pairs (mandatory)

| Twin A | Twin B | Rule |
|--------|--------|------|
| `nwob-docs/architecture/architecture.md` | `nwob-docs/sdd/masterplan.md` | Any create/update of one **MUST** write/update the other with the same body |

Readers may use either name. Validation treats either path as satisfying the other. **Writers** create new component files as flat `nwob-docs/sdd/components/{component-name}-plan.md` only. **Brownfield readers** MAY read legacy nested `sdd/components/{id}/` or `nwob-docs/architecture/components/` when present; do not write new files there.

### Write ACL for `*-spec.md` / `*-plan.md` / `*-tasks.md`

Any persona may **read** these files. **Write** only when a primary owning skill or documented co-author skill is active:

| File | May write | Must not write |
|------|-----------|----------------|
| `epic-spec.md` | PO author skills; SA **or** LB when invoking those skills / `/define` / `/features` / `/backlog` | Builder (product sections), Pod Builder (product sections), Observer, persona switch/init |
| `story-spec.md` | PO `/features`, `/backlog` (product anatomy); SA/LB `/define`, `/features`, `/orchestrate-design`; Builder / Pod Builder `co-design-solution` (technical annex; flag material AC for PO) | Observer, persona switch/init |
| `story-tasks.md` | Builder / Pod Builder `co-design-solution`; SA/LB `/orchestrate-design` / `co-design-solution` | PO (product-only skills), Observer, persona switch/init |
| `masterplan.md`, `architecture.md` | SA **or** LB `/c4` … `/ops`, `/architecture`, `/orchestrate-design` (dual-persist both) | Pod Builder, Observer, persona switch/init |
| `sdd/components/{component-name}-plan.md` | SA **or** LB `/services`, `/ops`, `/orchestrate-design` | Pod Builder, Observer, persona switch/init |
| ADR bodies, OpenAPI | SA **or** LB `/pattern`, `/adr`, `/contracts` | Pod Builder, Observer, persona switch/init |

**MUST NOT** rewrite or “improve” these files outside an owning skill, or during `/persona` / `/switch` / `nwob init`. Route product/AC gaps to PO `/backlog`; route annex gaps to `co-design-solution`; route architecture gaps to SA/LB.

### Fixed layout (not in artifact-paths mapping)

| Artifact | Default path | Owner role/skill |
|----------|--------------|------------------|
| Jira export params | `nwob-docs/sdd/tickets-export-params.md` | Product Owner — `/backlog` (ask/confirm; persist) |
| Jira tickets CSV | Path from `tickets-export-params.md` `output_path` (suggested: `nwob-docs/sdd/tickets.csv`) | Product Owner — `/backlog` (derived; not SDD source of truth) |
| Presentation intake | `nwob-docs/presentations/intake-record.md` | Product Owner **or** SA/LB — `/define` or `/problem` (initial); `/intake` (update) |
| System architecture | `nwob-docs/architecture/architecture.md` | SA **or** LB — `/c4` … `/ops`, `/architecture`, `/orchestrate-design` (dual with `sdd/masterplan.md`) |
| Masterplan | `nwob-docs/sdd/masterplan.md` | SA **or** LB — same skills as system architecture (dual twin; derived from `epic-spec.md`) |
| Component plan (per container) | `nwob-docs/sdd/components/{component-name}-plan.md` | SA **or** LB — `/services`, `/ops`, `/orchestrate-design` |
| Network / infra | `nwob-docs/architecture/network.md` | SA **or** LB — `/platform`, `/ops` |
| Service map | `nwob-docs/architecture/service-map.md` | SA **or** LB — `/services`, `/contracts`; prompter seeds brownfield |
| OpenAPI spec (per service) | `repositories/{service-name}/src/main/resources/swagger/{spec-file}.yaml` | SA **or** LB — `/contracts` |
| Code workspace | `repositories/` | Prompter (local clones); **init + `nwob doctor` create layout + `.gitignore` if missing** |
| Pattern-selection ADR | `nwob-docs/architecture/adr/ADR-NNN-architectural-pattern-selection.md` | SA **or** LB — `/pattern` |
| ADR | `nwob-docs/architecture/adr/ADR-NNN-kebab-title.md` | SA **or** LB — `/pattern`, `/adr` |
| Sequence diagram | `nwob-docs/diagrams/sequences/{service-name}.md` | SA **or** LB — `/services`; design package |
| Meeting notes (raw) | `nwob-docs/meetings/{YYYY-MM-DD}/{meeting-slug}-notes.{md\|txt\|docx\|pdf}` | Prompter upload; Observer `/meeting` reads |
| Meeting transcript (raw) | `nwob-docs/meetings/{YYYY-MM-DD}/{meeting-slug}-transcript.{txt\|md\|docx\|pdf}` | Prompter upload; Observer `/meeting` reads |
| Meeting summary (parsed) | `nwob-docs/observations/{YYYY-MM-DD}-{meeting-slug}-summary.md` | Observer — `/meeting` output |
| AI techniques log | `nwob-docs/observations/{YYYY-MM-DD}-ai-techniques-log.md` | Observer — `document-ai-techniques` |
| Chat session summary | `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md` | Observer — `/summarize` output |
| Workflow feedback | `nwob-docs/observations/{YYYY-MM-DD}-workflow-feedback.md` | Observer — `provide-workflow-feedback` |
| Mentor handoff package | `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md` | Observer — `/handoff` (append same-date; regenerate `## Document summary` each invocation) |
| MR audit report | `nwob-docs/observations/audit-report.md` | Lead Builder — `/audit` (`audit-and-approve-code`) |
| Value stream map | `nwob-docs/process/{YYYY-MM-DD}-value-stream-{slug}.md` | Product Owner — `/value` |
| Presentation deck | `nwob-docs/presentations/{deck-name}.html` or `.md` | Product Owner — `/present`, `/deck` |

### `epic-spec.md` section contract

| Section | Owner command |
|---------|---------------|
| Problem/Context | `/problem` or `/define` (PO, SA, or LB) |
| Metrics | `/problem` or `/define` |
| Solutions / Hypotheses | `/ideate` or `/define` |
| Roadmap (Now/Next/Later) | `/roadmap` or `/define` |
| Parent details (summary, objective, exit criteria, benefit realization) | `/define` / `/problem` — SA or LB from initiative `requirements.md` when present |
| Milestone / related epics | `/define` / `/roadmap` — SA or LB |
| High-level US/TS (AC, product rules, pre-conditions, triggers, flows) | `/define` / `/features` — SA, LB, or PO |
| Chronological backlog index (ID, summary, size, deps, link to story-spec) | `/features` / `/backlog` — PO, SA, or LB |

**Story model:** `/features` and `/backlog` maintain the chronological backlog **index** and high-level US/TS **inside `epic-spec.md`**, and write full story anatomy (product + later technical annex) to `{stories_dir}/{STORY_ID}/story-spec.md`. Lazy-create the `{STORY_ID}/` folder when first writing either story file. Jira CSV export params and `tickets.csv` via `/backlog` only (parameterized; see backlog-management skill).

**SDD gates:**

| Gate | Requirement |
|------|-------------|
| Initial | Resolved `epic-spec.md` (`spec`) on disk |
| Architecture (derived) | SA/LB derive `masterplan.md` (+ dual `architecture.md`) and `sdd/components/{component-name}-plan.md` from `epic-spec.md` |
| Design / build | In-scope `{stories_dir}/{STORY_ID}/story-spec.md` + `story-tasks.md`; story order from epic-spec backlog index |

**Non-standard unmapped paths are not valid inputs** when no mapping exists. With `.nwob/artifact-paths.json`, mapped paths override defaults even when filenames differ from NWOB conventions. Content may stay as-is; agents use the resolved path as source of truth.

ADR numbering: zero-padded three digits (e.g. `ADR-001-use-kafka.md`).
---

## Phase 0: Project discovery (mandatory)

Run before any workflow step. **Resolve artifact paths first** (mapping or defaults per table above); scan resolved paths only. Ask the prompter when not discoverable.

| Question | Paths | If present | If absent |
|----------|-------|------------|-----------|
| SDD artifacts? | Mapping key `spec` (required); `stories_dir` (optional) | Load, validate; write only via owning skills | Create missing files at resolved paths when an owning skill runs |
| Architecture docs? | Fixed: `nwob-docs/architecture/` (`architecture.md`, `network.md`, `service-map.md`, `adr/`) + `nwob-docs/sdd/masterplan.md` + flat `nwob-docs/sdd/components/{component-name}-plan.md` | SA/LB commands review/extend (`/c4` … `/architecture`); dual-persist masterplan; derive from `epic-spec.md` | SA/LB commands produce new docs at default paths; legacy nested components / `architecture/components/` read-only fallback |
| Code workspace? | `repositories/` + `nwob-docs/architecture/service-map.md` | Load clones; resolve paths from service-map | Run `nwob doctor` to repair layout + `.gitignore`; greenfield assumes future clones |
| Meeting inbox? | Fixed: `nwob-docs/meetings/{YYYY-MM-DD}/` | `/meeting` reads from date subfolders; list pending files | Create meetings tree when uploads expected |
| Docs scaffold? | `.nwob/init-options.json` → `scaffold_nwob_docs` | Default tree expected when `true` | External mapping mode when `false` |

Document discovery outcomes in the engagement. SDD reads/writes use **resolved mapping paths**; other artifacts use fixed `nwob-docs/` paths.

---

## Brownfield: prompter responsibilities

On brownfield engagements (existing spec, architecture, and/or code), the **prompter configures artifact paths** before agents proceed past Phase 0.

### Prompter checklist

**Option A — default layout (greenfield or migration into `nwob-docs/`):**

1. Run `nwob init` (default) or `nwob doctor` to create the `nwob-docs/` tree.
2. Place or copy existing artifacts into default paths with standard names.
3. Rename files to match standard names when unmapped.
4. If legacy `epic-plan.md` / `epic-tasks.md` / `story-plan.md` / nested component folders exist, migrate content into `epic-spec.md`, `story-spec.md`, and flat `{component-name}-plan.md` when ready — do not write new content to legacy paths.

**Option B — external docs (existing paths, no migration):**

1. Run `nwob init --no-scaffold-docs --persona <persona>` — init writes `.nwob/artifact-paths.json` with `spec` and `stories_dir` when the file is missing.
2. Edit `.nwob/artifact-paths.json` (gitignored): set `spec` (required); optionally `stories_dir`. Remove obsolete `plan` / `tasks` and any non-SDD keys.
3. Run `nwob config paths --validate`.
4. Confirm in the prompt which artifacts exist at mapped paths, e.g. *"Brownfield: mapping points `spec` → `docs/requirements/spec.md`; N services under `repositories/`."*

Shared steps (both options):

1. **Ensure `repositories/` exists** — `nwob init` and `nwob doctor` create it and upsert the managed `.gitignore` block if missing. Clone services: `git clone <url> repositories/{service-name}`.
2. **Register each service** in `nwob-docs/architecture/service-map.md` (path, remote, type; OpenAPI column uses swagger subpath).
3. **Stage meeting files** under `nwob-docs/meetings/{YYYY-MM-DD}/` using `{meeting-slug}-notes` and `{meeting-slug}-transcript` naming when `/meeting` is used.

Legacy layouts using `@backend/`, `@frontend/` require migration into `repositories/` and service-map rows.

### Legacy file handling (agent behavior)

| Situation | Agent action |
|-----------|--------------|
| Resolved path exists on disk | Read/update in place |
| Mapping points at existing file elsewhere | **Proceed** — use mapped path; do not require copy into `nwob-docs/` |
| Legacy file exists elsewhere only and **no mapping** | Stop Phase 0 — instruct prompter to run `nwob config paths --init` and map paths, **or** copy into default `nwob-docs/` paths after explicit confirmation |
| Legacy `epic-plan.md` / `epic-tasks.md` / `story-plan.md` / nested components | **Read-only** — migrate into consolidated paths on prompter request; never write new content there |
| Meeting notes/transcript outside `nwob-docs/meetings/` | Instruct prompter to stage under `nwob-docs/meetings/{YYYY-MM-DD}/` |
| Prompter pastes content in chat | **Do not treat chat as source of truth** — write to resolved path, then continue |
| Partial staging (e.g. spec only) | Branch per matrix below; create only missing artifacts at resolved paths |

---

## Brownfield branch matrix

Jump to the appropriate workflow step instead of restarting from step 1.

| Resolved SDD / architecture | Also present | Enter at step |
|-----------------------------|--------------|---------------|
| Resolved `spec` only | No `masterplan` / architecture | 2 (SA conceptual) or 3 (Product Owner `/features`) |
| Resolved `spec` only | `masterplan` / architecture present | 3 (Product Owner `/features`) |
| Resolved `spec` with backlog index | Stories not sprint-ready | 4 (backlog design; interim: Product Owner `/backlog`) |
| Resolved `spec` with sprint-ready stories | — | 8 (`orchestrate-design` / co-design) |
| Resolved `spec` + architecture + components | `repositories/` + service-map populated | 8 (`orchestrate-design` / co-design) |
| Code only | No SDD at resolved paths | **Stop** — configure mapping or run Product Owner `/problem` and `/features` |

---

## Persistence rules

1. **Resolve SDD paths first** — Load `.nwob/artifact-paths.json` when present; otherwise use SDD defaults. Non-SDD artifacts use fixed `nwob-docs/` paths.
2. **Write ACL** — Read any `*-spec.md` / `*-plan.md` / `*-tasks.md`; write only via owning skills (see Write ACL above). Persona switch/init must not modify those files.
3. **`repositories/` for service code** — OpenAPI specs written by `/contracts` to `repositories/{service-name}/src/main/resources/swagger/`.
4. **Write, don't chat-only** — Persist every artifact update to disk.
5. **Single source of truth** — No duplicate copies at non-standard paths within an engagement unless prompter explicitly requests migration.
6. **External mapping** — `.nwob/artifact-paths.json` is gitignored; SDD keys only (`spec`, `stories_dir`); share out-of-band when teams need the same paths.
7. **Product Owner presentations** — `/collect` reads SDD (resolved) + architecture (fixed `nwob-docs/architecture/`); `/present` writes under `nwob-docs/presentations/`; `/deck` requires SDD gate per [presentation-standards.md](presentation-standards.md).
8. **Observer `/meeting`** — reads raw notes and transcripts from `nwob-docs/meetings/{YYYY-MM-DD}/`; writes parsed summaries to `nwob-docs/observations/{YYYY-MM-DD}-{meeting-slug}-summary.md`.
9. **Observer `/summarize`** — writes chat session summaries to `nwob-docs/observations/{YYYY-MM-DD}-{topic}-chat-summary.md` on every invocation.
10. **Observer `/handoff`** — writes mentor handoff to `nwob-docs/observations/{YYYY-MM-DD}-mentor-handoff.md`; appends when same-date file exists; regenerates `## Document summary` at top on every invocation.
11. **Per-story artifacts** — Product Owner `/features` and `/backlog` write `{STORY_ID}/story-spec.md` under resolved `stories_dir`. Builder `co-design-solution` writes technical annex sections into the same `story-spec.md` and authors `{STORY_ID}/story-tasks.md`. Lazy-create the story folder when missing.
12. **Execution plans** — Builder `trigger-ai-build` writes Cursor Plan Mode overlays to `~/.cursor/plans/` only. Do not store them under `nwob-docs/`; they overlay `story-tasks.md`, they do not replace it.
13. **Lead Builder `/audit`** — writes `nwob-docs/observations/audit-report.md`.

---

## Common rationalizations

| Rationalization | Rebuttal |
|-----------------|----------|
| "Read from `docs/spec.md` instead — it's the same content" | Map `spec` in `.nwob/artifact-paths.json` or copy to default path after explicit confirmation. |
| "Artifacts in chat are enough for this session" | Chat is not source of truth. Write to resolved path before continuing. |
| "We'll organize files into `nwob-docs/` later" | Phase 0 proceeds with mapping; migration is optional, not a gate. |
| "The spec is a Word doc — agents can open it" | Convert/copy content into resolved `spec` path. |
| "I'll point you at the repo; you figure out where things are" | Read mapping or defaults; run `nwob config paths --show`; do not guess layout. |
| "I'll attach the transcript in chat instead of the inbox" | Save raw input to `nwob-docs/meetings/{YYYY-MM-DD}/` before parsing; chat is not source of truth. |
| "Keep writing epic-plan.md / epic-tasks.md / story-plan.md" | Those files are retired. Use `epic-spec.md`, `story-spec.md`, and `story-tasks.md`. |

---

## Verification checklist

- [ ] Artifact paths resolved (`.nwob/artifact-paths.json` or defaults)?
- [ ] Resolved paths scanned before workflow step 1?
- [ ] Brownfield: mapping configured or artifacts at default paths?
- [ ] No reliance on scattered unmapped paths as source of truth?
- [ ] All new/updated artifacts written at resolved paths?
- [ ] `repositories/` and `nwob-docs/architecture/service-map.md` present (or repaired via `nwob doctor`)?
- [ ] `.nwob/artifact-paths.json` contains only SDD keys (`spec`, optional `stories_dir`)?
- [ ] Obsolete `plan` / `tasks` keys removed from mapping?
- [ ] `.gitignore` managed block ignores `repositories/*` and `.nwob/artifact-paths.json`?
- [ ] Service-map rows match cloned services for active work?
- [ ] Chat-only artifacts persisted to disk before handoff?
- [ ] Meeting notes/transcripts staged in `meetings/{YYYY-MM-DD}/` when `/meeting` is invoked?
- [ ] `/meeting` summary written to `observations/{YYYY-MM-DD}-{slug}-summary.md`?
- [ ] `/summarize` summary written to `observations/{YYYY-MM-DD}-{topic}-chat-summary.md`?
- [ ] `/handoff` created or appended at `observations/{YYYY-MM-DD}-mentor-handoff.md` with current `## Document summary`?
- [ ] New component plans written as flat `sdd/components/{component-name}-plan.md` (no nested folders)?
