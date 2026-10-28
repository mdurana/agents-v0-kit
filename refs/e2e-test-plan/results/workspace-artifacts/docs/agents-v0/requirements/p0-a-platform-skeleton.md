# Feature: P0-A — Platform Skeleton

Milestone: P0 — Platform Skeleton
Story: P0-A
Vertical slice: yes

As a developer, I want a known-good baseline — the build and tests pass, this milestone is the tracked manifest, coverage and CVE scanning are bound to verify, and I can run the app locally with Dockerfile and Compose — so that feature work starts from a stack that already runs.

## Acceptance Criteria

### AC-1 (Kind: happy)
```gherkin
Given the scaffolded Java backend and React frontend in app/
When the backend and frontend test and build commands execute
Then all unit and integration tests pass with zero errors
```

### AC-2 (Kind: happy)
```gherkin
Given the repository with .cursor/, .agents/, and .agents-v0/ installed
When docs/agents-v0/milestones/p0-platform-skeleton.md is inspected
Then P0-A is the tracked baseline story without reinstalling the kit
```

### AC-3 (Kind: happy)
```gherkin
Given app/backend/pom.xml and .agents-v0/packs/java/pack.json
When the verify profile is inspected
Then JUnit Surefire, JaCoCo coverage, Checkstyle, SpotBugs, and OWASP Dependency-Check are bound to verify
```

### AC-4 (Kind: edge)
```gherkin
Given Dockerfile and docker-compose.yml in the repository
When container configuration and health endpoints are verified
Then the service exposes a public health check and container runtime support
```

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| build | docs/agents-v0/build/p0-a-platform-skeleton/plan.md, docs/agents-v0/build/p0-a-platform-skeleton/build-report.md | mdurana | Approved | 2026-10-28 |
| verify | docs/agents-v0/verify/p0-a-platform-skeleton/quality-gate.md, docs/agents-v0/verify/p0-a-platform-skeleton/vapt-checklist.md, docs/agents-v0/verify/p0-a-platform-skeleton/code-review.md | mdurana | Approved | 2026-10-28 |
| release | docs/agents-v0/requirements/p0-a-platform-skeleton.md, docs/agents-v0/verify/p0-a-platform-skeleton/quality-gate.md | mdurana | Approved | 2026-10-28 |
