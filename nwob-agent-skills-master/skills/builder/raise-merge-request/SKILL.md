---
name: raise-merge-request
description: >-
  Drafts GitLab merge request title, body, and branch names after every story-tasks.md
  ID for the story is done and review-implementation approved the last increment.
  Use when the user asks to draft, open, or raise MR copy, and trigger-ai-build
  has stopped.
---

# Raise a GitLab merge request

Draft merge request copy for a completed story so Session 5 can audit it. Title, body, and mermaid live in [merge-request-patterns.md](../../../references/rules/merge-request-patterns.md). Do not invent a second shape.

Git law (one branch per ticket, no commit or push, human opens GitLab): [git-delivery-standards.md](../../../references/rules/git-delivery-standards.md).

The human opens the MR in GitLab. This skill does not commit, push, or call GitLab APIs.

Boundaries: [builder-skill-boundaries.md](../../../references/rules/builder-skill-boundaries.md).

## When to use

- Every `story-tasks.md` ID for the story is complete.
- Lead Builder `review-implementation` approved the last increment.
- The user asks to draft, open, or raise merge request copy.
- `trigger-ai-build` has stopped.

If the user asks to approve, merge, or audit, stop. Those are Session 5.

## Workflow

### Step 1: Confirm gates

Work in `repositories/{SERVICE}/`. Limit the diff to the Jira ticket.

Read the source branch and the base branch from the locked execution plan under `~/.cursor/plans/`.

If a story `story-tasks.md` ID is still open, or the last increment is not Approved, stop.

### Step 2: Identify changes

Run these against the base branch from Step 1:

1. `git log <base>...HEAD --oneline`
2. `git diff <base>...HEAD --stat`
3. `git diff <base>...HEAD`
4. `git status`

Read the changed files and the call chains they touch. Draft from that diff and from `epic-spec.md`, not from commit messages alone. Schema: merge-request-patterns. Law: git-delivery-standards.

### Step 3: Draft title and body

Fill title and body from merge-request-patterns. Scale extra sections to the size of the change.

If the story spans more than one clone, draft one MR per clone. Put `{STORY_ID}` and every `story-tasks.md` ID for that clone in Technical Context.

### Step 4: Print the draft and stop

Print:

1. Draft title
2. Draft body (full markdown)
3. Source branch name
4. Base branch name

Stop. Do not edit files under `repositories/{SERVICE}/`. Do not run `git commit` or `git push`. Do not approve, merge, or audit. Do not write `nwob-docs/observations/audit-report.md`.

## Constitution compliance

Mandatory: start only after every story `story-tasks.md` ID is complete and the last increment is Approved. Follow git-delivery-standards (no commit, push, or GitLab APIs). Title uses `[<JIRA-PROJECT>-<JIRA-Ticket-Number>]` from `constitution-custom.mdc` (e.g. `[PROJ-12345]`), not `{STORY_ID}`. Body follows merge-request-patterns (Business Context and Technical Context; not from commit messages alone). Technical Context lists `{STORY_ID}` and every `story-tasks.md` ID for the clone. Do not approve, merge, audit, or send the MR to QA.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints) do not apply to MR drafting.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| Fold MR draft into `trigger-ai-build` | This skill is Session 4. It starts after the last increment. |
| Title with story id only is clearer | Use `[<JIRA-PROJECT>-<n>]` from `constitution-custom.mdc`. Put the story id in Technical Context. |
| A task-id list is enough for the body | Business Context and Technical Context headings are required. |
| Commit or push so the MR is ready | The human opens the MR. This skill drafts copy only. |
| Body from commit messages is fine | Draft from the diff and from `epic-spec.md`. |
| Approve or merge while we are here | Forbidden. Session 5 owns audit. The human approves and merges. |

## Red flags

- Skill started before every story `story-tasks.md` ID is complete, or before last-increment approval.
- Title uses `{STORY_ID}` instead of `[<JIRA-PROJECT>-<JIRA-Ticket-Number>]`.
- Body is missing Business Context or Technical Context.
- Diff outside the Jira ticket or the wrong clone.
- File edits, commit, push, GitLab API calls, approve, merge, an audit report, or a QA send.

## Verification

- [ ] Every `story-tasks.md` ID complete, and last increment Approved by `review-implementation`?
- [ ] Work scoped to `repositories/{SERVICE}/` and the Jira ticket?
- [ ] Branches taken from the locked execution plan under `~/.cursor/plans/`?
- [ ] Title and body follow merge-request-patterns?
- [ ] `{STORY_ID}` and every `story-tasks.md` ID in Technical Context?
- [ ] Draft title, body, source branch, and base branch printed?
- [ ] No file edits, commit, push, approve, merge, audit report, or QA send?
