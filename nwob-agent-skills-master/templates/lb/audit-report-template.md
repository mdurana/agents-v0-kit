# MR audit report

Lead Builder artifact for `audit-and-approve-code`. Constitution: `.cursor/rules/constitution-core.mdc`. Finding schema: [builder-quality-patterns.md](../../references/rules/builder-quality-patterns.md).

## Merge request

- **Source branch:**
- **Base branch:**
- **Git range:** `<base>...<source>`
- **Stories covered:**
- **Reviewer:**
- **Mode:** Standard NWOB build, or brownfield or peer MR

## SDD traceability

| Artifact | Status | Notes |
|----------|--------|-------|
| nwob-docs/sdd/epic-spec.md (backlog index) | | |
| `{stories_dir}/{STORY_ID}/story-spec.md` (product + annex) | | |
| `{stories_dir}/{STORY_ID}/story-tasks.md` | | |

## Quality gates

- [ ] 100% meaningful coverage on the measured scope (coverage gates in `.cursor/rules/constitution-core.mdc`)
- [ ] Testcontainers for Java integration tests (N/A on iOS and Android)
- [ ] Checkstyle, PMD, SpotBugs (Java. N/A on iOS and Android)
- [ ] SonarQube Quality Gate per [implementation-quality-standards.md](../../references/rules/implementation-quality-standards.md) (Java. N/A on iOS and Android)
- [ ] RFC 7807 error format on APIs (N/A for client-only clones)
- [ ] Stateless K8s compliance (N/A for client-only clones)
- [ ] MR Flow mermaid matches clone platform (N/A for rename, constant, or doc-only diffs)

## Standards checklist

Mark each cluster Pass, Fail, or N/A. Apply `.cursor/rules/constitution-custom.mdc` when that file is present.

| Cluster | Result | Notes |
|---------|--------|-------|
| Git and packages | | |
| Naming | | |
| Architecture and SOLID | | |
| Clean code | | |
| Defensive design and logging | | |
| Tests | | |

## Findings

Each finding includes:

- File, Line, when the issue is in the diff
- What is the problem
- How to verify
- Why it is a problem, and Impact
- Suggested fix. If several options exist, mark Recommended first
- Severity: Critical, Major, or Minor

### Critical (must fix before merge)

#### Finding 1

- **File, Line:**
- **What is the problem:**
- **How to verify:**
- **Why it is a problem / Impact:**
- **Suggested fix:**

### Major

#### Finding 1

- **File, Line:**
- **What is the problem:**
- **How to verify:**
- **Why it is a problem / Impact:**
- **Suggested fix:**

### Minor

#### Finding 1

- **File, Line:**
- **What is the problem:**
- **How to verify:**
- **Why it is a problem / Impact:**
- **Suggested fix:**

## Tech assessment

- **Risks:**
- **Scalability:**
- **Backward Compatibility:**
- **Test Coverage:**

## Verdict

- [ ] Approved. Ready for QA handoff (`APPROVE`)
- [ ] Changes requested. Author uses Builder `resolve-review-comments` or `trigger-ai-build` (`REQUEST CHANGES`)
