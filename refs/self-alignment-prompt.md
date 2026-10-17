Re-check the agents-v0 kit for docs-versus-workflow misalignment. Fix only a sentence you can prove is false, or a map sentence whose absence would make an agent skip a step the procedure requires. Do not close a workflow gap by editing.

Source of truth, in order:
1. What the check actually does: templates/.agents-v0/ci/*.sh, the GitLab job that calls it, scripts/install.sh, scripts/activate-stack-pack.sh, and the pack manifest the command names (pack.json, including ui when that field is an id).
2. The phase command: core/common/commands/v0-*.md. The command holds the step list.
3. The skill and the agent that the command names for that step.
4. An always-on rule only where it states a rule for every phase. workflow-orchestration.mdc does not override a command's step list.
5. Maps: templates/docs/agents-v0/agents-v0-kit.md, user-guide.md, greenfield-onboarding.md, brownfield-onboarding.md, README.md, and AGENTS.md. Change a map to match 1–4.

Trace every phase once: onboard, roadmap, architecture, plan, intake, design, build, verify, local-release, release, maintain, triage, deliver, status. For each phase, compare the command, the named skill, the named agent, the CI script that phase runs, and the map sentences for that phase.

Classify each finding:
- False sentence. A sentence would make an agent or a reviewer do something the higher source will not do, or two procedure files contradict each other. Fix the lower source. A script stays as it is.
- Skipped step. A map is shorter, and a person following only that map would skip a step the command requires. Add that step to the map. A shorter summary may stay when it points at the command and leaves the step out without denying it.
- Needs a decision. The commands agree and the script or activator is weaker, a page is never read by a command, a skill, or a CI script, or the fix would be a new phase, contract type, MCP server, core.hooksPath, or CI gate. Do not edit. List the file, the sentence or the missing check, and which source is weaker.

Already settled, keep these unless a script has changed:
- coverage_ratchet is a dated waiver record. It does not change JaCoCo 0.80 in core/java/starters/maven/quality-plugins.xml. The GitLab coverage-ratchet job does not pass LINE_COVERAGE_PCT, so check-coverage-ratchet.sh checks the approver and the removal date, and compares a measured number only when LINE_COVERAGE_PCT or JACOCO_LINE_PCT is set. Changed lines stay at 80% when DIFF_BASE is set.
- No messages means the Events section of design.md is `N/A: no event contract`. check-design.sh requires that phrase when no event contract is present, and rejects it when `asyncapi.yaml` or `events/` exists.

Do not add a phase, a contract type, an MCP server, core.hooksPath, or a CI gate. Keep the three always-on rules at or under 32,000 bytes. Stay inside the file the finding names.

After the edits, re-read each changed sentence against the source above it. If a False sentence or a Skipped step remains, list it and fix it. When none of those two remain, stop. List every Needs a decision item still open. Do not say the docs and the workflow are aligned while that list has an entry.