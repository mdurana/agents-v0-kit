# Reference benchmark

A repeatable run of the kit on one multi-service project. It turns "how will the kit do on complex software" into numbers you can compare across kit versions and model choices. Nothing in the kit has run this benchmark yet; the first run sets the baseline.

## The project

An order platform, built from an empty repo (greenfield, profile `app`):

| Part | Choice |
|------|--------|
| Services | `services/order`, `services/inventory`, `services/payment` (Spring Boot 3, Java 21, one PostgreSQL schema each) |
| Integration | Kafka. `order` starts a saga: reserve stock, charge payment, confirm; each step has a compensation |
| BFF | `bff/` (aggregation, session edge) |
| UI | `frontend/` SvelteKit: order list, order detail, place order |
| Profile rows | `Profile: app`, `Service roots: services/order, services/inventory, services/payment`, `BFF root: bff/`, `Frontend root: frontend/` |

Install the kit with `./scripts/install.sh --with-starters <repo>`, then run `/v0-plan` with the goal "Customers place an order; stock is reserved and payment is taken, or the order is cancelled and everything is released."

## Expected plan (check `/v0-plan` output against this)

| Story | Surface / service | Depends on |
|-------|-------------------|------------|
| P0-A | skeleton, green build for all roots | — |
| P0-B | kit and milestone tracking | P0-A |
| P0-C | quality gate (JaCoCo, Checkstyle, SpotBugs, OWASP) per service | P0-A |
| P1-A | order, inventory, payment OpenAPI and event schemas | P0-A |
| P1-B | one persistence model and migration per service | P0-A |
| P2-A | inventory: reserve and release stock | P1-A, P1-B |
| P2-B | payment: charge and refund | P1-A, P1-B |
| P2-C | order: place order, saga orchestration | P2-A, P2-B |
| P2-D | integration: order↔inventory and order↔payment contract tests | P2-A, P2-B, P2-C |
| P2-E | BFF: order aggregation and placement | P2-C |
| P2-F | UI: order list, detail, place order | P2-E |
| P4-A | hardening: SLO evidence for placement, k6 under `perf/` | P2-F |

A plan passes when it has these stories (names may differ), no cycle, one surface per story, at most eight acceptance criteria each, and an integration story for every service pair.

## Run protocol

1. Fix the inputs and record them in the result file: kit version (`VERSION`), model per role (`docs/agents-v0/model-routing-matrix.md`), CI host (GitLab).
2. Run `/v0-plan`, then every story in dependency order with `/v0-deliver`. One feature per git worktree (`scripts/feature-worktree.sh`). Approve each gate; count a gate as a re-approval when you sent work back.
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
