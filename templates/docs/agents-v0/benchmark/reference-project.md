# Reference benchmark

A repeatable run of the kit on one multi-service project. It turns "how will the kit do on complex software" into numbers you can compare across kit versions and model choices. Nothing in the kit has run this benchmark yet; the first run sets the baseline.

## The project

An order platform, built from an empty repo (greenfield, profile `app`):

| Part | Choice |
|------|--------|
| Services | `services/order`, `services/inventory`, `services/payment` (Java 21, Spring Boot 4.1.1, one PostgreSQL 15 schema each) |
| Integration | Kafka. `order` starts a saga: reserve stock, charge payment, confirm; each step has a compensation |
| BFF | `bff/` (aggregation, session edge) |
| UI | `frontend/` React 19 + Vite 7: order list, order detail, place order |
| Profile rows | `Profile: app`, `Service roots: services/order, services/inventory, services/payment`, `BFF root: bff/`, `Frontend root: frontend/` |

Start from an empty repo with `./scripts/bootstrap-greenfield.sh --profile app --scaffold-app <repo>` (P0-A uses the bundled health/shell template under `app/`). Evolve Layout to multi-service roots as stories require. Write a discovery file anywhere in the repo (for this benchmark, `notes/order-discovery.md`) with the headings Problem, Success metric, Options, Chosen option, In scope, and Out of scope. The problem sentence is: "Customers place an order; stock is reserved and payment is taken, or the order is cancelled and everything is released." Run `/v0-roadmap notes/order-discovery.md`, approve it, then `/v0-architecture`, approve it, then `/v0-plan`. P0-A is inside this program, so the roadmap and the architecture pack are required.

## Expected plan (check `/v0-plan` output against this)

| Story | Surface / service | Depends on |
|-------|-------------------|------------|
| P0-A | skeleton: green build, kit manifest, quality gate, local container | — |
| P1-A | order, inventory, payment OpenAPI and event schemas | P0-A |
| P1-B | one persistence model and migration per service | P0-A |
| P2-A | inventory: reserve and release stock | P1-A, P1-B |
| P2-B | payment: charge and refund | P1-A, P1-B |
| P2-C | order: place order, saga orchestration | P2-A, P2-B |
| P2-D | integration: order↔inventory and order↔payment contract tests | P2-A, P2-B, P2-C |
| P2-E | BFF: order aggregation and placement | P2-C |
| P2-F | UI: order list, detail, place order | P2-E |
| P4-A | hardening: SLO evidence for placement, k6 under `perf/` | P2-F |

A plan passes when `docs/agents-v0/milestones/plan.md` has the milestone table and a `flowchart TD` of these story ids, the manifests have these stories (names may differ), no cycle, Surface and Size filled, one surface per story, at most eight acceptance criteria each, including the negative or edge Intake will add, an integration story for every service pair, a `Roadmap:` line whose file has an `Approved` `roadmap` row, and `Architecture: docs/agents-v0/architecture.md` with an `Approved` `architecture` row. Every story goal is an in-scope item from that discovery file and names a context already on the context map.

## Run protocol

1. Fix the inputs and record them in the result file: kit version (`VERSION`), model per role (`docs/agents-v0/model-routing-matrix.md`), CI host (GitLab).
2. Run `/v0-roadmap`, approve it, then `/v0-architecture`, approve it, then `/v0-plan`. Run every story in dependency order with `/v0-deliver`. P0-A starts at `/v0-build`. One feature per git worktree (`scripts/feature-worktree.sh`). Approve each gate; count a gate as a re-approval when you sent work back. A story that adds a service is `Material: yes` and stops for the ARC record.
3. Batch the Intake and Design approvals of the P2 stories once (`workflow-orchestration.mdc` Batch approval) and record that you did.
4. Stop a story when its phase is `blocked` and record the blocked reason. Do not hand-edit code to unblock it; the point is what the kit does without help.
5. After the last story, run `sh .agents-v0/scripts/delivery-metrics.sh . > docs/agents-v0/benchmark/results/<YYYY-MM-DD>-<kit-version>.md` in the project and add the manual rows below.

## Metrics

| Metric | Source | Why it matters |
|--------|--------|----------------|
| Stories finished / stories planned | state files | Does the kit finish the program |
| Approved gates per story (target 5, batch counts once) | `delivery-metrics.sh` Delivery effort | Human cost |
| Re-approvals per story | manual count | Rework the gates missed |
| Failed attempts per story | `delivery-metrics.sh` Delivery effort | Build loop health; compare to the attempt budget |
| Stories `blocked`, with reasons | state files | Where the kit stops |
| Critical findings at first Verify, per story | `docs/agents-v0/verify/*/vapt-checklist.md`, `review-notes.md` | Build quality |
| Diff coverage at first CI run | `target/gate-metrics.json` | Tests written with the code |
| CI red runs per merge request | CI | Gaps between local and CI gates |
| Hook decisions: ask / block | `delivery-metrics.sh` Hook decisions | Guardrail pressure |
| Wall-clock days, plan to last merge | approval dates | Cycle time |
| Tokens or cost per story | Cursor billing | Spend |
| Defects found after the last merge (integration run, manual) | tester | What the gates did not catch |

## Result file

Copy this block into `docs/agents-v0/benchmark/results/<YYYY-MM-DD>-<kit-version>.md`.

```text
Kit version: <VERSION>
Models: <plan/build/review/debug model IDs from model-routing-matrix>
CI host: GitLab
Stories finished: <n>/12   Blocked: <n> (<story: reason>, ...)
Approved gates per story: <avg>   Re-approvals per story: <avg>
Failed attempts per story: <avg>  Max in one story: <n>
Critical findings at first Verify: <total>
Diff coverage at first CI run: <min / avg>
CI red runs per MR: <avg>
Cycle time (days): <n>   Cost: <n>
Defects after last merge: <n> (<short list>)
Notes: <what stopped the kit, what it did well>
```

## Reading the result

| Signal | Likely cause | Where to look |
|--------|--------------|---------------|
| Many `blocked` on Build | attempt budget too low, or the Build-role model is too weak for the unit | `Phase attempt budget`, `Build (critical)` row |
| Many re-approvals at Design | `/v0-plan` stories too large or contexts unclear | `program-planning`, context map |
| Critical findings at first Verify, mostly auth | Build ignores `vapt-spring.mdc` | raise those units to Build (critical) |
| Low diff coverage, green build | tests are not written with the code | `implement-*` step 6, `check-gate-metrics.sh` |
| CI red after green local | local gate differs from CI | project-profile verify commands |
| Defects after the last merge | integration or resilience gaps | `e2e-perf-testing` |
