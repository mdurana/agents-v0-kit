---
description: Brownfield onboarding — baseline, inventories, cited module and system documents, security baseline, and the Onboard gate before feature delivery.
---

# /v0-onboard

You are entering the **Onboard** phase for an **existing** repo after `scripts/install.sh`. The result is documentation that Intake, Design, and Build can rely on: every statement cited to code or marked `UNVERIFIED`, nothing invented, nothing fixed (`workflow-orchestration.mdc`).

## Resume
Copy `docs/agents-v0/onboarding/_report.template.md` to `docs/agents-v0/onboarding/report.md` when it is absent, then run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md --active-phase onboard --status in_progress`. If the phase is already `in_progress` or `blocked`, continue from files on disk; do not recreate them. On a blocker (uncommitted application changes, a red environment you cannot fix), re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves.

## Collision
Onboarding rewrites shared files (`docs/agents-v0/project-profile.md`, `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/`). Stop before the first edit when `git status` shows another feature's code, or a shared-file edit that is not this onboarding's. Record `--status blocked` with those paths and ask for a clean tree or a worktree (`sh .agents-v0/scripts/feature-worktree.sh <feature>`).

## Instructions
1. Launch the `codebase-documenter` subagent (skill: `onboard-discovery`).
2. **Scope questions.** The documenter lists the modules and asks which are in scope and which up to three flows need sequence diagrams. Relay those questions; do not guess.
3. **Helpers.** For each `docs/agents-v0/onboarding/<module>.helper-brief.md`, launch the helper it names (`explore-researcher` unless the brief says otherwise) from this session. Briefs for independent modules may run in parallel. Pass each `return:` into a second launch of `codebase-documenter`. Delete a brief after its result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents). Do not present the gate while a brief is on disk.
4. Check the **Onboard gate**:
   - `docs/agents-v0/project-profile.md` records the commands, the Layout (`Service roots` when the repo has several services), and the contracts. The baseline result and its numbers are in the report. Proposed `known_failures` and `coverage_ratchet` rows are listed for a person to approve, not yet in the profile.
   - When the profile `Pack` cell is empty or still a placeholder, run `sh .agents-v0/scripts/activate-stack-pack.sh --detect` (or prompt for the pack id if ambiguous or no marker). The bound pack's rules and skills are installed, and the profile records `Pack` and the verify commands.
   - `docs/agents-v0/discovery/` was generated at the report's `commit:`. Any `TRUNCATED:` list is re-run or recorded as partial.
   - Each in-scope module has a document under `docs/agents-v0/onboarding/modules/`.
   - `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/context-map.md`, and `docs/agents-v0/adr/0000-inherited-decisions.md` are as-is; the sequence diagrams the user named exist.
   - `sh .agents-v0/scripts/check-onboarding-docs.sh` passes: citations resolve, no `TEMPLATE:` line remains, every onboarding document has a `commit:` line.
   - The security baseline is summarized with a triage list for `/v0-maintain`; nothing was fixed here.
   - Open questions and every `UNVERIFIED` item are listed in the report.
5. **Stop** and present the gate result, the open questions, and the triage list to the user (the report is the handoff record; do not write a `phase-result.md`). After explicit approval, record the `onboard` row (Decision: `Approved`, approver, date, the report and modules paths) in the report's `Delivery approvals` table, add any approved ratchet or known-failure rows to the profile, and run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/onboarding/report.md` with no active-phase flags (and `sh .agents-v0/ci/check-feature-state.sh docs/agents-v0/onboarding/report.md`). `/v0-roadmap`, `/v0-architecture`, `/v0-intake`, and `/v0-plan` need that approval.

Optional starters (`docker/` and `openapi/` from kit `templates/`, plus pack starters from `core/<pack>/starters/`): copy only when the user requests `--with-starters` install or gives explicit consent. When the program spans repos, the documenter records `docs/agents-v0/workspace.manifest.json`.

## Rules
`workflow-orchestration.mdc`, `project-delivery-core.mdc`, `architecture-and-diagrams.mdc`, `security-baseline.mdc`, `ai-agent-conduct.mdc`, `docs/agents-v0/brownfield-onboarding.md`.
