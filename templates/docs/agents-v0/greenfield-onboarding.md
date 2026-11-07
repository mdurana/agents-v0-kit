# Greenfield onboarding (new system)

Engineer checklist for starting a **new** service or app repo with the agents-v0
delivery kit and **incremental** milestone delivery (P0 → P5).

## 1. Create an empty repo (preferred) or scaffold outside the kit

**Preferred:** create an empty git repo (no application source yet). The kit bundles a
P0 codebase archive (`templates/app/p0-platform-skeleton.tar.gz`) that matches the
`java` example — Java 21, Spring Boot 4.1.1, Tomcat 11.0.26, Spring Security,
PostgreSQL 15, Flyway, React 19, TypeScript 5.9, Vite 7, Vitest 3 — health/shell only.
The user names the stack on the pattern ADR (`Pack: <id>`). A discovery `Stack preference:` line is an input the ADR may accept or reject. `/v0-architecture` writes a complete pack for that id (`pack.json`, `rules/*.mdc`, `implement-service`, `implement-bff`, and a UI manifest when `ui` names an id). The id does not have to be one of the example packs.

**Fallback** when you must use an external generator:

| Profile | Typical bootstrap |
|---------|-------------------|
| `service` | Framework starter per stack (Pack `java`: [start.spring.io](https://start.spring.io) or internal archetype; .NET `dotnet new`; FastAPI; NestJS; Go) with `baseDir=app/backend` |
| `ui` | The pack's UI under `app/frontend/`. The React example is Vite. |
| `app` | Backend under `app/backend/` and UI under `app/frontend/` |

Do not put `src/`, `pom.xml`, or `package.json` at the repo root. `docs/`, `.agents-v0/`, and `openapi/` stay there.

## 2. Install the kit, extract the app template, seed P0

From the **agents-v0** kit repo:

```bash
mkdir -p /path/to/your-new-repo && git -C /path/to/your-new-repo init
./scripts/bootstrap-greenfield.sh --profile app --pack java --scaffold-app /path/to/your-new-repo
```

`--pack java` (or no `--pack`) with `--scaffold-app` extracts `templates/app/p0-platform-skeleton.tar.gz` into `app/backend`
and/or `app/frontend` (and seeds `docker-compose.yml` for profile `app`) without
overwriting existing trees. `--pack dotnet` (or any other id) does not extract that archive. `--profile` is `service`, `ui`, or `app`. Omit `--profile`
to infer from the tree after extract. This also runs `install.sh --with-starters`, seeds
milestone manifests **P0–P5** and `docs/agents-v0/milestones/plan.md` when missing, and fills Layout / verify commands in
`docs/agents-v0/project-profile.md` when those cells are still placeholders.

Repack the archive after editing `templates/app/{backend,frontend}`:

```bash
./scripts/pack-app-template.sh
```

During P0 build stories, follow that pack's **`scaffold-service`**. The `java` example proves the bundled template and does not reinvent the health shell when the archive was used. Any other pack follows its own scaffold and does not extract the Java archive. An empty Pack stops until `/v0-architecture` writes the manifest.

To keep kit commits out of the project, pin the kit instead of copying it:

```bash
./scripts/install.sh --link --commit <sha> --url <kit-git-url> /path/to/your-new-repo
```

`--path` points at a local kit checkout. The pin is `docs/agents-v0/kit-pin`. Set `CI_PACK_IMAGE` to the pack's `ciImage`.
**Major** cross-cutting changes use **`system-design`** in `/v0-design`.

Manual equivalent:

```bash
./scripts/install.sh --with-starters /path/to/your-new-repo
./scripts/scaffold-app-template.sh --profile app /path/to/your-new-repo
cp /path/to/agents-v0/templates/docs/agents-v0/milestones/p0-platform-skeleton.md \
   /path/to/your-new-repo/docs/agents-v0/milestones/
```

The manual path without bootstrap does not fill Layout. Set the **This repo** rows in `docs/agents-v0/project-profile.md`, or re-run bootstrap with `--profile`.

On an Intel Mac, before the first verify command, run `sh .agents-v0/scripts/host-tools-macports.sh` to check tools named by the pack's `hostChecks` and PyYAML. Exit 2 means a tool is missing. Approve `sh .agents-v0/scripts/host-tools-macports.sh --install` ([gold-standards.md](gold-standards.md)).

Install PyYAML (`python3 -m pip install pyyaml`; on Intel macOS the host-tools script above covers it). Optional: `cp .agents-v0/hooks/pre-push "$(git rev-parse --git-path hooks)/pre-push" && chmod +x "$(git rev-parse --git-path hooks)/pre-push"` checks that `<feature>.state.json` has `verifyPassed: true` before pushing a feature branch. After Local Release, regulated teams may archive evidence with `sh .agents-v0/scripts/export-audit-pack.sh <feature>`. To remap Cursor models, edit `.cursor/model-config.json` (seeded on install), then run `sh .agents-v0/scripts/update-agents-model.sh`. Ensure `.gitignore` keeps `docs/agents-v0/build/` and `docs/agents-v0/verify/` committable.

## 3. Wire quality before heavy coding

Wire the test runner, coverage collector, and CVE reporting specified in the bound pack's `pack.json`.

For pack `java` (and `--scaffold-app`), the backend already binds JaCoCo, Checkstyle, SpotBugs, and the
`ci-security` OWASP profile; ArchUnit lives under `src/test`. For an external Java skeleton,
copy starters from `core/java/starters/maven/` into the build when applicable:

- `maven/quality-plugins.xml` — JaCoCo, Checkstyle, SpotBugs, OWASP Dependency-Check on `verify`
- `maven/contract-conformance.xml` — when OpenAPI is generated
- `maven/archunit/LayerRulesTest.java` — layer boundaries

For other packs (`dotnet`, `node`, `python`, `go`), follow that pack's `scaffold-service` skill and wire the test runner, coverage collector, and CVE reporting named in its `pack.json`.

See `docs/agents-v0/gold-standards.md` in the target repo after install.

For local run after `--scaffold-app` (profile `app`):

```bash
docker compose up --build -d
```

API `:8080`, UI `:8081`, `postgres:15-alpine`. See `docker/README.md` for single-service Dockerfile starters.

## 4. Run the gated workflow for the skeleton

P0 is the platform skeleton (`P0-A` in `docs/agents-v0/milestones/p0-platform-skeleton.md`) on the integration branch.

1. Run `/v0-scaffold` (`guard-scaffold.sh`) on the integration branch after `/v0-plan` is approved. When `--scaffold-app` already extracted the template, `platform-engineer` verifies AC-1–AC-4 (`Dockerfile`, `docker-compose.yml`, and native stack verify); it does not recreate the skeleton.
2. When `guard-scaffold.sh ready` sets `awaiting_approval`, approve the platform skeleton in your own terminal outside Cursor (`sh .agents-v0/scripts/guard-common.sh approve scaffold`) and run `sh .agents-v0/scripts/guard-scaffold.sh commit`.
3. Once `scaffold` is committed, run feature stories (`P1`–`P5`) via `/v0-deliver <feature>` (or phase by phase starting at `/v0-intake <feature>`). Each phase stops at its gate for external terminal approval (`sh .agents-v0/scripts/guard-common.sh approve <phase> <feature>` or `sh .agents-v0/scripts/guard-common.sh approve deliver <feature>`).

## 5. Advance milestones

After P0 go/no-go, a program of more than one story starts with `/v0-roadmap` and the path of the discovery document. That file may live anywhere in the repository. `/v0-architecture` then writes the C4-through-operations pack and the ARC record, `design-reviewer` reviews it, and it stops for one approval before any story. Plan reads that pack and fills Surface and Size on each story row. It does not rewrite the pack. A story that adds a service, a datastore, a security boundary, or a breaking API is `Material: yes`. Design cites `docs/agents-v0/design/system/arc-record.md` when the program recommendation already covers it. An `arc` row is written only when the story amends that recommendation. Who skips `/v0-architecture`: `workflow-orchestration.mdc` Lifecycle.

`/v0-export` and `/v0-deck` are optional. They do not gate a merge.

Copy `docs/agents-v0/milestones/_template.md` to `p1-contracts-and-data-models.md`, etc., per
[README.md](../README.md) milestone program (P1 contracts, P2 MVP, P3 features, P4
hardening, P5 release readiness) when those files are not already seeded.

## References

- Non-engineering overview: [user-guide.md](user-guide.md)
- Model routing: [model-routing-matrix.md](model-routing-matrix.md)
- Brownfield / legacy repos: [brownfield-onboarding.md](brownfield-onboarding.md). `/v0-onboard` is for an existing codebase only; its steps are listed there, generated from `guard-onboard.sh steps`.
