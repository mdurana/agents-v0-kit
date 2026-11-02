---
name: onboard-discovery
description: Brownfield onboarding playbook. Baseline, mechanical inventories, module documents, as-is architecture and flows, security baseline, all cited and verified.
---

# onboard-discovery

Onboard phase playbook for the `codebase-documenter` agent (`/v0-onboard`, `workflow-orchestration.mdc`). Goal: documentation deep enough that Intake, Design, and Build can start without re-reading the code, with every unknown recorded. "Fully" means no silent gaps, not no gaps.

## Steps
You have no shell (Design: D5). The main session runs every script and guard step in `/v0-onboard`; you read their outputs and write documents.
1. **Set up.** `report.md` is already there (the guard's `start` copies the template). Record `commit:` with the `baseCommit` from `docs/agents-v0/onboarding/state.json`; every document describes that tree.
2. **Baseline.** The guard's `ready` step records the baseline audit in `docs/agents-v0/discovery/baseline-audit.txt`. A red baseline is documented, not fixed.
3. **Mechanical inventories.** Read the repo map, dependency graphs and discovery files the main session generated under `docs/agents-v0/`.
   - A root with no graph is recorded as `UNVERIFIED`; ask the main session to fix the environment (wrapper, `npm ci`) and rerun the script.
   - A `TRUNCATED:` line means a list was cut. Re-run with a higher `DISCOVER_MAX`, or record that the list is partial.
   - Inventories are heuristics. Read the cited line before relying on a row.
4. **Profile.** Update `docs/agents-v0/project-profile.md`: commands, Layout (`Profile`, `Backend root`, `Frontend root`, `BFF root`, `Service roots` as found; do not move source onto a greenfield default), contracts. The main session activates the pack (`activate-stack-pack.sh --detect`). Do not replace a `Pack` cell that already names an id. A later roadmap or architecture does not replace it. From `docs/agents-v0/discovery/baseline.md`, list the proposed `known_failures` and `coverage_ratchet` rows in the report. Add them to the profile only after a person approves them; a ratchet needs a Security and architecture approver.
5. **Scope.** From the repo map, Service roots, and packages, list the modules. Show the list to the user and agree the order and which modules are in scope. Ask the user to name up to three flows for sequence diagrams (prompt-only; the scripts do not count them), for example the main write path and the login path.
6. **Module documents.** For each module, in dependency order, write `docs/agents-v0/onboarding/modules/<module>.md` from `docs/agents-v0/onboarding/_module.template.md`, using the inventories for that module.
   - A module too large to read in one pass: write `docs/agents-v0/onboarding/<module>.helper-brief.md` with `helper: explore-researcher`, `ask: <module root and focus>`, the module root as `outputs` context, and these `return:` fields: purpose, public surface with `file:line`, data owned, dependencies, configuration key names, security annotations, tests, hotspots, unknowns. Then return. The main session launches the helper (briefs for independent modules may run in parallel); continue from its result.
   - Every statement cites `path:line` or says `UNVERIFIED`.
7. **System documents.** From the module documents, write `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md` as-is (replace every `TEMPLATE:` line), `docs/agents-v0/design/system/context-map.md` (the contexts and integrations that exist today, sync or async per boundary), and `docs/agents-v0/adr/0000-inherited-decisions.md` (decisions the code evidences, such as framework choice, database per service or shared database, sync or async, each with a citation and the status `Accepted (inherited)`). For each flow the user named, write `docs/agents-v0/diagrams/sequences/<service>.md` (Mermaid, `architecture-and-diagrams.mdc`), each step citing the code.
8. **API inventory.** Compare `docs/agents-v0/discovery/endpoints.txt` with the OpenAPI files the repo has. List endpoints missing from the contract, contract paths with no controller, and whether the spec is generated or hand-written.
9. **Security baseline.** Summarize `docs/agents-v0/discovery/security-baseline.md` in the report: unannotated mappings, permit-all, CSRF or CORS findings, literal secrets by file and key (`placeholder` entries are dummy tokens, not real secrets). Do not fix anything. A permit-all outside local configuration or a real literal secret (`LITERAL-IN-FILE`) is reported to the user at once, then listed for `/v0-maintain`.
10. **Mandated docs.** Make sure `README.md` states the build, run, and test commands from the profile. Add only what is missing. When the program spans repos, copy `templates/docs/agents-v0/workspace.manifest.json` to `docs/agents-v0/workspace.manifest.json` and fill it in.
11. **Verify.** Check every citation resolves, no `TEMPLATE:` line remains, and each document has its `commit:` line; the guard's `ready` step runs `check-onboarding-docs.sh` and names what to fix. Repeat each `UNVERIFIED` in the report's open questions.
12. **Report and stop.** Fill `docs/agents-v0/onboarding/report.md` and `docs/agents-v0/onboarding/phase-result.md`, return to the main session, and stop. Never edit `state.json`; the main session runs `ready`, and only the user approves.

## Rule-compliance checklist
- [ ] `workflow-orchestration.mdc`: baseline documented; profile complete; stopped for approval.
- [ ] `project-delivery-core.mdc`: mandated docs (README, architecture, network, sequences) as-is; stack deviations recorded.
- [ ] `architecture-and-diagrams.mdc`: Mermaid conventions; database ownership shown as it is.
- [ ] `security-baseline.mdc`: no secret value anywhere; literal secrets reported by key only.
- [ ] Every statement cites code or says `UNVERIFIED`; no `TEMPLATE:` line left.
- [ ] No weakening of security controls through an undocumented profile exception; no application file edited.
