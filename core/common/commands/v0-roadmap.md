---
description: Sequence an approved discovery document into a now / next / later roadmap. The discovery file may live anywhere in the repository.
---

# /v0-roadmap

You are sequencing a program (`workflow-orchestration.mdc`). The human-in-the-loop discovery already happened outside the kit; its output is the only product input.

## Prerequisite
The user passes one repo-relative path to the discovery file, for example `/v0-roadmap docs/product/claims-discovery.md`. The guard checks entry prerequisites, onboard approval, and roadmap state.

## Resume
The guard decides: `guard-roadmap.sh validate` (step 2) checks discovery completeness and compares sha256 checksums, and `guard-roadmap.sh start` (step 3) resumes from disk or seeds the template. Do not edit `docs/agents-v0/program.state.json`; only the guard scripts write it.

## Instructions
Only this main session runs guard commands; the subagents run none. <!-- kitfix-20261031-gate-commit --> The gate commit is step 8: one commit and one `roadmap-v<n>` tag, made by the guard, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-roadmap.sh steps (scripts/generate-roadmap-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-roadmap.sh check <discovery-path>`. It verifies entry prerequisites, confirms the discovery file exists, checks onboard approval on brownfield codebases, and checks that roadmap is not already approved. When it prints `REFUSED`, show its message and stop.
2. Run `sh .agents-v0/scripts/guard-roadmap.sh validate <discovery-path>` (or with `--refresh` on revision). It checks the six mandatory sections (Problem, Success metric, Options, Chosen option, In scope, Out of scope) and rejects placeholders. When it prints `REFUSED`, have the user complete the discovery document, then validate again.
3. Run `sh .agents-v0/scripts/guard-roadmap.sh start <discovery-path>`. It seeds `docs/agents-v0/roadmap/<program>.md` from `_template.md` if absent and sets state to `in_progress`.
4. Launch the `roadmap-planner` subagent (skill: `program-roadmap`) with the discovery path. It reads the discovery document and drafts `docs/agents-v0/roadmap/<program>.md` with Now, Next, and Later horizons; it runs no shell commands and leaves the Delivery approvals table empty.
5. On a blocker, run `sh .agents-v0/scripts/guard-roadmap.sh block "<plain reason>"` and stop.
6. When the planner reports the roadmap done, run `sh .agents-v0/scripts/guard-roadmap.sh ready <discovery-path>`. It verifies section completeness and item rules, writes `docs/agents-v0/roadmap/<program>.phase-result.md`, and sets state to `awaiting_approval`. When it prints `REFUSED`, have the planner fix what it names, then run `ready` again.
7. Stop. Present the roadmap sequence and its phase result to the user. Next: The user reviews the roadmap and runs, in their own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve roadmap. Never run approve yourself; the agent cannot approve this gate.
8. After the user runs approve in their own terminal, run `sh .agents-v0/scripts/guard-roadmap.sh commit`. It verifies the user's approval record, appends the verified Approved row to Delivery approvals, stages roadmap files, secret-scans, makes the single gate commit, and tags `roadmap-v<n>`. Then suggest: /v0-architecture.
<!-- END generated -->

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `architecture-and-diagrams.mdc`.
