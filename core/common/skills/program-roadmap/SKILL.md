---
name: program-roadmap
description: Roadmap playbook. Turn one discovery file, at a path the user names, into a now / next / later sequence. Do not rediscover the problem.
---

# program-roadmap

Roadmap playbook for the `roadmap-planner` agent (`workflow-orchestration.mdc` Phase Gates Summary).

## Steps
1. Take the discovery path from the user. Refuse to guess a file. Refuse a path that is absolute, contains `..`, or points outside the repository.
2. The discovery document at `<discovery-path>` was pre-validated by `guard-roadmap.sh validate` before this agent was launched. Read that file and nothing else about the problem. Required headings: Problem, Success metric, Options, Chosen option, In scope, Out of scope. Stop and report if any heading body is missing, empty, or still a placeholder (`<...>`, `[...]`, `TBD`, `TODO`, `FIXME`, `XX`/`XXX`, `__`, `???`).
3. Every In scope leaf item must belong entirely to one horizon. When an In scope parent bullet groups nested sub-bullets, either keep the nested block together in one horizon or place each leaf sub-item in its respective horizon. If a single leaf item bundles work intended for multiple delivery phases, stop and ask the user to split the item into sub-items in the discovery document. Do not invent derivative themes or split a leaf item across horizons.
4. Write `docs/agents-v0/roadmap/<program>.md` using `docs/agents-v0/roadmap/_template.md`. Set `Discovery:` to the path the user gave and its sha256 checksum (`Discovery: <path> (sha256: <hash>)`). Copy Problem, Success metric, Chosen option, and Out of scope as facts. Leave the `Delivery approvals` table without an `Approved` row. When the discovery file has a line `Stack preference:`, copy that line onto the roadmap as written. Do not activate a pack from it.
5. Place each In scope item in exactly one of Now, Next, or Later. The item text is copied verbatim. Do not invent a theme. Do not move an Out of scope item into a horizon.
6. Verify the roadmap content gate before reporting done: every required heading is filled, `Discovery:` has the sha256 checksum, and every In scope item belongs to one horizon.
7. Return completion to the main session. The main session records the phase result and sets the state to awaiting_approval. Do not run any commands or attempt self-approval. Sensei reviews the sequence and approves externally in his own terminal outside Cursor.

8. Do not write milestone stories, acceptance criteria, or an ARC record in this skill. `/v0-architecture` writes the ARC record. `/v0-plan` writes the stories. `/v0-intake` writes the Gherkin. `/v0-design` writes the feature contract.

## Rule-compliance checklist
- [ ] Preflight validation passed on `<discovery-path>` (all required headings present and non-placeholder).
- [ ] The discovery path and its sha256 checksum are recorded on `Discovery:`.
- [ ] No heading was filled in by the agent.
- [ ] Every In scope item belongs to exactly one horizon; no invented themes.
- [ ] The discovery file was not copied into `docs/agents-v0/`.
- [ ] `workflow-orchestration.mdc`: Roadmap gate met; stopped for approval.
