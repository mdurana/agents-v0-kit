The five recommendations overstate both the gaps and the score. Two are aimed at a product this kit does not build, two fight decisions the kit already encoded, and only the test-evidence and database-sandbox points describe a real weakness. Closing them as written would not produce a 4.97 kit.

The opening claim is that these are the last architectural limits on the way from 4.82 to 4.97. The scorecard cannot support that. The five weights add up to 80 percent, two rows stay at 5.0, and "closes all residual operational gaps" does not follow from rows that still land at 4.95. "Mathematically proven" for a 75 percent mutant-kill rate is a threshold, not a proof. There is no rubric in this repository that defines 4.82.

## 1. ODCS data contracts — decline as a kit default

The diagnosis does not match the repo. Nothing here depends on DataWorks or a warehouse tool. Design already has the two contracts this lifecycle is built for:

- OpenAPI, linted and checked for compatibility, then merged into the catalog at Build.
- AsyncAPI, linted when `asyncapi.yaml` exists, plus JSON Schema files under `events/` with an additive-evolution check in `check-event-schemas.sh`.
- `check-design.sh --pin` already writes a SHA-256 `design.lock` after approval.

ODCS (Bitol) is a real standard for analytical data products: tables, quality rules, owners, freshness. That is a different product from a service pack (`java`, `dotnet`, `node`, `python`, `go`) whose data section is entities, keys, indexes, retention, PII, and an expand/contract migration. Making `datacontract.yaml` mandatory would add a third contract to stories that have no dataset.

The pinning proposal also misses a smaller hole that does exist. `design_files()` hashes `design.md`, the OpenAPI file, `ux-spec.md`, `events/`, `mockups/`, and the cited ADR. It does not hash `asyncapi.yaml`, even though CI lints that file. If a contract pin is the goal, the fix is to include `asyncapi.yaml` in the existing hash.

The extra gates are a poor fit:

- A compat check that allows only additive dataset changes repeats `check-event-schemas.sh` and `check-openapi.sh compat` for a file most features will not have.
- Compiling ODCS quality rules through `datacontract-cli` in `/v0-verify` needs a warehouse or a loaded fixture. The kit's verify gate is the pack verify command plus coverage, CVEs, and reviewer reports.
- An AST rule that fails unindexed scans and `CROSS JOIN`s will flag admin jobs, small tables, and legitimate analytical SQL. PII is already a required part of `design.md`, reviewed by `design-reviewer`, and kept out of logs by the pack rules.
- A merge webhook into DataHub or OpenMetadata is a platform integration, and it picks the vendors the recommendation says it is trying to avoid.

## 2. Mutation testing — the loophole is real; the gate is the wrong first fix

`check-build-plan.sh` does not read Git history or watch a process go from exit 1 to exit 0. It reads the Build plan and the command-result cards in `build-report.md`. A done row must name a test that occurs in a test file, and some card with a non-zero exit must mention that name. `(no-red: <reason>)` waives the row, and `REQUIRE_RED=0` turns the check off.

That card is written by the same agent that writes the test. A green verify run is measured from JUnit, JaCoCo, and the CVE report by `check-gate-metrics.sh`. The red run is not. A tautology such as `assertNotNull` can be given a fabricated red card and still pass. That part of the recommendation is right.

A universal mutant-kill gate is a weak patch for that:

- The named tools cover Java (Pitest), Node (Stryker), and Python (mutmut). The kit also ships `dotnet` and `go`, which are absent from the proposal.
- A 75 percent score on every modified line is expensive, flaky on equivalent mutants, and noisy on DTOs, migrations, and UI. It will not be green on the first Verify of a brownfield repo.
- A test can kill a mutant and still assert the wrong behavior. The score does not prove the acceptance criterion.

The check that matches the kit's own rule — numbers come from tools, not from the agent — is to require the red card to point at a captured test report (non-zero exit, the test name present in the JUnit or pytest output), the same way the green run is judged. Mutation testing can sit beside that later as an optional pack field, scoped to changed production code, with a ratchet like `coverage_ratchet`, and with Stryker.NET and a Go mutator included if you add it.

## 3. MCP server and Git hooks — Cursor coupling is intentional

`validate-kit.sh` fails the kit if Claude or Kilo adapters, `.claude/`, or any MCP hook are present. `hooks.json` wires `beforeShellExecution` to `pre-shell.sh` on purpose. CI does not depend on that. `.gitlab-ci.yml` runs the gate scripts from the default branch, and an optional `.agents-v0/hooks/pre-push` already runs the local delivery gate. The agent experience is Cursor-only. The evidence path is already shell and GitLab.

