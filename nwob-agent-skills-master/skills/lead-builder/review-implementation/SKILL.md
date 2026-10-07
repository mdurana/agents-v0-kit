---
name: review-implementation
description: >-
  Validates one AI-generated increment against story-tasks.md, Gherkin AC, and
  the design package during the build phase. Use when trigger-ai-build is in
  progress and a task or increment is complete and needs Lead Builder review.
---

# Review one implementation increment

Validate one `story-tasks.md` item during Builder `trigger-ai-build`. Confirm the task meets `story-tasks.md`, Gherkin AC, and the design package before the next task starts.

Boundaries: [lead-builder-skill-boundaries.md](../../../references/rules/lead-builder-skill-boundaries.md). Quality patterns: [builder-quality-patterns.md](../../../references/rules/builder-quality-patterns.md), increment review section. Authoritative detail: [implementation-quality-standards.md](../../../references/rules/implementation-quality-standards.md) (including Java SonarQube / quality gates when Java applies).

This skill is not `audit-and-approve-code`. It does not run holistic MR review, the full Git, SOLID, and clean-code checklist, cross-increment integration testing, or the full story-coverage matrix. Those belong to `/audit`.

Load the story annex and `story-tasks.md` for file lists and AC context. Use `story-tasks.md` only when confirming cross-story order.

## When to use

- `trigger-ai-build` is in progress.
- Builder marked a task or increment complete and needs Lead Builder review before the next task.
- The user requests increment validation during the build phase.
- `validate-design-package` approved the design package before build began.

## Workflow

### Step 1: Confirm upstream gates

Confirm the SDD build gate passed: `epic-spec.md` and in-scope `story-spec.md` + `story-tasks.md` are finalized.

Confirm the design package was approved via `validate-design-package`.

If those gates were skipped, stop. Route to the matching skill.

### Step 2: Resolve effective constraints

Per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints), check the user prompt, then SDD artifacts, then other sources.

Apply effective stack and effective data lifecycle during review. Flag undocumented drift to the user.

### Step 3: Match the increment to one task

Match the completed work to one `story-tasks.md` item (by ID).

Load `{stories_dir}/{STORY_ID}/story-spec.md` (product + technical annex) and `{stories_dir}/{STORY_ID}/story-tasks.md` when the task traces to a story.

Verify the implementation satisfies traceable Gherkin AC in `story-spec.md`. Product AC wins if annex text differs.

Confirm scope matches the task. No undocumented scope creep.

Apply increment review axes only: correctness vs this `story-tasks.md` ID, slice security, 100% meaningful coverage, Java Testcontainers / mobile N/A, RFC 7807 on APIs. Do not apply the full MR standards checklist. That is `/audit`.

### Step 4: Apply increment review patterns

Apply the increment review section in [builder-quality-patterns.md](../../../references/rules/builder-quality-patterns.md):

1. Review axes: correctness, security, performance at slice scope, design fidelity.
2. If gates fail, stop. Reproduce, localize, fix the root cause, add a regression test.
3. If the increment includes user-facing UI and DevTools MCP is available, run the optional UI smoke.

Do not load `references/agent-skills-main/skills/code-review-and-quality` or `debugging-and-error-recovery` when the embed applies.

### Step 5: Verify quality gates

Confirm the increment passes:

1. 100% meaningful coverage on the measured scope. Testcontainers for Java integration tests; N/A on iOS/Android.
2. RFC 7807 error format on APIs; N/A for client-only clones.
3. Checkstyle, PMD, SpotBugs on Java; N/A on iOS/Android.
4. Stateless K8s on backend. No pod-local state. N/A for client-only clones.
5. Evidence from the platform verify command (`mvn clean verify`, `xcodebuild test`, or `./gradlew test`).

### Step 6: Check design fidelity

No undocumented architecture, stack, or data-lifecycle drift from the approved design package.

API implementations match OpenAPI contracts at `repositories/{service-name}/src/main/resources/swagger/` where those files are in scope.

If architectural drift appears, route to `orchestrate-design` or the matching SA skill. Do not accept silent drift.

### Step 7: Record the outcome

If the increment is approved, Builder `trigger-ai-build` may advance to the next `story-tasks.md` item.

If rework is needed, route back to `trigger-ai-build` with documented findings.

If this is the final increment, confirm the MR is ready for `audit-and-approve-code`. That is a lightweight readiness check. Do not duplicate holistic MR audit.

## Constitution compliance

Mandatory: increment review against `story-tasks.md` and Gherkin AC. 100% meaningful coverage must pass. Java: Testcontainers, RFC 7807, stateless K8s, Checkstyle, PMD, SpotBugs. iOS: XCTest/`xcodebuild`. Android: Gradle. Mark JVM-only gates N/A on mobile.

Default-overridable: technology stack (Default technology stack in constitution-core) and data lifecycle (Default data lifecycle in constitution-core) per [AGENTS.md](../../../AGENTS.md#default-vs-override-constraints). Reject increments that introduce undocumented stack or lifecycle choices.

## Rationalizations

| Excuse | Rebuttal |
|--------|----------|
| Quality gates passed in CI. Skip this review | Automated gates do not verify AC fidelity or design alignment. |
| We will audit everything at MR time | Increment review catches drift early. Final audit is not a substitute. |
| This task is too small to review | No exception for scope size. |
| AI followed `story-tasks.md`. Good enough | Verify against Gherkin AC and the design package, not the task title alone. |
| Use reference `code-review-and-quality` instead | Apply the increment section in builder-quality-patterns. |
| Invoke reference `test-driven-development` directly | TDD is embedded in Builder `trigger-ai-build`. This skill validates outcomes per increment. |
| Run the full SOLID, Git, and method-length checklist on this todo | Increment review stays slice-scoped. Holistic standards belong to `/audit`. |

## Red flags

- Increment approved without a matching `story-tasks.md` item or Gherkin AC.
- Quality gate failures waived.
- Undocumented architecture or stack drift accepted.
- Session 4 MR draft started without all increments passing this skill.

## Verification

- [ ] Increment mapped to a `story-tasks.md` item and traceable story AC?
- [ ] Story annex and `story-tasks.md` loaded for file and AC context when present?
- [ ] Increment axes only, full MR checklist deferred to `/audit`?
- [ ] Automated quality gates passed with evidence?
- [ ] No undocumented design, stack, or data-lifecycle drift?
- [ ] Increment approved, or rework documented?
- [ ] On the final increment: MR readiness confirmed for `audit-and-approve-code`?
