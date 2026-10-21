# Agentic Workflow Guide

You can drive delivery in Cursor **without writing code**. You provide the business intent, answer questions, and approve the gates that apply. A story with an API, messages between systems, screens, or a public route stops at each phase. The platform skeleton skips Intake and Design and stops once, at Release. Optional local release may record the earlier rows first. A story with none of those does not stop at Design, unless it adds a service, a datastore, a security boundary, or a breaking API. Engineers and the AI handle implementation, testing, and security checks.

This guide matches the workflow in this kit. A new program starts with **Roadmap**, then **Architecture**, then **Plan**. Each story then runs **Intake → Design → Build → Verify → Release** (and **Maintain** when something breaks or needs an update). Optional `/v0-local-release` may sit after Verify so the next story can start. `/v0-release` does not require it. Use the phase commands in Cursor; gates, approvals, and evidence work the same way documented here. `bootstrap-greenfield.sh --pack java --scaffold-app` extracts the Java example archive under `app/`. Omitting `--pack` extracts that same archive. Any other pack builds its shell from its own scaffold during P0-A. An empty Pack does not select Java.

---

## What you need


| Item           | Notes                                                                                                |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| **Cursor**     | Desktop app with the project open (your team’s service repo, after the kit is installed).            |
| **Chat**       | Open the AI chat panel in that project.                                                              |
| **Your input** | A Jira ticket, Confluence page, email spec, or a short description in plain language.                |
| **Approvals**  | You say when a gate is good enough to continue (see [Gates](#the-five-gates-where-you-approve)). The platform skeleton has one approval, at Release. A story with no API, no messages between systems, no screens, and no public route does not stop at Design, unless it adds a service, a datastore, a security boundary, or a breaking API. |


You do **not** need to run terminal commands, edit code, or pick AI models. Optional: ask your team to set the model picker to **Agent → Composer 2.5** for day-to-day chat.

Phase commands use a **`/v0-` prefix** (for example `/v0-plan`, `/v0-build`) so they do not clash with Cursor’s built-in slash commands such as `/plan`.

---



## Quick start (three steps)

1. **Open chat** in the project that uses this workflow kit.
2. **Start work** with one of these (type in chat):
  - `/v0-deliver` — full journey from requirements through release. A story with an API, messages between systems, screens, or a public route stops at every gate. The platform skeleton skips Intake and Design and stops once, at Release. Optional local release may record the earlier rows first. A story with none of those does not stop at Design, unless it adds a service, a datastore, a security boundary, or a breaking API.
  - `/v0-intake` — turn one ticket or one approved story into requirements.
3. **Paste your spec** right after the command, for example:
  ```text
   /v0-intake

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
| `/v0-roadmap`  | A new program. Point it at the discovery document your team already wrote, anywhere in the repo. The AI sequences now / next / later and stops. It does not reopen the problem. |
| `/v0-architecture` | After that roadmap is approved and before any story. The AI writes the system shape and the architecture decision and stops. |
| `/v0-plan`     | After that architecture decision is approved: milestones, ordered stories, and `docs/agents-v0/milestones/plan.md` (the milestone table and story flowchart) before any `/v0-intake`. |
| `/v0-intake`   | Turn one idea or ticket into clear requirements. Each acceptance criterion is a Given / When / Then. One is a failure case, unless the story has no security trigger and no failure behavior. The platform skeleton does not run this. |
| `/v0-export`   | Optional. Regenerates a Jira spreadsheet from the approved stories. It does not change the plan. |
| `/v0-deck`     | Optional. Writes a briefing from one approved story (`intake`), or from the approved roadmap and plan (`product` or `delivery`). You say who the audience is and what the meeting must decide. |
| `/v0-design`   | After intake is approved, when the story has an API, messages between systems, screens, or a public route. The platform skeleton skips this. A story with none of those locks the design and continues, unless it adds a service, a datastore, a security boundary, or a breaking API — that one still stops for an architecture decision. |
| `/v0-build`    | After design is approved, or after a no-contract design is locked. The platform skeleton starts here: it copies the milestone story and writes the design. |
| `/v0-verify`   | After build is approved — automated tests and security review. The platform skeleton does not stop here. |
| `/v0-local-release` | Optional, after verify. Records a local checkpoint so the next story can start. Skip it and run `/v0-release`. |
| `/v0-release`  | After verify is approved — merge request readiness (GitLab), then completion after an authorized merge. The platform skeleton's one approval is here, after the test report and the merge-request link. |
| `/v0-deliver`  | Run the whole chain. You approve at each gate that applies.                                             |
| `/v0-maintain` | Bug, security patch, dependency update, or doc fix after go-live.                                       |
| `/v0-triage`   | Small, low-risk change (typo, docs-only, version-only update). The change itself must qualify, and you confirm it before the lighter path starts. |
| `/v0-onboard`  | First-time setup on an **existing** repo: documents what is there (modules, architecture, flows, security baseline) with sources cited, and records what it could not determine. You approve the report before intake. |
| `/v0-status`   | Name the feature. An unfinished phase is run again from the saved files; a phase waiting on you does not start the next one. |


You can also write in normal language, for example: *“Run intake on PROJ-1234”* or *“We’re only doing design for the notifications feature.”* Using the slash commands is clearer for the workflow. When more than one feature is open, name it: `/v0-status tax-statement`.

---

## If work was interrupted

`/v0-status` plus the feature name reads the saved progress for that feature. It does not mark the phase approved, and it does not restart the chat that was cut off.

| What you see | What you do |
|--------------|-------------|
| The phase was still being written, or it stopped on a problem | Run the same command again (`/v0-design`, `/v0-build`, and so on). The AI keeps the files already saved. A second design run reviews that saved design. A second verify run reuses the test report when the code has not changed, and repeats the checks when it has. |
| The phase is waiting for you | Reply `Approved` or list what to change. A green build is not approval. The next phase does not start until you approve a phase that has its own stop. |
| You did not name a feature | The AI lists the open features and asks which one you mean. |

---

## More than one feature

You can approve intake for a second feature while the first feature’s build is still waiting on you, then start design for the second feature. Each feature has its own requirements and design notes.

The second feature must not change a file the first one is already changing. Those shared files include the project profile, the shared API catalog, architecture notes, the plan picture (`docs/agents-v0/milestones/plan.md`), the README, and the application code. Intake and design for the second feature stay in its own requirements and design documents, including that feature’s own API draft. The shared API catalog is updated when that feature is built. Build, verify, release, and a fix after go-live stop if those shared files, or the other feature’s code, are already modified. Ask engineering for a separate branch before that work continues in the same checkout. Creating that branch still needs you to ask for it. The usual way is one working folder per feature: engineering runs `.agents-v0/scripts/feature-worktree.sh <feature>` once you have said yes, and each feature then builds in its own folder without touching the others.

## Big goals: roadmap, then plan

When the goal is a new program, start with `/v0-roadmap` and the path of the discovery document your team already agreed. That file may sit anywhere in the repo. It needs these headings, each filled in: Problem, Success metric, Options, Chosen option, In scope, Out of scope. The AI turns In scope into now / next / later and stops. It does not reopen the problem. You approve the sequence. Then `/v0-architecture` writes the system shape (who talks to whom, how data moves and is stored, what happens when a part fails, the options, the network, and who runs it) and an independent reviewer checks it before it stops. You approve that once, before any story exists. The discovery file may name `Stack preference:`. The roadmap copies that line and does not install it. The architecture approval writes the pack the team named, including a stack that is not one of the kit examples, and installs it after that approval. An empty Pack stops until that pack is complete and installed. Then `/v0-plan` writes the milestone files and `docs/agents-v0/milestones/plan.md` (a table of milestones and stories, and a flowchart of the story order) and stops. You approve that picture once. Each story then runs through the gates that apply, in the order the plan sets: a story cannot start building until the stories it depends on have passed Verify. Who skips the roadmap, the architecture command, and the plan is the skip list in `workflow-orchestration.mdc` (a single ticket, the platform skeleton, and a fix after go-live).

With many small stories you can approve the Intake or Design gate for several of them in one message, but only by naming each one, for example `Approved: Design for P2-A, P2-B, P2-C`. That is available only for ordinary stories with no security triggers and no open questions. Build, Verify, and Release are always approved one story at a time. "Approve all" does not count.

The AI also stops by itself when one phase has failed too many times in total (default 8 failed attempts). It reports what blocked it; engineering decides whether to raise the limit.

---



## The five gates (where you approve)

The AI **must not** skip a gate that applies. Roadmap, Architecture, and Plan are the stops for a new program, before these five. A story with an API, messages between systems, screens, or a public route stops at each gate below. The platform skeleton skips Intake and Design and stops once, at Release. Optional local release may record the earlier rows first. A story with none of those does not stop at Design: the design is locked, and you approve it together with the build. A story that adds a service, a datastore, a security boundary, or a breaking API still stops at Design. Each stop ends with a short report: what was done, what’s ready, and what still needs your decision.

### 1. Intake gate

**Your question:** *Did we capture the right problem, success criteria, and rules?*


| You should see               | What it means                                                                                 |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| Acceptance criteria          | One Given / When / Then per criterion. The result names what you would see (a status, a saved record, a message, or a screen). |
| A failure case               | At least one criterion says what happens when the input or the dependency is wrong. If the story has no security trigger and no failure behavior, the artifact records `Negatives: N/A` and a reason instead. |
| How to try it                | The state required beforehand, and one way a person can check the main path before QA.        |
| NFRs                         | Speed, availability, audit needs (in plain language).                                         |
| Regulations / policies       | e.g. privacy, banking, or internal GXI items that apply.                                      |
| UX requirements (UI changes) | Accessibility target (WCAG 2.1 AA), devices/browsers, design system, and UX success criteria. |
| Open questions               | The list says none.                                                                           |


**You might say:**  

- `Approved — proceed to design.`  
- `Add acceptance criterion: user must confirm identity before download.`  
- `Regulation XYZ applies; include it.`

---



### 2. Design gate

**Your question:** *Is the solution shape right before we build?*

This stop applies when the story adds an API, messages between systems, screens, or a public route, and when it adds a service, a datastore, a security boundary, or a breaking API. That last case uses the architecture decision you already approved. You are asked to accept a new recommendation only when this story changes it. A health, readiness, or liveness check does not by itself make it a public route. Otherwise the AI locks the design and continues to Build, and you approve that design together with the build. The platform skeleton does not run this phase.


| You should see            | What it means                                                                                                 |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- |
| API / contract summary    | What systems talk to each other (not code — interfaces). The draft belongs to this feature. It is merged into the shared API catalog when the feature is built. |
| Diagrams                  | Flowcharts or sequence diagrams (who calls whom).                                                             |
| Design notes and review   | A short design document (every requirement mapped to what satisfies it; who may do what; what happens when a dependency fails). An independent reviewer writes findings when there is an API, messages between systems, screens, or a public route. You approve once that reviewer has no open Critical item, and the design is locked then. A story with none of those is locked without a reviewer. If building shows a locked design is wrong, the AI stops, reviews the changed design, and asks you to approve an amendment before it locks the new version. |
| ADR (if needed)           | Short decision record for big choices (e.g. sync vs async). Once you accept it, a later change adds a new record and leaves the old one in place. A story with no product decision records that none was needed. |
| UI stack (if new screens) | The pack's `ui` id. The React example is **React 19, TypeScript 5.9, Vite 7**. |
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
| Security (VAPT) review   | Always-on checks (function and object access, JWT, audit events) plus regression checks (logout, uploads, cookies, exposure). |
| Code review notes        | **Critical** = must fix before release; **Suggestion** = nice to fix.    |
| UX / accessibility check | Automated accessibility scan green; UX criteria tested (for UI changes). |


Tests finish first. The security checklist and the code review are prepared together, and you see one list of **Critical** items. If that list has anything on it, the AI should fix and re-run verify — you approve again when Critical items are gone. If the code changed after you had already approved verify, that approval is reopened until you approve the new run. A re-run on the same code reuses the test report.

**You might say:**  

- `Approved for release.`  
- `Critical on upload validation — fix before we approve.`

---



### 5. Release gate

**Your question:** *Are we ready to ship and document?*


| You should see | What it means                                                                                              |
| -------------- | ---------------------------------------------------------------------------------------------------------- |
| Docs updated   | README and sequence diagrams for what changed. Architecture and network notes are a later docs-only change. |
| Merge request  | Ready for engineering merge (CI green). |
| VAPT sign-off  | Security checklist in the merge request description.                                                       |


"Ready" is not "released": the AI reports readiness and waits for an authorized human merge. Release is complete only after the merge and green CI are confirmed. Approving a phase does not by itself authorize committing, pushing, or opening a merge request; explicitly request those actions when needed.

**You might say:**  

- `Please open the merge request; engineering will merge after CI is green.`  
- `Wait for product sign-off on release notes.`

---



## Maintain (after go-live)

Use `/v0-maintain` when:

- Users report a bug  
- Security or compliance asks for a patch  
- Dependencies need upgrading  
- Documentation is out of date

Describe the issue in plain language. The AI fixes, then runs **Verify** again. You approve if the fix and checks look good.

---



## How to write a good request

**Include:**

- **Who, what, and why** in one sentence: As a [role], I want [goal], so that [benefit].  
- **Constraints** (privacy, regions, deadlines, systems involved). Intake turns the sentence and each constraint into numbered acceptance criteria (`AC-1`, `AC-2`, …), one Given / When / Then scenario each, including one failure case unless the story has no security trigger and no failure behavior.  
- **Links** (Jira, Confluence, Figma) — paste text if you can’t link  
- **Out of scope** (what we are *not* doing), as its own list

**Example (good):**

```text
/v0-intake

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
| **VAPT**               | Security review. Always-on checks cover function access, object access, JWT validation, and audit events. Regression checks cover logout, uploads, cookies, and exposure. |
| **BFF**                | A thin layer between screens and backend services — you rarely need to care unless integration is discussed.      |
| **API / OpenAPI**      | A contract describing how systems exchange data — like a menu of allowed operations.                              |
| **Merge request (MR)** | The packaged change engineers merge on GitLab after checks pass. |
| **Critical finding**   | Must be fixed before release; not optional.                                                                       |


---



## What the AI will not do without you

- **Commit or push** code to Git without your OK — the shell hook **asks** in Cursor; approve only when you intended that action (e.g. Release).  
- **Self-approve delivery gates** in markdown — CI and CODEOWNERS expect a **human** reviewer on the merge request; say `Approved` in chat, then a person records it in the artifact and approves the merge request.  
- **Skip a gate that applies** on `/v0-deliver` — you approve each phase that has its own stop. The platform skeleton's one stop is Release. A story with no API, no messages between systems, no screens, and no public route has no Design stop. A green build does not approve itself.  
- **Start the next phase** while the current one is still waiting for your approval.  
- **Overwrite another feature’s files** in the same checkout — it stops and names the files instead.  
- **Store passwords or API keys** in chat — use your org’s secret vault; never paste production secrets.

---



## When to bring in engineering


| Situation                                        | Who                                                                                                                  |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| First time using the kit in a **new** repo       | Engineer creates an empty repo, then either copies the kit with `scripts/bootstrap-greenfield.sh` or pins it with `scripts/install.sh --link` (see `docs/agents-v0/greenfield-onboarding.md`). `--pack java --scaffold-app` extracts the Java example archive into `app/`. Any other pack does not extract that archive. |
| First time using the kit in an **existing** repo | Engineer runs `scripts/install.sh` or `scripts/install.sh --link`, then `sh .agents-v0/scripts/audit-brownfield-baseline.sh` (see `docs/agents-v0/brownfield-onboarding.md`). Do not use `--scaffold-app`. |
| Design / OpenAPI / UX fill-ins                   | Engineer uses `docs/agents-v0/snippets/` (CRUD OpenAPI, sync-vs-async ADR, one-screen UX) instead of inventing structure. |
| Red–green loops burning time                     | Engineer ensures profile **fast** verify cells are real commands (`npm test`, `./mvnw … -P!ci-security`); second failure uses `failure-brief.md`. |
| Critical security finding you don’t understand   | Security or lead engineer.                                                                                           |
| CI failing repeatedly on release                 | Release manager / DevOps.                                                                                            |
| Changing org-wide rules                          | Engineering + architecture (not this guide).                                                                         |


---



## One-page cheat sheet

```text
1. Open Cursor chat in the project.
2. New program: /v0-roadmap <path to the discovery file>, then /v0-architecture, then /v0-plan. One ticket: /v0-deliver or /v0-intake. Name the feature if more than one is open.
3. Answer questions when asked.
4. At each gate that applies: read summary → Approved OR list changes. The platform skeleton asks once, at Release.
5. If the chat stopped mid-phase: /v0-status <feature> → run the same phase command again.
6. After go-live: /v0-maintain + describe the issue.
```

For technical setup and model routing, see [README.md](../../README.md) at the repo root. The full map of commands, records, and checks is [agents-v0-kit.md](agents-v0-kit.md). Engineers: [greenfield-onboarding.md](greenfield-onboarding.md) (`--pack java --scaffold-app` for the Java archive), [brownfield-onboarding.md](brownfield-onboarding.md), [snippets/README.md](snippets/README.md).