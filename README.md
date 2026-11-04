# Agentic Delivery Workflow Kit (agents-v0)

An agentic delivery kit for **Cursor** and **AGENTS.md / SKILL.md** compatible coding agents (Claude Code, Antigravity, Windsurf, VS Code Copilot). `scripts/install.sh` copies the core into a target repo. `scripts/install.sh --link` pins a kit commit in `docs/agents-v0/kit-pin` and symlinks `AGENTS.md`, `.cursor`, and `.agents-v0/scripts` instead of copying them.

The kit helps agents build and maintain enterprise-grade systems through a gated lifecycle: **Roadmap → Architecture → Plan** for a new program, then **Intake → Design → Build → Verify → Local Release / Release**, and **Maintain** feeding back into Verify. The stack is the id the user names on the pattern ADR (`Pack: <id>`); a discovery `Stack preference:` line is an input that the ADR may accept or reject, and the roadmap copies that line without installing a pack. `/v0-architecture` writes `.agents-v0/packs/<id>/pack.json` and its rules and skills, and binds it with `activate-stack-pack.sh` after the `architecture` row is approved. Any id is valid once that pack is complete (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id). Example packs under `core/` are not a closed list. The UI is the manifest's `ui` id when `ui` names an id (`core/ui/react` is the React example). The map of every command, record, and check is [templates/docs/agents-v0/agents-v0-kit.md](templates/docs/agents-v0/agents-v0-kit.md) (installed as `docs/agents-v0/agents-v0-kit.md`). A story with a contract, a UI, or a public route stops at every gate for explicit user approval. P0-A skips Intake and Design and stops once, at `/v0-local-release` or `/v0-release`. `bootstrap-greenfield.sh --scaffold-app` extracts the `java` example archive into `app/` only for that example. Another pack's P0-A follows that pack's scaffold skill. An empty `Pack` does not select Java. Build copies the milestone story, writes the N/A design, and proves that shell. A story with no `/api/v1` operation, no UX spec, and no public route continues to Build, unless it is `Material: yes` (a new service, datastore, security boundary, or breaking API); that story still stops at Design. Approval is never inferred. State, approvals, `baseCommit`, and on-disk artifact indexes are persisted in `<feature>.state.json` via `.agents-v0/scripts/sync-feature-state.sh`.

A feature’s progress is `docs/agents-v0/requirements/<feature>.state.json` (`.agents-v0/scripts/sync-feature-state.sh`). `lastApprovedPhase` and `approvedPhases` come only from explicit `--approve <phase>` transitions. `activePhase` plus `activeStatus` (`in_progress`, `awaiting_approval`, or `blocked`) is the phase in flight. `/v0-status <feature>` reads that file: `in_progress` or `blocked` runs the same phase again from files already on disk (`artifacts` map + `git diff <baseCommit>`); `awaiting_approval` waits and does not start the next phase. The user names the feature. The newest state file is not assumed to be the one they mean.

