# Agentic Workflow Guide

You can drive delivery in Cursor **without writing code**. You provide the business intent, answer questions, and **approve each phase** before work continues. Engineers and the AI handle implementation, testing, and security checks.

This guide matches the workflow in this kit: **Intake → Design → Build → Verify → Release** (and **Maintain** when something breaks or needs an update). The workflow runs identically in Cursor, Kilo Code, and Claude Code — the gates, approvals, and evidence are the same; only the command palette and agent menus differ per tool.

---

## What you need


| Item           | Notes                                                                                                |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| **Cursor**     | Desktop app with the project open (your team’s service repo, after the kit is installed).            |
| **Chat**       | Open the AI chat panel in that project.                                                              |
| **Your input** | A Jira ticket, Confluence page, email spec, or a short description in plain language.                |
| **Approvals**  | You say when each phase is good enough to continue (see [Gates](#the-five-gates-where-you-approve)). |


You do **not** need to run terminal commands, edit code, or pick AI models. Optional: ask your team to set the model picker to **Agent → Composer 2.5** for day-to-day chat.

---



## Quick start (three steps)

1. **Open chat** in the project that uses this workflow kit.
2. **Start work** with one of these (type in chat):
  - `/deliver` — full journey from requirements through release (stops at every gate).
  - `/intake` — only clarify and document requirements (good for early discovery).
3. **Paste your spec** right after the command, for example:
  ```text
   /intake

   Feature: Customer can download their annual tax statement from the portal.
   Users: retail banking customers (logged in).
   Must comply with internal data-privacy policy; no statement data in email links.
   Target: next quarterly release.
   Jira: PROJ-1234 (paste description if you have it)
  ```
4. When the AI **stops at a gate**, read the summary and reply `Approved` to continue, or describe what to change.

---



## Commands you can use


| Command     | When to use it                                                                                          |
| ----------- | ------------------------------------------------------------------------------------------------------- |
| `/plan`     | A big goal (a platform, several services): split it into milestones and ordered stories before any `/intake`. |
| `/intake`   | Turn a idea or ticket into clear requirements and open questions.                                       |
| `/design`   | After intake is approved — APIs, data flows, and architecture decisions.                                |
| `/build`    | After design is approved — actual software is written.                                                  |
| `/verify`   | After build is approved — automated tests and security review.                                          |
| `/release`  | After verify is approved — merge request readiness (GitLab), then completion after an authorized merge. |
| `/deliver`  | Run the whole chain; you approve at each gate.                                                          |
| `/maintain` | Bug, security patch, dependency update, or doc fix after go-live.                                       |
| `/triage`   | Small, low-risk change (typo, docs-only, version-only update). The change itself must qualify, and you confirm it before the lighter path starts. |
| `/onboard`  | First-time setup on an **existing** repo: documents what is there (modules, architecture, flows, security baseline) with sources cited, and records what it could not determine. You approve the report before intake. |
| `/status`   | Name the feature. An unfinished phase is run again from the saved files; a phase waiting on you does not start the next one. |


You can also write in normal language, for example: *“Run intake on PROJ-1234”* or *“We’re only doing design for the notifications feature.”* Using the slash commands is clearer for the workflow. When more than one feature is open, name it: `/status tax-statement`.

---

## If work was interrupted

`/status` plus the feature name reads the saved progress for that feature. It does not mark the phase approved, and it does not restart the chat that was cut off.

| What you see | What you do |
|--------------|-------------|
| The phase was still being written, or it stopped on a problem | Run the same command again (`/design`, `/build`, and so on). The AI keeps the files already saved and fills in what is missing. |
| The phase is waiting for you | Reply `Approved` or list what to change. A green build is not approval. The next phase does not start until you approve. |
| You did not name a feature | The AI lists the open features and asks which one you mean. |

---

## More than one feature

You can approve intake for a second feature while the first feature’s build is still waiting on you, then start design for the second feature. Each feature has its own requirements and design notes.

The second feature must not change a file the first one is already changing. Those shared files include the project profile, the shared API catalog, architecture notes, the README, and the application code. Intake and design for the second feature stay in its own requirements and design documents, including that feature’s own API draft. The shared API catalog is updated when that feature is built. Build, verify, release, and a fix after go-live stop if those shared files, or the other feature’s code, are already modified. Ask engineering for a separate branch before that work continues in the same checkout. Creating that branch still needs you to ask for it. The usual way is one working folder per feature: engineering runs `scripts/feature-worktree.sh <feature>` once you have said yes, and each feature then builds in its own folder without touching the others.

## Big goals: plan first

When the goal is larger than one story, start with `/plan` and paste the goal. The AI proposes the pieces (which parts of the system, which milestones, which stories, and in what order) and stops. You approve the plan once. Each story then runs through the five gates in the order the plan sets: a story cannot start building until the stories it depends on have passed Verify.

With many small stories you can approve the Intake or Design gate for several of them in one message, but only by naming each one, for example `Approved: Design for P2-A, P2-B, P2-C`. That is available only for ordinary stories with no security triggers and no open questions. Build, Verify, and Release are always approved one story at a time. "Approve all" does not count.

The AI also stops by itself when one phase has failed too many times in total (default 8 failed attempts). It reports what blocked it; engineering decides whether to raise the limit.

---



## The five gates (where you approve)

The AI **must not** skip ahead without your OK. Each gate ends with a short report: what was done, what’s ready, and what still needs your decision.

### 1. Intake gate

**Your question:** *Did we capture the right problem, success criteria, and rules?*


| You should see               | What it means                                                                                 |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| Acceptance criteria          | Testable “done” statements (who can do what, under which conditions).                         |
| NFRs                         | Speed, availability, audit needs (in plain language).                                         |
| Regulations / policies       | e.g. privacy, banking, or internal GXI items that apply.                                      |
| UX requirements (UI changes) | Accessibility target (WCAG 2.1 AA), devices/browsers, design system, and UX success criteria. |
| Open questions               | List should be empty or you’ve answered each one.                                             |


**You might say:**  

- `Approved — proceed to design.`  
- `Add acceptance criterion: user must confirm identity before download.`  
- `Regulation XYZ applies; include it.`

---



### 2. Design gate

**Your question:** *Is the solution shape right before we build?*


| You should see            | What it means                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| API / contract summary    | What systems talk to each other (not code — interfaces). The draft belongs to this feature. It is merged into the shared API catalog when the feature is built. |
| Diagrams                  | Flowcharts or sequence diagrams (who calls whom).                                                             |
| Design notes and review   | A short design document (every requirement mapped to what satisfies it; who may do what; what happens when a dependency fails) and an independent reviewer's findings. You approve once the reviewer has no open Critical item. The approved design is then locked: if building shows it is wrong, the AI stops and asks you to approve an amendment. |
| ADR (if needed)           | Short decision record for big choices (e.g. sync vs async).                                                   |
| UI stack (if new screens) | Team may ask **Svelte or React** once — pick what product/engineering agreed.                                 |
| UX spec and mockups (UI screens) | User flows, per-screen states (loading/error/empty), static HTML mockups, and the default behavior of each control. You approve the spec and the mockups together. |


**You might say:**  

- `Approved.`  
- `Change flow: notification email must not contain a direct download link.`  
- `Split read vs write APIs for audit.`

---



### 3. Build gate

**Your question:** *Did implementation finish without blocking errors?*


| You should see          | What it means                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Build / compile success | Software builds in the project’s standard way, starting from a known-good baseline. |
| Tests for new behavior  | New or changed features come with automated tests, written alongside the code.      |
| Quality checks          | Coverage, static-analysis, and security (CVE) checks run as part of the build.      |
| Scope summary           | Which parts were built (backend, BFF, screens).                                     |
| Security basics         | Login and permissions wired; no secrets in the repo.                                |


You usually **do not** review code line by line. Trust this gate for “engineering says it compiles, matches design, and the automated quality checks pass.”

**You might say:**  

- `Approved — run verify.`  
- `Hold — we changed policy on retention; update design first.` (sends work back)

---



### 4. Verify gate

**Your question:** *Is it tested and safe enough to release?*


| You should see           | What it means                                                            |
| ------------------------ | ------------------------------------------------------------------------ |
| Test results             | Automated tests passed; coverage targets met.                            |
| Security (VAPT) review   | Checklist for common risks (logout, permissions, uploads, etc.).         |
| Code review notes        | **Critical** = must fix before release; **Suggestion** = nice to fix.    |
| UX / accessibility check | Automated accessibility scan green; UX criteria tested (for UI changes). |


Tests finish first. The security checklist and the code review are prepared together, and you see one list of **Critical** items. If that list has anything on it, the AI should fix and re-run verify — you approve again when Critical items are gone.

**You might say:**  

- `Approved for release.`  
- `Critical on upload validation — fix before we approve.`

---



### 5. Release gate

**Your question:** *Are we ready to ship and document?*


| You should see | What it means                                                                                              |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| Docs updated   | README / architecture notes for what changed.                                                              |
| Merge request  | Ready for engineering merge (CI green). On GitLab this is a merge request. On GitHub it is a pull request. |
| VAPT sign-off  | Security checklist in the merge request description.                                                       |


"Ready" is not "released": the AI reports readiness and waits for an authorized human merge. On GitLab, after a person approves the merge request, engineering runs the manual **delivery-approval** job. Release is complete only after the merge and green CI are confirmed. Approving a phase does not by itself authorize committing, pushing, or opening a merge request; explicitly request those actions when needed.

**You might say:**  

- `Please open the merge request; engineering will merge after CI is green.`  
- `Wait for product sign-off on release notes.`

---



## Maintain (after go-live)

Use `/maintain` when:

- Users report a bug  
- Security or compliance asks for a patch  
- Dependencies need upgrading  
- Documentation is out of date

Describe the issue in plain language. The AI fixes, then runs **Verify** again. You approve if the fix and checks look good.

---



## How to write a good request

**Include:**

- **Who, what, and why** in one sentence: As a [role], I want [goal], so that [benefit].  
- **Constraints** (privacy, regions, deadlines, systems involved). Intake turns the sentence and each constraint into numbered acceptance criteria (`AC-1`, `AC-2`, …).  
- **Links** (Jira, Confluence, Figma) — paste text if you can’t link  
- **Out of scope** (what we are *not* doing), as its own list

**Example (good):**

```text
/intake

As a branch manager, I want to approve withdrawals over PHP 500k, so that large payments leave the region only with a local approver.
The approver must be in the same region as the account.
The audit log must record who approved and when.
Not in scope: mobile app this quarter.
```

**Example (too vague):**

```text
Make the portal better.
```

---



## Glossary


| Term                   | Meaning for you                                                                                                   |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------- |
| **Gate**               | A pause point where you approve or send work back.                                                                |
| **Intake**             | Capture and agree requirements before building.                                                                   |
| **Design**             | Plan interfaces, data, and flows before code.                                                                     |
| **UX spec**            | The screen-by-screen plan: flows, states, default behavior of each control, and links to HTML mockups — approved with those mockups at the Design gate. |
| **Build**              | Write and wire the software.                                                                                      |
| **Verify**             | Automated tests + security + review checklist.                                                                    |
| **Release**            | Merge request, docs, and readiness to deploy.                                                                     |
| **VAPT**               | Security review against a standard checklist (auth, permissions, data exposure, etc.).                            |
| **BFF**                | A thin layer between screens and backend services — you rarely need to care unless integration is discussed.      |
| **API / OpenAPI**      | A contract describing how systems exchange data — like a menu of allowed operations.                              |
| **Merge request (MR)** | The packaged change engineers merge on GitLab after checks pass. GitHub calls the same thing a pull request (PR). |
| **Critical finding**   | Must be fixed before release; not optional.                                                                       |


---



## What the AI will not do without you

- **Commit or push** code to Git without your OK — the shell hook **asks** in Cursor/Claude; approve only when you intended that action (e.g. Release).  
- **Self-approve delivery gates** in markdown — CI and CODEOWNERS expect a **human** reviewer on the merge request; say `Approved` in chat, then a person records it in the artifact and approves the merge request.  
- **Skip gates** on `/deliver` — you approve each phase. A green build does not approve itself.  
- **Start the next phase** while the current one is still waiting for your approval.  
- **Overwrite another feature’s files** in the same checkout — it stops and names the files instead.  
- **Store passwords or API keys** in chat — use your org’s secret vault; never paste production secrets.

---



## When to bring in engineering


| Situation                                        | Who                                                                                                                  |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| First time using the kit in a **new** repo       | Engineer scaffolds the app, then runs `scripts/bootstrap-greenfield.sh` (see `docs/greenfield-onboarding.md`).       |
| First time using the kit in an **existing** repo | Engineer runs `scripts/install.sh` and `scripts/audit-brownfield-baseline.sh` (see `docs/brownfield-onboarding.md`). |
| Critical security finding you don’t understand   | Security or lead engineer.                                                                                           |
| CI failing repeatedly on release                 | Release manager / DevOps.                                                                                            |
| Changing org-wide rules                          | Engineering + architecture (not this guide).                                                                         |


---



## One-page cheat sheet

```text
1. Open Cursor chat in the project.
2. Big goal: /plan first. Then /deliver + paste Jira/spec (or /intake only). Name the feature if more than one is open.
3. Answer questions when asked.
4. At each gate: read summary → Approved OR list changes.
5. If the chat stopped mid-phase: /status <feature> → run the same phase command again.
6. After go-live: /maintain + describe the issue.
```

For technical setup, model routing, and compliance mapping, see [README.md](../README.md). Engineers: [greenfield-onboarding.md](greenfield-onboarding.md), [brownfield-onboarding.md](brownfield-onboarding.md).