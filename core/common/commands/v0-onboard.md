---
description: Brownfield onboarding — baseline, inventories, cited module and system documents, security baseline, and the Onboard gate before feature delivery.
---

# /v0-onboard

You are entering the **Onboard** phase for an **existing** repo after `scripts/install.sh`. The result is documentation that Intake, Design, and Build can rely on: every statement cited to code (`path/File:line`) or marked `UNVERIFIED`, nothing invented, nothing fixed (`workflow-orchestration.mdc`).

## Resume
The guard decides: `guard-onboard.sh start` (step 1) resumes from the files on disk, and refuses when onboarding is already approved or waiting for approval. Do not edit `docs/agents-v0/onboarding/state.json`; only the guard scripts write it.

## Collision
Onboarding writes shared files (`docs/agents-v0/project-profile.md`, `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`). Stop before the first edit when `git status` shows another feature's uncommitted code or shared-file edit.

## Instructions
Only this main session runs these commands; the subagents run none. <!-- kitfix-20261031-gate-commit --> The gate commit is step 8: one commit and one `onboard-v<n>` tag, made by the guard, never `--amend`.

<!-- BEGIN generated: sh .agents-v0/scripts/guard-onboard.sh steps (scripts/generate-onboard-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-onboard.sh start`. It begins or resumes onboarding and sets the state to `in_progress`. When it prints `REFUSED`, show its message and stop.
2. Run the inventories: `sh .agents-v0/scripts/generate-repo-map.sh`, `sh .agents-v0/scripts/collect-dependency-graphs.sh` and `sh .agents-v0/scripts/discover-codebase.sh`. When the profile `Pack` cell is empty or a placeholder, run `sh .agents-v0/scripts/activate-stack-pack.sh --detect`: exit 2 keeps the existing pack (no `--force` unless the user confirms a replacement), exit 3 asks the user for the pack id.
3. List the discovered modules. Ask the user which are in scope and which flows (up to three) need sequence diagrams. Do not guess.
4. Launch the `codebase-documenter` subagent (skill: `onboard-discovery`) with the scope answers. It reads code and writes the onboarding docs; it runs no commands. For each `docs/agents-v0/onboarding/<module>.helper-brief.md` it writes, launch one `explore-researcher` from this session and pass its result back.
5. On a blocker, run `sh .agents-v0/scripts/guard-onboard.sh block "<plain reason>"` and stop.
6. When the documenter reports the docs done, run `sh .agents-v0/scripts/guard-onboard.sh ready`. It records the baseline audit, runs the onboarding docs check and sets the state to `awaiting_approval`. When it prints `REFUSED`, have the documenter fix what it names, then run `ready` again.
7. Stop. Present the onboarding report, its open questions and the triage list. Next: Sensei reviews the onboarding docs and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve onboard. Never run approve yourself.
8. After the user says approve ran, run `sh .agents-v0/scripts/guard-onboard.sh commit`. It checks the approval, secret-scans and makes the one onboard commit with its `onboard-v<n>` tag. Then suggest: /v0-roadmap, /v0-intake, /v0-triage, or /v0-maintain.
<!-- END generated -->

## Onboard gate
The documenter is done when:
- `docs/agents-v0/project-profile.md` records the commands, the Layout (`Service roots` when the repo has several services), and the contracts.
- Each in-scope module has a document under `docs/agents-v0/onboarding/modules/`.
- `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/context-map.md`, `docs/agents-v0/adr/0000-inherited-decisions.md`, and `docs/agents-v0/diagrams/sequences/<service>.md` (for each user-selected flow) document the system as-is, every statement cited or `UNVERIFIED`, no `TEMPLATE:` line left.
- The security baseline snapshot and the open `UNVERIFIED` items are summarized in `docs/agents-v0/onboarding/report.md`, and `docs/agents-v0/onboarding/phase-result.md` is written.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc`, `ai-agent-conduct.mdc`, `docs/agents-v0/brownfield-onboarding.md`.
