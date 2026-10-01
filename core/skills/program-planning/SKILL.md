---
name: program-planning
description: Plan phase playbook. Turn a large goal into milestone manifests, ordered stories, and integration stories before any Intake.
---

# program-planning

Plan phase playbook for the `program-planner` agent (`workflow-orchestration.mdc` Program planning).

## Steps
1. Read the goal and the repo context (`docs/project-profile.md`, `docs/repo-map.md`). Name the bounded contexts in scope.
2. Run `system-design` first: `docs/design/system/context-map.md` (one row per context: purpose, service root, owner, sync or async integrations), the NFR/SLO budget, and threat-model notes.
3. Choose the milestones. Start from `templates/docs/milestones/` (P0 skeleton, P1 contracts and data models, P2 MVP, P3 features, P4 hardening, P5 release readiness). Drop a milestone only with a recorded reason.
4. Write each story row in `docs/milestones/<milestone>.md`:
   - Story ID (`P2-A`, `P2-B`, …).
   - User story: one full `As a [role], I want [goal], so that [benefit].` sentence. No `<...>` or `[...]` placeholders. If the role, goal, or benefit is unknown, ask the user.
   - Feature artifact: a concrete path, `docs/requirements/<feature>.md`.
   - Status: `planned`.
   - Dependency: story IDs only, comma-separated. Milestone-level dependencies (`P1`) are prose and are not checked.
5. Size every story: one surface (`backend`, `bff`, or `frontend`) and at most eight acceptance criteria. Split a larger story into rows here. Use `Vertical slice: yes` only when the user asked for one journey across surfaces.
6. Add an integration story for each pair of contexts that call each other. It depends on both sides, covers the contract and the failure modes, and is the place for consumer-driven contract tests.
7. Order the stories as a graph with no cycle. A story starts Build only after every story it names has its Verify approval (`ci/check-milestone.sh` enforces this).
8. Map each filled NFR/SLO row to a P4 hardening story.
9. Present the context map, the manifests, and the story graph (Mermaid `flowchart` of story IDs). Wait for explicit approval. Then append the `plan` row to each manifest's `Delivery approvals` table:

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | plan | docs/milestones/&lt;milestone&gt;.md, docs/design/system/context-map.md | &lt;name&gt; | Approved | &lt;date&gt; |

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc`: contexts, database per service, Mermaid conventions.
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; `Service roots` recorded for multi-service repos.
- [ ] Every story sentence is complete; every story fits the size budget.
- [ ] Every cross-context call has an integration story with both sides as dependencies.
- [ ] The dependency graph has no cycle.
- [ ] `workflow-orchestration.mdc`: Plan gate met; stopped for approval.
