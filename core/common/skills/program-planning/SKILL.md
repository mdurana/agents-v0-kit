---
name: program-planning
description: Plan phase playbook. Turn a large goal into milestone manifests, ordered stories, and integration stories before any Intake.
---

# program-planning

Plan phase playbook for the `program-planner` agent (`workflow-orchestration.mdc` Program planning).

## Steps
1. Read the approved roadmap (`Discovery:` is the only product source), the approved architecture pack, and the repo context (`docs/agents-v0/project-profile.md`, `docs/agents-v0/repo-map.md`). A plan whose only story is seeded P0-A may skip the roadmap and the architecture pack. Any other plan stops until the `roadmap` row and the `architecture` row are `Approved` and the profile `Pack` cell names a complete pack manifest. Do not rewrite the context map, network, SLO budget, threat model, or ARC record. Stories follow that pack's service skill.
2. Read `docs/agents-v0/design/system/context-map.md` from `/v0-architecture`. Name the bounded contexts already in that map. A story that needs a context the map does not list stops for an architecture amendment, not a silent edit.
3. Choose the milestones. Start from `templates/docs/agents-v0/milestones/` (P0 skeleton, P1 contracts and data models, P2 MVP, P3 features, P4 hardening, P5 release readiness). Drop a milestone only with a recorded reason.
4. Write each story row in `docs/agents-v0/milestones/<milestone>.md`:
   - Story ID (`P2-A`, `P2-B`, …).
   - User story: one full `As a [role], I want [goal], so that [benefit].` sentence. No `<...>` or `[...]` placeholders. If the role, goal, or benefit is unknown, ask the user.
   - Feature artifact: a concrete path, `docs/agents-v0/requirements/<feature>.md`.
   - Status: `planned`.
   - Dependency: story IDs only, comma-separated. Milestone-level dependencies (`P1`) are prose and are not checked.
   - Surface: `backend`, `bff`, `frontend`, or `vertical slice`.
   - Size: the number of acceptance criteria, at most 8, including the negative or edge Intake will add. Seeded P0-A stays at 4.
   - The user-story sentence states an outcome the approved roadmap already names. Do not add a theme.
5. Record `Roadmap:` and `Architecture: docs/agents-v0/architecture.md` on each manifest in scope. Omit both lines only when the plan's only story is seeded P0-A. Size every story: one surface and at most eight acceptance criteria, including that negative or edge. Split a larger story into rows here. Use `Vertical slice: yes` only when the user asked for one journey across surfaces. Do not split the seeded P0-A platform skeleton row. It is already one story. Surface `vertical slice` and Size `4`.
6. Add an integration story for each pair of contexts that call each other. It depends on both sides, covers the contract and the failure modes, and is the place for consumer-driven contract tests.
7. Order the stories as a graph with no cycle. A story starts Build only after every story it names has its Verify approval (`.agents-v0/ci/check-milestone.sh` enforces this).
8. Map each filled NFR/SLO row to a P4 hardening story.
9. Write `docs/agents-v0/milestones/plan.md` from the manifests. Two parts only:
   - A table with columns `Milestone`, `Stories`, and `What they cover`. One row per milestone in the plan, from P0 when it is in scope. `Stories` lists the story ids in dependency order. `What they cover` is one line, not the user-story sentence.
   - A `flowchart TD` of every story. The node id is the story id with the hyphen removed (`P2-F` → `P2F`). The label is the story id (`P2F[P2-F]`). One arrow per dependency, including edges that cross milestones. A story with no dependency is a node with no incoming arrow.
10. Present `docs/agents-v0/milestones/plan.md`. Wait for explicit approval. Then append the `plan` row to each manifest's `Delivery approvals` table:

   | Phase | Artifacts | Approver | Decision | Date |
   |-------|-----------|----------|----------|------|
   | plan | docs/agents-v0/milestones/plan.md, docs/agents-v0/milestones/&lt;milestone&gt;.md, docs/agents-v0/design/system/context-map.md, the roadmap path | &lt;name&gt; | Approved | &lt;date&gt; |

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc`: contexts, database per service, Mermaid conventions.
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; `Service roots` recorded for multi-service repos.
- [ ] Every story sentence is complete; every story fits the size budget.
- [ ] Every cross-context call has an integration story with both sides as dependencies.
- [ ] The dependency graph has no cycle.
- [ ] `docs/agents-v0/milestones/plan.md` is the milestone table and the story flowchart.
- [ ] `workflow-orchestration.mdc`: Plan gate met; stopped for approval.
