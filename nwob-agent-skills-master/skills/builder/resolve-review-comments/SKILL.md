---
name: resolve-review-comments
description: >-
  Implements only the pasted GitLab review comments on the MR source branch,
  verifies, and drafts thread replies. Use when /audit requested changes and the
  author must address comments. Commit and push only after the user confirms.
---

# Resolve GitLab review comments

Read pasted GitLab review text, change only the code those comments require, verify, then draft replies the human can paste into GitLab. Reply draft shape lives in [merge-request-patterns.md](../../../references/rules/merge-request-patterns.md).

The human posts replies in GitLab. This skill does not fetch comments from GitLab, post notes, or call GitLab APIs.

Boundaries: [builder-skill-boundaries.md](../../../references/rules/builder-skill-boundaries.md).

This skill is not `/audit`. The auditor does not implement. If a `story-tasks.md` ID is still unfinished, use `trigger-ai-build` instead.

## When to use

- `/audit` or a peer requested changes, and the user pasted GitLab review comments in chat.
- The user asks to address, resolve, or reply to MR review comments.
- The author of Sessions 1 through 4 is running as Builder.
- The prompt names the MR source branch (`MR_BRANCH` or `${STORY_CONTEXT.MR_BRANCH}`).

If the user asks to approve, merge, or re-audit, stop.

## Workflow

### Step 1: Confirm scope

Work in `repositories/{SERVICE}/` on the MR source branch from the prompt. Fetch and check out that branch if it is not already current.

If the chat has no pasted review comments, ask the user to paste them and stop.

### Step 2: List the pasted comments

Parse the pasted GitLab review text. List each comment: file, line, the ask, and open or resolved when the paste includes that.

Ignore bot and system notes unless they block merge. Do not invent comments from the audit report. Use only the pasted text.

### Step 3: Implement only those comments

Change application code only to address the pasted comments.

If a `story-tasks.md` ID is still unfinished, stop that work here and tell the user to use `trigger-ai-build`.

Do not author `story-tasks.md` or `story-tasks.md` or ADRs.

Run the story verify commands. Use `mvn clean verify`, or the Verify block on the locked execution plan. If verify fails, fix the comment-driven change. Do not claim done.

### Step 4: Draft the reply

Write a short reply: what changed, which comments are done, what is deferred and why. Print it.

If the clone has uncommitted or unpushed fixes, say so and include the `git commit` and `git push` commands you would run.

Stop and ask.

### Step 5: Git after yes

If the user says no, revise the reply or the diff. Do not commit or push.

If the user says yes, run only the confirmed `git commit` and `git push`. Do not post to GitLab. The human pastes the reply into GitLab if they choose.

Print confirmation. Do not approve or merge. Session 5 Lead Builder re-runs `/audit` after the author pushes.

## Constitution compliance

Mandatory: edit application code only to address pasted MR comments. Verify before you claim done. Commit and push only after the user says yes. Do not approve, merge, audit, or post to GitLab. Do not author `story-tasks.md` or `story-tasks.md` or ADRs.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints) still apply to any code change.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| The auditor can fix while reviewing | `/audit` does not implement. The author runs this skill. |
| Fold this into `trigger-ai-build` | Unfinished `story-tasks.md` IDs go to Session 3. Pasted comments go here. |
| Reply or push without asking | Print the draft. Commit and push only after the user says yes. |
| Approve once comments are done | The Session 5 human approves and merges. |
| Also land the next `story-tasks.md` item | Out of scope. Use `trigger-ai-build`. |
| Skip verify. The comment was a rename | Run the story verify commands before you claim done. |
| Fetch comments from GitLab | Use the pasted GitLab review text. Do not call GitLab APIs. |

## Red flags

- Started by the Session 5 auditor under `/audit`.
- Code changes unrelated to pasted comments.
- Comments invented from the audit report instead of pasted GitLab text.
- `story-tasks.md` / `story-tasks.md` or ADRs authored here.
- Commit, push, or GitLab post without the user saying yes.
- GitLab fetch, post, approve, or merge.
- Verify skipped.
- Unfinished `story-tasks.md` IDs implemented here instead of `trigger-ai-build`.

## Verification

- [ ] MR branch confirmed, and pasted review comments present in chat?
- [ ] Each relevant comment listed with file, line, ask, and status when present?
- [ ] Diff limited to those comments?
- [ ] Story verify commands run and passing?
- [ ] Reply drafted and shown, no commit or push until the user said yes?
- [ ] No GitLab post, approve, merge, audit report, `story-tasks.md`, `story-tasks.md`, or ADR write?
- [ ] Unfinished `story-tasks.md` IDs routed to `trigger-ai-build`?
