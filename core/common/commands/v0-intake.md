---
description: Intake phase. Turn a Jira/Confluence spec into the requirements artifact with acceptance criteria, NFRs, regulations, and the approvals table.
---

# /v0-intake

You are entering the **Intake** phase of the delivery lifecycle (`workflow-orchestration.mdc`).

## Resume
Once `docs/agents-v0/requirements/<feature>.md` exists, run `sh .agents-v0/scripts/sync-feature-state.sh docs/agents-v0/requirements/<feature>.md --active-phase intake --status in_progress`. If this phase is already `in_progress` or `blocked`, continue from that file; do not recreate it. On a blocker, re-run with `--status blocked --reason "<one line>"` and stop. When the gate is ready for the user, re-run with `--status awaiting_approval` and stop. Do not add an `Approved` row until the user approves (`workflow-orchestration.mdc` Phase resume).

## Prerequisite
Brownfield: when `docs/agents-v0/onboarding/report.md` exists, its `Delivery approvals` table must record an `Approved` `onboard` row. When application source exists, `docs/agents-v0/project-profile.md` still has placeholder verify commands, and no onboarding report exists, stop and run `/v0-onboard` first. Do not infer the onboarding approval. A story that belongs to a milestone manifest also needs every story named in its Dependency column to have an `Approved` Verify row in its own artifact; otherwise stop and report the first unmet dependency (`.agents-v0/ci/check-milestone.sh` enforces this at Build).

## Collision
While another feature is in flight in this checkout, write only `docs/agents-v0/requirements/<feature>.md`, its state file, and the feature's helper brief. Stop before editing a shared file (`workflow-orchestration.mdc` Parallel features) when `git status` shows it is already modified, and record `--status blocked` with that reason.

## Instructions
0. Classify **change tier** (`workflow-orchestration.mdc`): **Trivial** → `/v0-triage` instead of full Intake; **Major** → record in the artifact and require `system-design` outputs in `/v0-design`.
1. Launch the `requirements-analyst` subagent with the source spec (Jira/Confluence/user description).
2. **Helpers.** If `docs/agents-v0/requirements/<feature>.helper-brief.md` exists, launch the helper it names (`explore-researcher` unless the brief says otherwise) from this session. Pass the result into a second launch of `requirements-analyst`. Delete the brief after that result is back. Launch each brief once (`workflow-orchestration.mdc` Helper agents).
3. The analyst must follow the `spec-intake` skill and produce `docs/agents-v0/requirements/<feature>.md`. Record the user story as `As a [role], I want [goal], so that [benefit].` Copy the milestone row when the story belongs to a program. If that sentence still contains `<...>` placeholders, or omits `so that`, stop and ask the user to supply the missing role, goal, or benefit; do not invent them. Split the goal and each constraint into `AC-1`, `AC-2`, … with one Gherkin scenario per id (`### AC-n — <name>`, `Kind:`, `Given` / `When` / `Then`) and keep out of scope as its own list. Each `Then` names an observable result. At least one scenario is `Kind: negative` or `Kind: edge`, unless `Negatives: N/A: <reason>` and no security-review trigger applies. A trigger (auth, upload, RBAC, public route) needs a `Kind: negative` whose `Then` is a refusal. Record Preconditions and a Desk check. Record `Material: yes` when the story adds a service, a datastore, a security boundary, or a breaking API; otherwise `Material: no`. Also record NFRs, regulations, security-review triggers (`none` or the triggers that apply), and open questions (`none` once resolved); add milestone/story links and `Milestone file:` when the story belongs to a milestone program — `docs/agents-v0/milestones/<milestone>.md`. Apply the story-size budget: one surface unless the user asked for a vertical slice, and at most eight criteria (`AC-1` through `AC-8`), including the required negative. When the milestone Surface cell is `backend`, `bff`, or `frontend`, copy it to `Surfaces:`. When it is `vertical slice`, record `Vertical slice: yes` and set `Surfaces:` to the surfaces that journey crosses. Do not copy the words `vertical slice` into `Surfaces:`. The seeded P0-A platform skeleton records `Vertical slice: yes` and only the four acceptance criteria named on `docs/agents-v0/milestones/p0-platform-skeleton.md`. Do not write `## Proposed split` for that story. Any other oversized story stops on `## Proposed split` until the user approves the split. Do not run `check-intake.sh` while that section is open.
4. The UI is the bound pack's `ui` id. The React example is React 19, TypeScript 5.9, and Vite 7.
5. For UI-affecting changes, record UX requirements: WCAG 2.1 AA target, device/browser matrix, design-system reference, UX acceptance criteria.
6. Resolve open questions with the user.
7. Check the **Intake gate** (`workflow-orchestration.mdc`):
   - User story recorded as `As a [role], I want [goal], so that [benefit].`
   - Acceptance criteria split from that story and its constraints (`AC-1`, `AC-2`, …), one Gherkin scenario per id, with `Kind` and an observable `Then`. Out of scope is a separate list. One scenario is `Kind: negative` or `Kind: edge`, or `Negatives: N/A: <reason>` when no security-review trigger applies. Preconditions and a desk check are recorded. NFRs and regulations recorded. `Material:` is `yes` or `no`.
   - Story size: `Surfaces:` is one of `backend`, `bff`, or `frontend`, unless `Vertical slice: yes`. When the profile lists `Service roots`, a backend or BFF story also records `Service root:`. At most `AC-8`. No open `## Proposed split`.
   - Open questions are `none`.
   - Security-review triggers identified. A trigger has a refusing `Kind: negative`.
   - For UI-affecting changes: UX requirements recorded.
   - `sh .agents-v0/ci/check-intake.sh docs/agents-v0/requirements/<feature>.md` exits 0. Fix and re-run until it does. Do not present the gate on a failing check.
8. **Stop** and present the gate result to the user. Write `docs/agents-v0/requirements/<feature>.phase-result.md` (`workflow-orchestration.mdc` Phase result), including `user_story`, `ac_count`, `negative_count` (negative plus edge), `regulations`, and `open_questions`, each copied from the requirements artifact. After explicit approval, record the Intake decision (Decision: `Approved`), approver, date, and requirements-artifact path in its `Delivery approvals` section. Do not advance to Design without that approval.

## P0 skeleton
When the story is P0-A from `docs/agents-v0/milestones/p0-platform-skeleton.md`, do not launch `requirements-analyst` and do not write the requirements file. The next command is `/v0-build`. That command copies the user story and AC-1 through AC-4 from the milestone, then writes the N/A design and pins it. Release records the Intake row with the others from the one approval at the end.

## Rules
`workflow-orchestration.mdc`, `ai-agent-conduct.mdc`, `project-delivery-core.mdc`, `frontend-web.mdc`, `security-baseline.mdc` §11.