Different features may proceed in one checkout only while each writes its own `docs/agents-v0/requirements/<feature>.md`, state file, and `docs/agents-v0/design/<feature>/`. Design writes the feature contract draft at `docs/agents-v0/design/<feature>/openapi.yaml`. Build merges that approved draft into the org catalog (`openapi/api-v1.yaml` unless the profile names another file). Build, verify, release, and maintain stop when `git status` shows another feature’s code or a shared-file edit that is not this feature’s approved diff. Shared files include `docs/agents-v0/project-profile.md`, the org catalog, `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `README.md`, and build or CI files. The feature draft is not a shared file. Ordinary feature work does not rewrite `docs/agents-v0/project-profile.md`. Creating a branch needs explicit user authorization.

## Layout


| Path                   | Purpose                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `AGENTS.md`            | Kit lifecycle summary (reference; Cursor loads rules from `.cursor/rules/`)                                        |
| `core/common/`         | Lifecycle shared by every pack: commands, agents, rules, skills, hooks, Cursor adapter                            |
| `core/<id>/` and `core/ui/<id>/` | Example pack manifests, agents, rules, skills, hooks, and starters. A project pack lives in the target at `.agents-v0/packs/<id>/` |
| `core/common/commands/v0-*.md` | 16 entry points (`/v0-roadmap` … `/v0-deck`) |
| `core/common/agents/`  | Shared subagents. `backend-engineer` and `bff-engineer` live in the pack. 20 subagents in all |
| `core/common/skills/` plus each pack's `skills/` | 40 playbooks |
| `templates/`           | Project starters: GitLab CI, docs, Maven/OpenAPI/Docker snippets, `.cursorignore`; P0 app archive under `templates/app/` |
| `templates/docs/agents-v0/` | Kit reference docs (map, user guide, compliance, model routing); installed to `docs/agents-v0/` in target repos |
| `scripts/`             | `install.sh`, `link-project.sh`, `validate-kit.sh`, `bootstrap-greenfield.sh`, `scaffold-app-template.sh`, `pack-app-template.sh`, `audit-brownfield-baseline.sh` |




## Cursor install surface


| Concern                         | Location                                                                         |
| ------------------------------- | -------------------------------------------------------------------------------- |
| Always-on rules                 | `.cursor/rules/org/*.mdc` (`alwaysApply` where set)                              |
| Phase commands                  | `.cursor/commands/`                                                              |
| Subagents                       | `.cursor/agents/` (`model:`)                                                     |
| Role model overrides | `.cursor/model-config.json` (seeded from `.cursor/model-config.json`) |
| Skills                          | `.cursor/skills/`                                                                |
| Git/secret/state guardrails     | `.cursor/hooks.json` + `pre-shell.sh` + `pre-edit.sh` (`hook-policy.py`)         |
| Agent context ignores           | `.cursorignore`                                                                  |
| Stop reminder                   | `stop.sh`                                                                        |
| Session context                 | `session-start.sh`                                                               |




## Onboarding


| Scenario                       | Script / doc                                                                                                                                                                                                                                                          |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **New repo (greenfield)**      | Empty repo, then `./scripts/bootstrap-greenfield.sh --profile app --pack <id> /path/to/target-repo` (add `--scaffold-app` to extract `templates/app/p0-platform-skeleton.tar.gz` for the `java` example). Profiles: `service`, `ui`, or `app`. See [templates/docs/agents-v0/greenfield-onboarding.md](templates/docs/agents-v0/greenfield-onboarding.md) |
| **Existing repo (brownfield)** | `./scripts/install.sh /path/to/target-repo` then `./scripts/audit-brownfield-baseline.sh /path/to/target-repo` — do **not** use `--scaffold-app`. See [templates/docs/agents-v0/brownfield-onboarding.md](templates/docs/agents-v0/brownfield-onboarding.md) |




## Install

```bash
# install into a target repo (minimal templates; seeds the java example into .cursor)
./scripts/install.sh /path/to/target-repo
# or: ./scripts/install.sh --pack dotnet /path/to/target-repo
# pin the kit instead of copying it (project commits do not include kit files):
./scripts/install.sh --link --path /path/to/this-kit --commit "$(git rev-parse HEAD)" /path/to/target-repo
# greenfield / full starters (copies kit templates and core/<pack>/starters):
./scripts/install.sh --pack <id> --with-starters /path/to/target-repo
# preferred greenfield for Java example (kit + P0 app archive under app/):
./scripts/bootstrap-greenfield.sh --profile app --pack java --scaffold-app /path/to/new-repo
# after editing templates/app/{backend,frontend}, repack the install archive:
./scripts/pack-app-template.sh

# after kit changes: validate, refresh kit-managed files
./scripts/install.sh --update /path/to/target-repo
# offline or air-gapped (no Maven or network): same checks, minus the app-template build test
./scripts/install.sh --update --quick /path/to/target-repo
```

On an Intel Mac, missing host tools named by the bound pack's `hostChecks` are installed with MacPorts when a port exists (JDK 21, Node, npm, Python, Go): `sh .agents-v0/scripts/host-tools-macports.sh` (see `docs/agents-v0/gold-standards.md` after install). The .NET SDK comes from the pack image, not MacPorts. PyYAML uses the same script (`python3 -m pip install pyyaml`, or a `pyXY-yaml` port when Python is from MacPorts).

Seeded only when missing (never clobbered): `README.md` and project templates. Always refreshed on `--update`: `AGENTS.md`, `.cursor/` rules, agents, commands, skills, hooks, reference docs, `.agents-v0/scripts/*.{sh,py}` (including `sync-feature-state.sh`, `resolve-layout.sh`, `run-backend-verify.sh`, `endpoint_scan.py`, `packlib.py`), and example packs under `.agents-v0/packs/`. A project pack whose id is not an example is left in place. `--update` keeps the profile `Pack` row. `--link` writes `docs/agents-v0/kit-pin` and symlinks the kit checkout. The profile `Pack` is whatever id has a complete pack (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id). Example manifests under `core/` are not a closed list.

## Model routing

The kit routes by **role** — Plan, Build, Review, Explore, Debug, Schemas, Docs, Documenter, Orchestrator, and UX Designer — with default Cursor model IDs in [templates/docs/agents-v0/model-routing-matrix.md](templates/docs/agents-v0/model-routing-matrix.md) (installed to `docs/agents-v0/` in target repos). Build (critical) uses the Plan model. Those IDs match `.cursor/model-config.json`. `scripts/install.sh` seeds `.cursor/model-config.json` and runs `.agents-v0/scripts/update-agents-model.sh` to rewrite agent `model:` lines and sync the installed routing matrix from config (or `KIT_MODEL_*` env vars). Run that script again after you change the config. Kit source agents under `core/common/agents/` and `core/<pack>/agents/` keep the matrix defaults.

## Milestone delivery

Milestone programs (P0 Platform Skeleton, P1 Contracts & Data Models, P2 MVP/Core Features, P3 Features 1..N, P4 Hardening, P5 Release Readiness) are manifest-driven: `docs/agents-v0/milestones/<milestone>.md` groups user stories → feature chains, each story running the standard gated chain with approvals in its own `<feature>.state.json` and artifact. A program that is more than the seeded P0-A story starts from an approved roadmap (`/v0-roadmap`), then `/v0-architecture`; each manifest then records `Roadmap:` and `Architecture: docs/agents-v0/architecture.md`, and each story row has Surface and Size. Story artifacts record `Milestone:` / `Story:` traceability links (`spec-intake` skill). A P4 manifest that names `docs/agents-v0/design/system/slo-evidence.md` requires that file at `verify` and `release`: each filled SLO row in `docs/agents-v0/design/system/nfr-slo.md` is measured or waived. The ARC record points at that table. Template: `docs/agents-v0/milestones/_template.md`.

## Complex programs


| Need                                       | What the kit provides                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Decompose a large goal                     | `/v0-roadmap <discovery-path>` sequences a discovery file anywhere in the repo. `/v0-architecture` writes the C4-through-operations pack and the ARC record, and `design-reviewer` checks it, before any story. `/v0-plan` then writes the milestone manifests and `docs/agents-v0/milestones/plan.md` (milestone table and story flowchart) from that pack. Approvals are recorded in `docs/agents-v0/program.state.json` (`roadmap`, then `architecture`, then `plan`). Skip list: `workflow-orchestration.mdc` Lifecycle. A story starts Build only after the stories it depends on have `verify` in `approvedPhases` |
| Several services in one repo               | `Service roots` in the profile Layout (or `services/*/` auto-detected), one catalog per service, `.agents-v0/scripts/resolve-layout.sh` and `.agents-v0/scripts/run-backend-verify.sh` build and verify each root                                                                                                                                                                                                                                                                                                                                                     |
| Parallel features                          | `.agents-v0/scripts/feature-worktree.sh <feature>`: one worktree and branch per feature (needs explicit authorization; hooks ask)                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Native build & quality verification        | `.agents-v0/scripts/run-backend-verify.sh` runs the pack's native verify command (Pack `java`: JaCoCo 0.80, Checkstyle, SpotBugs, Surefire, ArchUnit, OWASP Dependency-Check; Pack `dotnet`: xUnit + Coverlet; Pack `node`: Jest; Pack `python`: pytest + coverage; Pack `go`: go test -cover). `test-engineer` (`quality-gate`), `security-reviewer` (`vapt-review`), and `code-reviewer` (`pr-review`) verify test execution, coverage (≥ 80% backend, ≥ 70% frontend, ≥ 80% changed lines), CVEs, and VAPT controls before `verifyPassed: true` is recorded |
| Fewer approval stops                       | Batch approval of Intake and Design for named, low-risk stories (`workflow-orchestration.mdc`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Bounded effort                             | `Phase attempt budget` (default 8 failed attempts per phase) checked by `.agents-v0/scripts/check-attempt-budget.sh`, plus `reopenCount ≤ 3` and `helperBriefHashes` loop protection in `.agents-v0/scripts/sync-feature-state.sh`                                                                                                                                                                                                                                                                                                                            |
| Messaging, E2E, deploy                     | Skills `implement-messaging`, `e2e-perf-testing`, `release-deploy` (profile **Deploy** table)                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Reviewer independence, critical units      | Review role on a stronger model than Build; security-trigger and saga units run on the Plan-role model (`docs/agents-v0/model-routing-matrix.md`)                                                                                                                                                                                                                                                                                                                                                                                                             |
| Document an existing codebase              | `/v0-onboard` (`codebase-documenter`, `onboard-discovery`): baseline numbers, layout-aware inventories in `docs/agents-v0/discovery/` (endpoints, entities, messaging, config key names, security baseline), cited module documents, as-is architecture and flows. `.agents-v0/scripts/check-onboarding-docs.sh` rejects a citation that does not resolve. Approval is recorded in `docs/agents-v0/onboarding/state.json` (`--approve onboard`) and `docs/agents-v0/onboarding/report.md`                                                                                   |
| Fixes, patches, upgrades, hotfixes         | `/v0-maintain` and `/v0-triage` keep a maintenance note (`docs/agents-v0/maintain/<id>/note.md`) and state file (`docs/agents-v0/maintain/<id>/state.json`) with its own tier, approvals, and evidence; the MR says `Maintain-Note:`. Trivial (docs-only or version-only, no security surface, schema, or major bump, confirmed by a person) gets an abbreviated Verify; emergency may merge first and owes Verify by a due date                                                                                                                                |
| Design you can verify, Build you can check | `/v0-design` writes `design.md` and, when the story adds a `/api/v1` operation, `openapi.yaml` (optional `asyncapi.yaml` for messaging). Prefer Design fill-ins under `docs/agents-v0/snippets/`. A story with no such operation records `N/A: no /api/v1 operation` and skips the draft. `design-reviewer` runs when there is an OpenAPI draft, an AsyncAPI or `events/` contract, a UI, or a public route other than `/health`, `/ready`, or `/live`. A later change after Design approval is an amendment (`--reopen design`, `design-reviewer`, user approval). A changed decision supersedes that ADR. A story with none of those continues to Build unless `Material: yes`; that story cites `docs/agents-v0/design/system/arc-record.md` and stops at Design. P0-A skips `/v0-intake` and `/v0-design`: after `--scaffold-app`, Build copies the milestone story and AC-1 through AC-4, writes that N/A design, and proves the seeded `app/` template |
| Local or remote release you can trust      | `/v0-deliver` chains phase commands. `/v0-local-release` records `release` in `<feature>.state.json` and fast-forwards the local integration branch so the next story can start without opening a GitLab MR. `/v0-release` renders the MR body (`.agents-v0/scripts/render-mr-body.sh`), opens the MR on explicit request, caps the CI fix loop at three rounds, and records `release`. Optional `.agents-v0/hooks/pre-push` checks `verifyPassed: true` in `<feature>.state.json` before pushing a feature branch. Regulated teams may archive evidence with `.agents-v0/scripts/export-audit-pack.sh`. `glab mr merge` and `glab mr approve` are blocked; `.agents-v0/scripts/release-notes.sh` updates the changelog |
| Measure the kit                            | `.agents-v0/scripts/delivery-metrics.sh` (Delivery effort)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |




## Validate the kit

```bash
./scripts/validate-kit.sh                       # validate the kit itself (no arguments)
./scripts/validate-kit.sh --target /path/to/target   # also validate an installed target
```

Kit checks: rule frontmatter, cross-references, all sixteen `v0-*` commands, README counts, agent `model:` fields against the routing matrix, Cursor adapter config, required template artifacts (including the P0 app archive and Design snippets), hook classifications, evidence contracts (Build/Verify), the always-on rule size budget (32 KB), the CI template (parses, names only scripts that exist under `.agents-v0/`, Node 22), minimum JaCoCo and ArchUnit versions in the app template, and shell syntax. Target checks: `AGENTS.md`, `.cursor/` tree, `.agents-v0/scripts/` and exec bits, seeded docs, MR template evidence contract, and `!docs/agents-v0/build/` ignore negations. Model availability in Cursor is not verified.