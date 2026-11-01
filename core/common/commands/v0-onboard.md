---
description: Brownfield onboarding — baseline, inventories, cited module and system documents, security baseline, and the Onboard gate before feature delivery.
---

# /v0-onboard

You are entering the **Onboard** phase for an **existing** repo after `scripts/install.sh`. The result is documentation that Intake, Design, and Build can rely on: every statement cited to code (`path/File:line`) or marked `UNVERIFIED`, nothing invented, nothing fixed (`workflow-orchestration.mdc`).

## Resume
If `docs/agents-v0/onboarding/state.json` has `onboard` in `approvedPhases` and no active phase, stop. Do not set `in_progress`. Suggest `/v0-roadmap`, `/v0-intake`, `/v0-triage`, or `/v0-maintain`. If `activeStatus` is `awaiting_approval`, stop and wait. Do not set `in_progress`. Otherwise copy `docs/agents-v0/onboarding/_report.template.md` to `docs/agents-v0/onboarding/report.md` when it is absent, then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status in_progress docs/agents-v0/onboarding/report.md`. If the phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When ready for user review, re-run with `--status awaiting_approval` and stop.

## Collision
Onboarding writes shared files (`docs/agents-v0/project-profile.md`, `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`). Stop before the first edit when `git status` shows another feature's uncommitted code or shared-file edit.

## Instructions
1. Launch the `codebase-documenter` subagent (skill: `onboard-discovery`).
2. **Baseline, inventories, and pack** (before scope questions): run `sh .agents-v0/scripts/audit-brownfield-baseline.sh`, then `sh .agents-v0/scripts/generate-repo-map.sh`, `sh .agents-v0/scripts/collect-dependency-graphs.sh`, and `sh .agents-v0/scripts/discover-codebase.sh`. When the profile `Pack` cell is empty or still a placeholder, run `sh .agents-v0/scripts/activate-stack-pack.sh --detect`. Exit 2 keeps the existing `Pack`; do not pass `--force` unless the user confirms a replacement. Exit 3 (no marker, or more than one) asks the user for the pack id.
3. **Scope questions:** List the discovered modules and ask which are in scope and which up to three flows need sequence diagrams (prompt-only; the scripts do not count them). Relay those questions; do not guess.
4. **Helpers:** When `docs/agents-v0/onboarding/<module>.helper-brief.md` files are on disk, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md` once with every brief present. Then launch one `explore-researcher` per brief from this session, pass each result back to `codebase-documenter`, and delete that brief. Do not sync again while a brief already stored in `helperBriefHashes` is still on disk.
5. Check the **Onboard gate**:
   - `docs/agents-v0/project-profile.md` records the commands, the Layout (`Service roots` when the repo has several services), and the contracts.
   - `docs/agents-v0/discovery/` baseline and inventories from step 2 were recorded.
   - Each in-scope module has a document under `docs/agents-v0/onboarding/modules/`.
   - `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/context-map.md`, `docs/agents-v0/adr/0000-inherited-decisions.md`, and `docs/agents-v0/diagrams/sequences/<service>.md` (for each user-selected flow) document the system as-is.
   - `sh .agents-v0/scripts/check-onboarding-docs.sh --gate` passes: every gate document is present (the list is `onboard_gate_docs` in `.agents-v0/scripts/gate-rules`), citations resolve, every `commit:` stamp is a real commit, and no `TEMPLATE:` line remains. `--approve onboard` runs the same check and refuses while it fails.
   - Security baseline snapshot and open `UNVERIFIED` items are summarized in `docs/agents-v0/onboarding/report.md`.
6. Copy `docs/agents-v0/onboarding/_phase-result.template.md` to `docs/agents-v0/onboarding/phase-result.md` and fill it in, including its `commit:` line (the same commit as the report), then run `sh .agents-v0/scripts/sync-feature-state.sh --active-phase onboard --status awaiting_approval docs/agents-v0/onboarding/report.md`, and **stop** to present the onboarding report, open questions, and triage list to the user. After explicit user approval, run `sh .agents-v0/scripts/sync-feature-state.sh --approve onboard docs/agents-v0/onboarding/report.md`. <!-- kitfix-20261031-gate-commit --> Then commit this gate on the integration branch, one commit, and tag it: `git add -A && git commit -m "onboarding: onboard approved" && git tag -a onboard-v1 -m "onboard approved"` (the script prints it). Never `--amend`; a revision after a reopen is a new commit and the next tag (`onboard-v2`). The next phase refuses to start while this gate is uncommitted. Never commit secrets (`.env`, keys): `check-gate-commit.sh` names them.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc`, `ai-agent-conduct.mdc`, `docs/agents-v0/brownfield-onboarding.md`.