Git hooks cannot replace the shell guard. `hook-policy.py` blocks force-push, hard reset, `printenv`, and reads of credential paths on any command the agent runs. `core.hooksPath` only sees Git events. `git commit`, `git push`, and a raw `curl` of a secret are different moments, and the first two already require their own human authorization. Setting `core.hooksPath` from `install.sh` would also change Git config, which this kit's install path does not do. The current pre-push hook is a documented copy into `.git/hooks`.

An MCP server that exposes `/v0-intake` through `/v0-release` and the state file would put phase transitions on a tool any MCP client can call. The kit's approval model is a person writing `Approved` in the handoff table. A tool named "request approval" does not make that decision harder to skip. The repo previously had MCP policy files and removed them. Putting them back is a product-scope change, not an unfinished refactor.

Rules are Cursor `.mdc` files (`alwaysApply`, `globs`), not neutral Markdown waiting for `compile-rules.sh`. A compiler that emits `.windsurfrules` and Claude prompts only pays off if you reverse the Cursor-only decision. Headless CI does not need it.

## 4. Ephemeral databases — tighten a hole the kit already names

The kit is not mock-only. `quality-and-testing.mdc` calls for Testcontainers for API, database, and messaging tests. `implement-messaging` requires them. The Java `implement-service` skill requires a Testcontainers test that applies the Flyway migration to the previous schema. `migration-safety` asks for an up/down test when down is supported, plus a written rollback. The GitLab build job starts `docker:27-dind` for that.

The escape hatch is real. The same testing rule says Testcontainers only when the repo already depends on them. The Java `pack.json` still lists an H2 test profile. An agent can satisfy `./mvnw -B clean verify` against H2 and Mockito and never start PostgreSQL. Race conditions, dialect SQL, and real foreign keys will not show up. That is the useful part of this recommendation.

The proposed hard fail is the wrong rule. `migration-safety` prefers expand/contract: additive migration, deploy, backfill, then a later contract. Many of those steps are deliberately irreversible. A gate that fails the build when down is missing would reject the rollout style the kit tells Build to use. Rollback is already a flag, a previous artifact, or a down script, recorded in the build report. Requiring every pack to declare PostgreSQL, Redis, and Kafka would also reject a service with no datastore.

A tighter rule, consistent with what Java Build already says: if the diff touches a migration or SQL, Verify must run at least one test against the database named in the profile (Testcontainers or Compose), and H2 does not satisfy that row. Keep the down migration optional, with the rollback note required.

## 5. Canary phase — deploy already exists; automation would skip the gate

`/v0-release` does not always stop at the merge. When `project-profile.md` has a Deploy table, `release-deploy` runs after the authorized merge: one human authorization per environment, the row's deploy command, a smoke check, a rollback command, and feature flags for migrations, auth, and public routes. Records go to `docs/agents-v0/release/<feature>/deploy-<environment>.md` in a follow-up docs merge. A project with no Deploy table stops at the merge on purpose. `nfr-slo.md` is closed at Verify by k6 or a waiver (`slo-evidence`), using p95, before production.

A new `/v0-deploy` that shifts traffic 5 percent, then 25 percent, then 100 percent, queries Prometheus, OpenTelemetry, or Datadog, rolls back by itself, and reopens Maintain removes the per-environment approval `release-deploy` exists to enforce. It also binds the kit to APM products, which recommendation 1 treats as a defect. Live error rate and p99 are not what `nfr-slo.md` records.

The Deploy table can grow a smoke command that checks the SLO the profile already named. The person still authorizes the environment, and a failed smoke still runs the recorded rollback and stops. That stays inside `release-deploy`.

## What is worth doing

| Recommendation | Verdict | If you change anything |
| --- | --- | --- |
| ODCS triad, SQL AST lint, catalog webhook | Out of scope for this kit | Hash `asyncapi.yaml` in `design.lock` |
| 75 percent mutation gate on the diff | Right problem, heavy fix | Bind the red card to a real failing test report; mutation only as an optional ratchet |
| MCP phase server and `core.hooksPath` | Conflicts with the Cursor-only, no-MCP kit | Leave shell policy on `pre-shell.sh`; CI already runs without the IDE |
| Mandatory containers and reversible migrations | Partially already required | Schema changes run against the profile database; H2 does not count; irreversible expand/contract stays legal |
| `/v0-deploy` with automatic canary rollback | Skips the human deploy gate | Optional SLO probe on the existing Deploy row |

The residual risk in this kit is self-reported red evidence, an H2 path around Testcontainers, and `asyncapi.yaml` left out of the design pin. The scorecard's other three items are scope changes, and adopting them would make the lifecycle larger without making those three holes smaller.