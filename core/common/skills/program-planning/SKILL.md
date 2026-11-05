---
name: program-planning
description: Plan phase playbook. Turn a large goal into milestone manifests, ordered stories, and integration stories before any Intake.
---

# program-planning

Plan phase playbook for the `program-planner` agent (`workflow-orchestration.mdc` Phase Gates Summary).

## Steps
1. Read the approved roadmap (`Discovery:` is the only product source), the approved architecture pack, and the repo context (`docs/agents-v0/project-profile.md`, `docs/agents-v0/repo-map.md`). On a brownfield repo, stop until `docs/agents-v0/onboarding/state.json` shows `lastApprovedPhase: "onboard"`. When `repo-map.md` is still a generator stub on a greenfield repo, the approved architecture pack (`architecture.md`, `context-map.md`, `components/*.md`) is the source — do not write an `explore-researcher` brief. A plan whose only story is seeded P0-A may skip the roadmap and the architecture pack. Any other plan stops until the `roadmap` row and the `architecture` row are `Approved` and the profile `Pack` cell names a complete pack (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id). Maintain, Trivial, and a milestone that already has an `Approved` `plan` row do not run this skill. Do not rewrite the context map, network, SLO budget, threat model, or ARC record. Do not edit `BFF root` or `Service roots` in `docs/agents-v0/project-profile.md` for directories that do not exist on disk yet (`resolve-layout.sh` emits them immediately; keep them `n/a` until the story that scaffolds those directories runs in `/v0-build`). Stories follow that pack's service skill.
2. Read `docs/agents-v0/design/system/context-map.md` from `/v0-architecture`. Name the bounded contexts already in that map. A story that needs a context the map does not list stops for an architecture amendment, not a silent edit. Report the unmapped context blocker to the main session and stop.
3. Choose the milestones. Start from `templates/docs/agents-v0/milestones/` (P0 skeleton, P1 contracts and data models, P2 MVP, P3 features, P4 hardening, P5 release readiness). Drop a milestone only with a recorded reason. Seeded P0-A is preserved. For subsequent milestones, replace template stubs (bracketed `[role]` placeholders, placeholder dependencies `P0`/`P1`, and unassigned Surface/Size `—`) with concrete stories.
4. Write each story row in `docs/agents-v0/milestones/<milestone>.md`:
   - Story ID (`P2-A`, `P2-B`, …). No duplicate story IDs across manifests.
   - User story: one full `As a [role], I want [goal], so that [benefit].` sentence. No `<...>` or `[...]` placeholders. Derive the role, goal, and benefit from the approved roadmap, its `Discovery:` file, and the architecture pack; ask the user only when those approved sources leave them ambiguous.
   - Feature artifact: a concrete path, `docs/agents-v0/requirements/<feature>.md`.
   - Status: `planned`.
   - Dependency: concrete story IDs only, comma-separated (cross-milestone story IDs such as `P1-B` on a P2 story are permitted; use `—` only when a root story has no dependency; bare milestone labels like `P0`, `P1`, or `P3` are not valid story dependencies).
   - Surface: `backend`, `bff`, `frontend`, or `vertical slice`.
   - Size: the number of acceptance criteria, `1`–`8`, including the negative or edge Intake will add. Seeded P0-A stays at `4`.
   - The user-story sentence states an outcome the approved roadmap already names. Foundational technical components mandated by the Architecture "Now" slice (e.g., local identity adapter, session store, persistence baseline) that support roadmap outcomes are authored as technical enabler stories in P1/P2 without adding unapproved product themes.
5. Record `Roadmap:` and `Architecture: docs/agents-v0/architecture.md` on each manifest in scope. Omit both lines only when the plan's only story is seeded P0-A. Size every story: one surface and at most eight acceptance criteria, including that negative or edge. Split a larger story into rows here. Use `Vertical slice: yes` only when the user asked for one journey across surfaces. Do not split the seeded P0-A platform skeleton row. It is already one story. Surface `vertical slice` and Size `4`.
6. Add an integration story for each pair of contexts that call each other. It depends on both sides, covers the contract and the failure modes, and is the place for consumer-driven contract tests.
7. Order the stories as a graph with no cycle. A story starts Build only after every story it names (including cross-milestone dependencies) has its Verify approval (`verify` in `approvedPhases` / `verifyPassed: true`).
8. Map each filled NFR/SLO row in `docs/agents-v0/design/system/nfr-slo.md` to a P4 hardening story (splitting across multiple P4 stories when needed so each story stays within Size ≤ 8), and split P5 release readiness across stories (e.g., `P5-A`, `P5-B`) so the 10-item checklist in `docs/agents-v0/design/system/ops-readiness.md` fits within Size ≤ 8 per story.
9. Write `docs/agents-v0/milestones/plan.md` from the manifests. Two parts only:
   - A table with columns `Milestone`, `Stories`, and `What they cover`. One row per milestone in the plan, from P0 when it is in scope. `Stories` lists the story ids in dependency order. `What they cover` is one line, not the user-story sentence.
   - A `flowchart TD` of every story (or one `flowchart TD` per milestone when the backlog exceeds ~50 stories so each diagram stays within the ~50-node Mermaid cap in `architecture-and-diagrams.mdc`). The node id is the story id with the hyphen removed (`P2-F` → `P2F`). The label is the story id (`P2F[P2-F]`). One arrow per dependency, including edges that cross milestones. A story with no dependency is a node with no incoming arrow.
10. Complete authoring and report back to the main session. The guard scripts handle phase results, state synchronization, external approvals, and gate commits; the planner runs no shell commands.

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc`: contexts, database per service, Mermaid conventions (≤ ~50 nodes per diagram; split `flowchart TD` per milestone when larger).
- [ ] `project-delivery-core.mdc`: async/messaging/cache justified; target `Service roots` / `BFF root` recorded in `context-map.md` and component plans (leaving `project-profile.md` roots as `n/a` until scaffolded on disk in `/v0-build`).
- [ ] Every story sentence is complete; every story fits the size budget (`1`–`8`), has a valid `Surface`, and names concrete story-ID dependencies.
- [ ] Every cross-context call has an integration story with both sides as dependencies.
- [ ] The dependency graph has no cycle and no duplicate story IDs across manifests.
- [ ] `docs/agents-v0/milestones/plan.md` is the milestone table and the story flowchart.
- [ ] `workflow-orchestration.mdc`: Plan gate met; stopped for approval.
