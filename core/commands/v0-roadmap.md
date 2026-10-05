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
Continue from `docs/agents-v0/roadmap/<program>.md` when it already records `Discovery:` as the path the user gave. Do not recreate it. Replacing the discovery document means the user points this command at the new path and approves the roadmap again.

## Collision
The roadmap file and the discovery path it records are shared for that program. Stop before editing either when `git status` shows it is already modified.

## Instructions
1. Launch the `program-planner` subagent with the discovery path. It follows `program-roadmap`.
2. Read only that file. It must contain these headings, each with a body that is not empty and not a placeholder (`<...>`, `[...]`, or `TBD`): Problem, Success metric, Options, Chosen option, In scope, Out of scope. A missing or placeholder heading stops the command. Name the heading. The person completes it in the discovery file. Run this command again from that same path.
3. Write `docs/agents-v0/roadmap/<program>.md` from `docs/agents-v0/roadmap/_template.md`. The `Discovery:` line is the path the user gave, relative to the repository root, with no `..`. Now, Next, and Later contain only items copied from In scope under the chosen option. Do not add a theme, reopen an option, or interview.
4. Check the **Roadmap gate** (`workflow-orchestration.mdc`): the discovery path is recorded, every theme is an in-scope item from that file, and out-of-scope items appear only under Out of scope.
5. **Stop** and present the sequence. After explicit user approval, append the `roadmap` row (Decision: `Approved`, approver, date, this file and the discovery path) to the roadmap's `Delivery approvals` table. That approval covers the sequence. The discovery file has no kit approval row. Do not start `/v0-plan` without the `roadmap` row.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `architecture-and-diagrams.mdc`.
