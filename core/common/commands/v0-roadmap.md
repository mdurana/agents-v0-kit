---
description: Sequence an approved discovery document into a now / next / later roadmap. The discovery file may live anywhere in the repository. This command does not rediscover the problem.
---

# /v0-roadmap

You are sequencing a program (`workflow-orchestration.mdc` Roadmap). The human-in-the-loop discovery already happened outside the kit. Its output is the only product input.

## Prerequisite
The user passes one repo-relative path to the discovery file, for example `/v0-roadmap docs/product/claims-discovery.md`. The path may point at any file under the repository root. A run with no path stops and asks for one. Do not search the tree for a discovery document. Do not copy the file into `docs/agents-v0/`.

On a brownfield repo, `docs/agents-v0/onboarding/report.md` must record an `Approved` `onboard` row. When application source exists, `docs/agents-v0/project-profile.md` still has placeholder verify commands, and no onboarding report exists, stop and run `/v0-onboard` first.

Maintain and Trivial never open this command. A single named ticket goes to `/v0-intake`. The seeded P0-A skeleton goes to `/v0-build`.

## Resume
Continue from `docs/agents-v0/roadmap/<program>.md` when it already records `Discovery:` as the path the user gave. Do not recreate it unless `--refresh` is passed or the discovery document content has changed. When facts in the discovery file change, re-run with `--refresh`, update the roadmap facts, reset the `roadmap` approval row, and seek user approval again. Replacing the discovery document means the user points this command at the new path and approves the roadmap again.

## Collision
The roadmap file is shared for that program. Stop before editing `docs/agents-v0/roadmap/<program>.md` when `git status` shows it is already modified by another workstream (unless resuming or running `--refresh` for this program). Uncommitted user edits in the discovery file are expected after authoring or completing preflight fixes; `/v0-roadmap` only reads the discovery file and never edits it. If not in a git repository or `git status` fails, report the error and verify repository state before proceeding.

## Instructions
1. Launch the `program-planner` subagent with the discovery path. It follows `program-roadmap`.
2. Preflight the discovery document: run `sh .agents-v0/ci/check-roadmap.sh --preflight <discovery-path>`. It must contain these headings (Problem, Success metric, Options, Chosen option, In scope, Out of scope), each with a body that is not empty and not a placeholder (`<...>`, `[...]`, `TBD`, `TODO`, `FIXME`, `XX`/`XXX`, `__`, or `???`). Subheadings (`###`) inside a section (such as `### Option 1` under `## Options`) are allowed. A missing or placeholder heading stops the command. Name the heading. The person completes it in the discovery file. Run this command again from that same path.
3. Every In scope leaf item must belong entirely to one horizon. When an In scope parent bullet groups nested sub-bullets, either keep the nested block together in one horizon or place each leaf sub-item in its respective horizon. If a single leaf bullet spans multiple delivery phases, stop and request the user to split it into distinct in-scope sub-items in the discovery document before proceeding. Do not split a leaf item across horizons or invent follow-on themes.
4. Write `docs/agents-v0/roadmap/<program>.md` from `docs/agents-v0/roadmap/_template.md`. The `Discovery:` line records the path the user gave and its sha256 hash (`Discovery: <path> (sha256: <hash>)`). Now, Next, and Later contain only items copied from In scope under the chosen option. Leave the `Delivery approvals` table without an `Approved` row until the user approves in step 6. When the discovery file has a line `Stack preference:`, copy that line onto the roadmap as written. Do not activate a pack from it. Do not add a theme, reopen an option, or interview.
5. Check the **Roadmap gate** (`workflow-orchestration.mdc`): run `sh .agents-v0/ci/gate.sh roadmap docs/agents-v0/roadmap/<program>.md`. It verifies before user approval that the discovery path is recorded, the discovery checksum matches, every in-scope item is assigned to exactly one horizon without inventions or omissions, and out-of-scope items appear only under Out of scope.
6. **Stop** and present the sequence. After explicit user approval, append the `roadmap` row (Decision: `Approved`, approver, date, this file and the discovery path) to the roadmap's `Delivery approvals` table and verify via `sh .agents-v0/ci/gate.sh roadmap --approved docs/agents-v0/roadmap/<program>.md` (pre-commit runs it again when git hooks are installed). That approval covers the sequence. The discovery file has no kit approval row. Do not start `/v0-architecture` or `/v0-plan` without the `roadmap` row.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `architecture-and-diagrams.mdc`.
