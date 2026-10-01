---
description: Chain the full delivery lifecycle with a stop for user approval at every gate.
---

# /deliver

Chain the full delivery lifecycle: **Intake → Design → Build → Verify → Release**, with **Maintain** feeding back into Verify. A goal larger than one story starts with `/plan`; `/deliver` then runs one story of the approved manifest, in dependency order. Prefer launching the `orchestrator` subagent to run phases sequentially (helpers run from the main session, not from nested subagents). For **Trivial** tier use `/triage` instead of full Intake. For **Major** tier include `system-design` in Design and `ux-designer` when UI-affecting.

## Rules
Follow `workflow-orchestration.mdc`, including Phase resume and Parallel features. Stop at **every gate** and wait for user approval before advancing. Do not auto-advance. An `in_progress` or `blocked` state resumes that same phase; it does not approve it. A second feature in this checkout must not write a shared file another feature already has dirty.

Before each transition, verify the previous handoff artifact exists, its evidence is named and the recorded evidence paths exist on disk, and its `Delivery approvals` section records the explicit phase approval. If that evidence is absent, stop and report the missing prerequisite; never infer approval from a prior chat message or a passing command.

## Tier routing
- **Trivial** — stop after confirming scope; run `/triage` → abbreviated Maintain/Verify only.
- **Major** — full pipeline; Design includes `system-design` and threat-model notes; use milestone manifest when applicable.
- **Standard** — pipeline below.

## Pipeline
1. **Intake** — launch `requirements-analyst` (skill: `spec-intake`). Run any helper brief from this session (`workflow-orchestration.mdc` Helper agents).
   - Gate: criteria, NFRs, regulations recorded; open questions resolved; one surface unless `Vertical slice: yes`; at most `AC-8`.
   - **STOP → user approves → continue.**
2. **Design** — launch `solution-architect` (skills: `contract-first-design`, `system-design` when Major) and `ux-designer` when UI-affecting. Run helper briefs (`schema-author`, `docs-author`) from this session.
   - Gate: feature draft `docs/design/<feature>/openapi.yaml` + event schemas (`eventVersion`); the org catalog is unchanged; one error envelope per surface; ADR; Mermaid diagrams. When UI-affecting: UX spec plus static HTML mockups, with a component-default row for every interactive control (`ux-design.mdc`).
   - **STOP → user approves → continue.**
3. **Build** — launch `backend-engineer` / `bff-engineer` / `frontend-engineer` (skills: `implement-spring-service`, `implement-bff`, `implement-frontend`).
   - Follow `/build` (prerequisite, baseline, plan, loop, evidence) and the Build gate in `workflow-orchestration.mdc`. Do not restate them here.
   - **STOP → user approves → continue.**
4. **Verify** — launch `test-engineer` (skill: `quality-gate`) first. Then launch `security-reviewer` (skill: `vapt-review`) and `code-reviewer` (skill: `pr-review`) together. Wait for both. Gather one Critical list. Run a `schema-author` brief from this session. The P4 SLO story follows `slo-evidence`.
   - Follow `/verify` and the Verify gate in `workflow-orchestration.mdc`.
   - On a gathered Critical: route back to Build/Maintain, then re-enter Verify.
   - **STOP → user approves → continue.**
5. **Release** — launch `release-manager` (skill: `release-pr`).
   - Open the merge request only when the user explicitly requests it. **GitLab (default):** `glab mr create` with `.gitlab/merge_request_templates/default.md`. **GitHub:** `gh pr create` with `.github/pull_request_template.md`. Commit and push require their own explicit authorization.
   - Readiness: docs synced; template complete (include `Feature-Artifact:`); CI green. On GitLab, after the MR is approved, run the manual `delivery-approval` job. **STOP → report readiness; wait for an authorized human merge.**
   - Completion: confirm the merge request is merged and CI on the default branch remains green. **STOP → report outcome.**

## Maintain (on demand)
At any point after Release, `/maintain` launches `maintenance-engineer` (skills: `bugfix-triage`, `dependency-upgrade`, `doc-sync`) and routes back to Verify.

## Conduct
Per `ai-agent-conduct.mdc`: Reconnaissance → Plan → Execute → Verify → Report at each phase. No commits/force-push without explicit user approval.
