---
name: program-roadmap
description: Roadmap playbook. Turn one discovery file, at a path the user names, into a now / next / later sequence. Do not rediscover the problem.
---

# program-roadmap

Roadmap playbook for the `program-planner` agent (`workflow-orchestration.mdc` Roadmap).

## Steps
1. Take the discovery path from the user. Refuse to guess a file. Refuse a path that is absolute, contains `..`, or points outside the repository.
2. Validate the discovery document using `sh .agents-v0/ci/check-roadmap.sh --preflight <discovery-path>`. Read that file and nothing else about the problem. Required headings: Problem, Success metric, Options, Chosen option, In scope, Out of scope. Stop and name the first heading whose body is missing, empty, or still a placeholder (`<...>`, `[...]`, `TBD`, `TODO`, `FIXME`, `XX`/`XXX`, `__`, `???`).
3. Every In scope leaf item must belong entirely to one horizon. When an In scope parent bullet groups nested sub-bullets, either keep the nested block together in one horizon or place each leaf sub-item in its respective horizon. If a single leaf item bundles work intended for multiple delivery phases, stop and ask the user to split the item into sub-items in the discovery document. Do not invent derivative themes or split a leaf item across horizons.
4. Write `docs/agents-v0/roadmap/<program>.md` using `docs/agents-v0/roadmap/_template.md`. Set `Discovery:` to the path the user gave and its sha256 checksum (`Discovery: <path> (sha256: <hash>)`). Copy Problem, Success metric, Chosen option, and Out of scope as facts. Leave the `Delivery approvals` table without an `Approved` row until the user approves in step 7. When the discovery file has a line `Stack preference:`, copy that line onto the roadmap as written. Do not activate a pack from it.
5. Place each In scope item in exactly one of Now, Next, or Later. The item text is copied verbatim. Do not invent a theme. Do not move an Out of scope item into a horizon.
6. Verify the roadmap content gate before asking for approval: run `sh .agents-v0/ci/gate.sh roadmap docs/agents-v0/roadmap/<program>.md` (which runs `check-roadmap.sh`).
7. Present the sequence and wait for explicit approval. Then append the `roadmap` row and verify with `sh .agents-v0/ci/gate.sh roadmap --approved docs/agents-v0/roadmap/<program>.md`:

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | roadmap | docs/agents-v0/roadmap/<program>.md, <discovery path> | <name> | Approved | <date> |

8. Do not write milestone stories, acceptance criteria, or an ARC record in this skill. `/v0-architecture` writes the ARC record. `/v0-plan` writes the stories. `/v0-intake` writes the Gherkin. `/v0-design` writes the feature contract.

## Rule-compliance checklist
- [ ] Preflight validation passed: `check-roadmap.sh --preflight <discovery-path>`.
- [ ] The discovery path and its sha256 checksum are recorded on `Discovery:`.
- [ ] No heading was filled in by the agent.
- [ ] Every In scope item belongs to exactly one horizon; no invented themes.
- [ ] The discovery file was not copied into `docs/agents-v0/`.
- [ ] `workflow-orchestration.mdc`: Roadmap gate met; stopped for approval.
