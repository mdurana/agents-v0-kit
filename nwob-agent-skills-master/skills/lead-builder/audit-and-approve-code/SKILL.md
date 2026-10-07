---
name: audit-and-approve-code
description: >-
  Audits an MR branch with git, writes the SDD audit report, and prints a GitLab
  review draft from the same findings. Use when the user invokes /audit and an
  MR is ready for Lead Builder QC before QA.
---

# Audit a merge request

Inspect the MR source branch with git, audit it against SDD artifacts and [builder-quality-patterns.md](../../../references/rules/builder-quality-patterns.md), write `audit-report.md`, then print a GitLab review from the same findings.

Authoritative detail: [git-delivery-standards.md](../../../references/rules/git-delivery-standards.md), [implementation-quality-standards.md](../../../references/rules/implementation-quality-standards.md) (including Java SonarQube / quality gates when Java applies).

The human posts the review and approves or merges in GitLab. This skill does not edit the branch, post GitLab notes, or call GitLab APIs.

Boundaries: [lead-builder-skill-boundaries.md](../../../references/rules/lead-builder-skill-boundaries.md).

Increment review is `review-implementation`. This skill is the MR gate (`/audit`). Do not implement fixes. Do not approve or merge the MR.

## When to use

- The user invokes `/audit`.
- All increments passed `review-implementation`, or the report documents a brownfield or peer MR.
- Application code exists on the MR source branch.
- The prompt names the MR source branch (`MR_BRANCH` or `${STORY_CONTEXT.MR_BRANCH}`).

## Workflow

### Step 1: Confirm upstream

If increment reviews are present, confirm they passed.

If increment reviews are missing because the branch was not built with NWOB, document brownfield or peer MR in the report and continue. Do not refuse the review for that reason alone.

Confirm `epic-spec.md`, in-scope `story-spec.md` + `story-tasks.md`, and the design package as they apply. Resolve effective stack and data lifecycle per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

If SDD artifacts are missing and this is not a documented brownfield review, stop.

Do not skip `/audit` because CI is green.

### Step 2: Read the branch

From `repositories/{SERVICE}/`, or the clone named in the prompt:

1. Fetch and check out the MR source branch from the prompt.
2. Read the base branch from the locked execution plan under `~/.cursor/plans/`, or from Session 4 draft output in the chat.
3. Run `git log <base>...<MR_BRANCH> --oneline`, `git diff --stat`, and `git diff` for the full range.
4. Read every changed file on that branch before you judge.

If Session 4 printed draft title, body, or branch names and they are not in the chat, ask the user to paste them.

### Step 3: Audit the diff

Review against `epic-spec.md`, `epic-spec.md` backlog index, `story-tasks.md`, in-scope `story-tasks.md`, the design package, and the working code. Apply builder-quality-patterns:

1. The MR audit checklist.
2. The MR standards checklist. Mark each cluster Pass, Fail, or N/A.
3. The finding schema: File and Line, What, How to verify, Why or Impact, Suggested fix, Severity.
4. The code simplification pass after functional correctness.
5. Constitution QC.
6. Design fidelity. Route ADR gaps to `architecture-governance`.

Do not load `references/agent-skills-main/skills/*/SKILL.md` when this embed applies.

### Step 4: Persist the SDD report

Fill [templates/lb/audit-report-template.md](../../../templates/lb/audit-report-template.md). Write `nwob-docs/observations/audit-report.md`. Do not leave findings only in chat.

### Step 5: Print the GitLab draft

Render the GitLab Output Format from the same findings. Print it in chat. Do not write a second opinion.

Map verdicts: `APPROVE` is Approved, ready for QA. `REQUEST CHANGES` is Changes requested.

Stop. Do not post to GitLab. The human copies the draft into GitLab if they choose.

### Step 6: Route the outcome

If the verdict is `APPROVE`, the MR is ready for QA handoff after the human approves in GitLab.

If the verdict is `REQUEST CHANGES`, the author uses Builder `resolve-review-comments` with pasted GitLab comments. If a `story-tasks.md` ID is still unfinished, the author uses `trigger-ai-build`. The auditor does not implement.

## Constitution compliance

Mandatory: audit the MR against SDD and the design package. Inspect the full branch diff with git before you write the report. Findings use the full schema. Both renderings come from one finding set. The agent does not approve, merge, implement, or post to GitLab.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints).

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| Increments already reviewed, skip MR audit | Holistic audit catches integration gaps and story coverage. |
| CI is green, approve | CI does not verify Gherkin AC or design fidelity. |
| Write a fresher GitLab review in chat | Render both artifacts from the same findings. |
| Post the review from here | Print the draft. The human posts in GitLab. |
| Fix the code while auditing | The author uses `resolve-review-comments` or `trigger-ai-build`. |
| Approve or merge from the agent | Forbidden. The human approves and merges after an Approved report. |
| Increments missing, refuse the peer MR | Document brownfield. Audit the diff with the full checklist. |
| Use the reference code-review SKILL.md | Use builder-quality-patterns. |
| Need an MR URL | Use the source branch and git diff. |

## Red flags

- MR judged without checking out the branch and reading the full git diff.
- Findings without File and Line when the issue is in the diff.
- GitLab draft contradicts `audit-report.md`.
- Agent posted to GitLab, edited the branch, or approved or merged.
- Auditor implemented fixes under `/audit`.
- Report not written under `nwob-docs/observations/`.

## Verification

- [ ] MR branch checked out and full `git log` / `git diff` run against the base branch?
- [ ] MR reviewed against spec, plan, tasks, and design package?
- [ ] MR audit checklist and standards clusters applied?
- [ ] Each finding has File and Line when applicable, What, How to verify, Why or Impact, Suggested fix, Severity?
- [ ] `audit-report.md` written from the template?
- [ ] GitLab Output Format printed from the same findings?
- [ ] No branch edits, GitLab post, approve, or merge?
- [ ] Constitution QC verified?
- [ ] Verdict aligned between the report and the GitLab draft?
