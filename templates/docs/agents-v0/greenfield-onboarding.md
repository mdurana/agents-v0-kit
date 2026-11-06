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

Wire CI with the seeded `.gitlab-ci.yml` when using GitLab. For air-gapped runners, set GitLab CI variable `CI_IMAGE_PREFIX` to your mirror prefix (document the same value in the profile's **CI image prefix** row). The build job uses Docker-in-Docker and caches `.m2/repository`; the frontend and e2e jobs cache `.npm/`. Set `ENABLE_GITLAB_SAST=1` when the instance provides the SAST template. Install PyYAML (`python3 -m pip install pyyaml`; on Intel macOS the host-tools script above covers it). Optional: `cp .agents-v0/hooks/pre-push "$(git rev-parse --git-path hooks)/pre-push" && chmod +x "$(git rev-parse --git-path hooks)/pre-push"` checks that `<feature>.state.json` has `verifyPassed: true` before pushing a feature branch. After Release, regulated teams may archive evidence with `sh .agents-v0/scripts/export-audit-pack.sh <feature>`. To remap Cursor models, edit `.cursor/model-config.json` (seeded on install), then run `sh .agents-v0/scripts/update-agents-model.sh`. Ensure `.gitignore` keeps `docs/agents-v0/build/` and `docs/agents-v0/verify/` committable.

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

P0 is one story (`P0-A` in `docs/agents-v0/milestones/p0-platform-skeleton.md`): one branch and one merge request.

1. `/v0-build`, or `/v0-deliver` for the story end-to-end. Do not run `/v0-intake` or `/v0-design`. Build copies the milestone story and AC-1 through AC-4 and writes `design.md` (`N/A: no /api/v1 operation`, Events `N/A: no event contract`). When `--scaffold-app` already extracted the template, prove AC-1–AC-4; do not recreate the skeleton. A missing module on this first skeleton story is the work only when no template was used. A module that already exists must verify clean before edits. A `/health`, `/ready`, or `/live` route with the pack public marker (Pack `java`: `@PreAuthorize("permitAll()")`) does not by itself require `design-reviewer`.
2. `/v0-verify` then `/v0-local-release`. Do not stop for a separate approval at Build or Verify. The one approval is at `/v0-local-release` after the test report exists (or run `/v0-scaffold` on the integration branch).

Record approvals in `<feature>.state.json` via `sh .agents-v0/scripts/sync-feature-state.sh <feature> --approve <phase>`.

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
