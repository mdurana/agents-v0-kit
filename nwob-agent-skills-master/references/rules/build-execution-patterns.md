# Build Execution Patterns

Condensed patterns embedded in Builder `trigger-ai-build`. Sources: `incremental-implementation`, `test-driven-development`, `context-engineering`, `source-driven-development`, `frontend-ui-engineering` in `references/agent-skills-main/skills/`.

**Constitution overrides reference defaults:** 100% meaningful coverage is mandatory. Testcontainers is Java-only. The reference ~80% unit pyramid does not apply.

---

## Context load order

Load context in this hierarchy (highest precedence first):

1. **Rules.** [AGENTS.md](../../AGENTS.md), [constitution-core.mdc](../../rules/constitution-core.mdc), `.cursor/rules/` (including `constitution-custom.mdc` when present)
2. **SDD** — `nwob-docs/sdd/epic-spec.md` (backlog index + story order), `{stories_dir}/{STORY_ID}/story-spec.md` (product + technical annex), and `story-tasks.md` (Gherkin and official task IDs win)
3. **Technical annex** — annex sections in `{stories_dir}/{STORY_ID}/story-spec.md` (files, mocks, subtask mapping)
4. **Execution overlay** — live Cursor plan in `~/.cursor/plans/` only; every YAML todo cites a `story-tasks.md` ID; not an SDD file
5. **Architecture** — `nwob-docs/architecture/architecture.md`, `network.md`, `service-map.md`, relevant `adr/`, OpenAPI at `repositories/{service-name}/src/main/resources/swagger/`
6. **Task-scoped source** — files listed in the **current** `story-tasks.md` item only
7. **Errors / tests** — failing output from verify command for the active increment

**Anti-flood:** Do not load the entire codebase when a task lists ≤5 files. **Anti-starvation:** Always load the story trace and Gherkin AC for the active task's linked epic-spec backlog row and `story-spec.md`. Do not let the Cursor overlay outrank `story-spec.md` or `story-tasks.md`.

---

## Increment cycle

For each `story-tasks.md` item:

```
Implement → Test → Verify → Lead Builder review-implementation → next task
```

1. **Implement** — smallest complete slice for the task; one task at a time
2. **Test** — TDD where behavior changes (see below); run targeted tests first
3. **Verify** — platform command after significant increments: `mvn clean verify` (Java), `xcodebuild test` (iOS), `./gradlew test` (Android)
4. **Lead Builder gate** — `review-implementation` sign-off before advancing
5. **Next task** — only after increment approved

Keep the system compilable after each slice. Do not batch multiple `story-tasks.md` items without per-task verification. If the user groups 2–3 `story-tasks.md` items in one Cursor todo, still produce a `review-implementation` verdict per ID. Use `epic-spec.md` backlog index for cross-story order when needed.

---

## Test-driven development (constitution-aligned)

When the task changes behavior:

1. **RED** — write a failing test proving required behavior (or reproduction test for bugs)
2. **GREEN** — minimal implementation to pass
3. **REFACTOR** — clean up while tests stay green

| nwob mandatory | Reference default (overridden) |
|----------------|-------------------------------|
| 100% meaningful coverage on the measured scope | ~80% unit-heavy pyramid |
| Java: Testcontainers for integration | Optional integration layer |
| iOS: XCTest / `xcodebuild`; Android: Gradle | npm-only or Java-only scripts on every clone |
| Every exception handler tested (APIs) | Best effort |

Run the platform verify command — `mvn clean verify` on Java, `xcodebuild test` on iOS, `./gradlew test` on Android. Do not run `mvn` on mobile clones.

---

## Source-driven implementation

Before writing framework-specific code:

1. **Resolve effective stack** from user prompt → SDD → ADRs → Default technology stack in constitution-core defaults
2. **Fetch official docs** for the resolved framework versions (page-level, not homepages)
3. **Implement** documented patterns; surface doc vs codebase conflicts to user
4. **Cite** in ADR or Javadoc when the choice is architectural. Avoid raw URL comments in production code

OpenAPI contracts from SA `architecture-delivery-enablement` at `repositories/{service-name}/src/main/resources/swagger/` take precedence over ad-hoc API shapes.

---

## Frontend branch (when UI in scope)

Resolve UI from `constitution-custom.mdc` and project stack rules. Do not assume React or Svelte.

| Effective stack | UI | Load |
|-----------------|----|------|
| Java/Spring API | N/A for native screens | `constitution-custom.mdc`, [implementation-quality-standards.md](implementation-quality-standards.md) |
| iOS | SwiftUI | `constitution-custom.mdc` (iOS harness notes) |
| Android | Jetpack Compose | `constitution-custom.mdc` (Android harness notes) |
| Web (only when custom says so) | React or Svelte | project frontend conventions |

When UI is in scope:

- Colocate screens, tests, and hooks or ViewModels per the omni glob
- Loading, error, and empty states required
- No secrets in client storage; Bearer + correlation ID on API calls

Confirm the UI framework from custom or user prompt.

---

## MR and QA handoff

After all `story-tasks.md` items for the active story complete:

1. Raise MR with traceability to stories
2. Run `audit-and-approve-code` — **stop** before external QA until approved
3. Document any user-waived Lead Builder gates in chat

---

## Anti-patterns

| Anti-pattern | Correct action |
|--------------|----------------|
| Load entire repo into context | Task-scoped files + linked story only |
| Skip tests until end of sprint | TDD + verify per increment |
| Apply reference 80% coverage target | Constitution 100% meaningful coverage; 70/20/10 is a mix hint |
| Infer stack from `package.json` alone | Resolve from SDD and ADRs first |
| Advance task without `review-implementation` | Lead Builder per-increment gate |
| Treat Cursor plan as `story-tasks.md` | Overlay in `~/.cursor/plans/`; cite `story-tasks.md` ID on every todo |
| Persist execution plan under `nwob-docs/` | Cursor cache only |
| Invoke reference skill files directly | Use this embed inside `trigger-ai-build` |
