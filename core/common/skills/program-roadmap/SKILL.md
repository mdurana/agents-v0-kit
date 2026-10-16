---
name: program-roadmap
description: Roadmap playbook. Turn one discovery file, at a path the user names, into a now / next / later sequence. Do not rediscover the problem.
---

# program-roadmap

Roadmap playbook for the `program-planner` agent (`workflow-orchestration.mdc` Roadmap).

## Steps
1. Take the discovery path from the user. Refuse to guess a file. Refuse a path that is absolute, contains `..`, or points outside the repository.
2. Read that file and nothing else about the problem. Required headings: Problem, Success metric, Options, Chosen option, In scope, Out of scope. Stop and name the first heading whose body is missing, empty, or still a placeholder.
3. Write `docs/agents-v0/roadmap/<program>.md` using `docs/agents-v0/roadmap/_template.md`. Set `Discovery:` to the path the user gave. Copy Problem, Success metric, Chosen option, and Out of scope as facts. When the discovery file has a line `Stack preference:`, copy that line onto the roadmap as written. Do not activate a pack from it.
4. Place each In scope item in exactly one of Now, Next, or Later. The item text is copied. Do not invent a theme. Do not move an Out of scope item into a horizon.
5. Present the sequence and wait for explicit approval. Then append the `roadmap` row:

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | roadmap | docs/agents-v0/roadmap/&lt;program&gt;.md, &lt;discovery path&gt; | &lt;name&gt; | Approved | &lt;date&gt; |

6. Do not write milestone stories, acceptance criteria, or an ARC record in this skill. `/v0-architecture` writes the ARC record. `/v0-plan` writes the stories. `/v0-intake` writes the Gherkin. `/v0-design` writes the feature contract.

## Rule-compliance checklist
- [ ] The discovery path is the one the user passed, recorded on `Discovery:`.
- [ ] No heading was filled in by the agent.
- [ ] Every Now / Next / Later item is an In scope item from that file.
- [ ] The discovery file was not copied into `docs/agents-v0/`.
- [ ] `workflow-orchestration.mdc`: Roadmap gate met; stopped for approval.
