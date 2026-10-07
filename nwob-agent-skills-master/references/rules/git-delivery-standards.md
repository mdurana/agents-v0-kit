# Git and delivery standards

Law for git workflow, conventional commits, and scoped merge requests. Mandated by `constitution-core.mdc`.

Draft MR title, body, mermaid, and reply shape live in [merge-request-patterns.md](merge-request-patterns.md). This file does not define that schema. Do not invent a second MR body or title template here.

Engagement-specific branch regex and title pattern live in `constitution-custom.mdc`.

Load this file during build (`trigger-ai-build`, `execution-plan-template.md`), Session 4 MR draft (`raise-merge-request`), and Session 5 peer MR audit (`audit-and-approve-code`).

---

## Branch workflow

| Rule | Requirement |
|------|-------------|
| One branch per ticket | Isolate work in exactly one feature branch per story or Jira ticket. Bundling multiple tickets into one branch is **forbidden**. |
| Feature branching | Branch from the project integration branch (for example `main` or `master` per engagement config). Delete the feature branch after a successful merge. |
| Branch naming | Layout (type prefix, date segment, ticket key, slug) is engagement-defined. See `constitution-custom.mdc`. |

---

## Conventional commits

Commit headers **must** follow:

```
<type>: <imperative description>
```

### Commit types

Use exactly one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.

### Imperative mood

| Good | Bad |
|------|-----|
| `feat: add inbox feed pagination` | `feat: added pagination` |
| `fix: validate upload size before parse` | `fix: fixes upload bug` |
| `refactor: extract pagination helper` | `refactor: updates` |

Vague messages (`fix bugs`, `updates`, `wip`) are **forbidden** and **must** be rejected in review.

### Traceability

Commits **should** reference the tracking ticket in an optional body or footer (`Fixes:`, `Refs:`, or `#<id>`). Use the ticket key from `constitution-custom.mdc`, not a placeholder project id invented here.

### Agent vs user commits

The agent **must not** run `git commit`, `git push`, or stage commits in Sessions 2–4 (`trigger-ai-build`, `review-implementation`, `raise-merge-request`). The agent **may** suggest a conventional commit message or branch name for the user to copy. See `execution-plan-template.md` Git rules section.

Session 6 (`resolve-review-comments`): commit and push **only** after the user says yes.

---

## Merge request law

| Rule | Requirement |
|------|-------------|
| Scoped MRs | Each merge request **must** align to a single story or tracking ticket, matching the one-branch-per-ticket rule. |
| Title and body | **Must** follow [merge-request-patterns.md](merge-request-patterns.md). Title pattern (ticket prefix) comes from `constitution-custom.mdc`. Do not draft the body from commit messages alone. |
| Who drafts | Session 4 `raise-merge-request` drafts copy. The human opens GitLab. `/audit` is not the MR creator. |
| Approval | GitLab Approve and Merge are human only. Agents **must not** approve or merge. Session 5 peer `/audit` writes a review draft. It is not GitLab approval. |

### MR hygiene (audit checklist)

Before QA handoff, verify:

- Title and body follow merge-request-patterns and trace to `plan.md` stories
- Commits are atomic per increment where feasible
- No unrelated changes outside sprint scope
- Branch is mergeable; CI green
- Branch naming and commit format match engagement rules

Detailed audit rows: [builder-quality-patterns.md](builder-quality-patterns.md) MR standards checklist (Git and packages cluster).

---

## When to load this file

| Trigger | Consumer |
|---------|----------|
| Suggesting commit messages or branch names | `trigger-ai-build`, execution plan |
| Dual-hat increment review after each `story-tasks.md` ID | `review-implementation` (same person **may** dual-hat with `trigger-ai-build`) |
| Session 4 MR draft (law only. Schema is merge-request-patterns) | `raise-merge-request`. Human opens GitLab. |
| Session 5 peer `/audit` (report and GitLab draft. Author must not self-audit) | `audit-and-approve-code` |
| GitLab Approve / Merge | Human only |
