# Greenfield onboarding (new system)

Engineer checklist for starting a **new** service or app repo with the agents-v0
delivery kit and **incremental** milestone delivery (P0 → P5).

## 1. Scaffold the application (outside the kit)

The kit does not run Spring Initializr or frontend CLIs for you. Create the repo with
your team’s standard generator, then open it in Cursor.

| Profile | Typical bootstrap |
|---------|-------------------|
| `service` | [start.spring.io](https://start.spring.io) or internal archetype with `baseDir=backend` — Java 17+, Spring Boot 3.x, Flyway if using PostgreSQL. A BFF-only repo uses `baseDir=bff` and stays thin per `project-delivery-core.mdc` |
| `ui` | SvelteKit (`npx sv create frontend`) or React (Vite or org template) under `frontend/` |
| `app` | Spring Initializr with `baseDir=backend`. UI under `frontend/`. Add `bff/` only when a BFF is in scope |

Do not scaffold `src/`, `pom.xml`, or `package.json` at the repo root. `docs/`, `ci/`, and `openapi/` stay there.

Commit the initial skeleton (or use an empty repo) before installing the kit.

## 2. Install the kit and seed P0

From the **agents-v0** kit repo:

```bash
./scripts/bootstrap-greenfield.sh --profile app /path/to/your-new-repo
```

`--profile` is `service`, `ui`, or `app` (`project-delivery-core.mdc`). Omit it to infer the profile from `pom.xml`, `backend/pom.xml`, or `package.json`. This runs `install.sh --with-starters`, seeds milestone manifests **P0–P5** when missing, and fills the Layout rows plus verify commands in `docs/project-profile.md` when those cells are still placeholders.

During P0 build stories, agents follow the **`scaffold-service`** skill (secure defaults,
quality plugins, container starter). **Major** cross-cutting changes use **`system-design`** in `/design`.

Manual equivalent:

```bash
./scripts/install.sh /path/to/your-new-repo
cp /path/to/agents-v0/templates/docs/milestones/p0-platform-skeleton.md \
   /path/to/your-new-repo/docs/milestones/
```

The manual path does not fill Layout. Set the **This repo** rows in `docs/project-profile.md`, or re-run bootstrap with `--profile`.

Wire CI with the seeded `.gitlab-ci.yml` (on-prem GitLab). Protect the default branch (merge requests only; no direct push) and turn on Code Owner approval for `.gitlab-ci.yml`, `ci/`, and `.cursor/`. Set `GITLAB_TOKEN` (`read_api`, masked) on the protected `delivery-approval` environment only, and replace `@your-team` in `CODEOWNERS`. Check the token and the Docker runner choice with `sh scripts/verify-gitlab-ci-prereqs.sh` (`GITLAB_HOST`, `GITLAB_PROJECT_ID`). For air-gapped runners, set GitLab CI variable `CI_IMAGE_PREFIX` to your mirror prefix (document the same value in the profile's **CI image prefix** row). The build job uses privileged Docker-in-Docker and caches `.m2/repository`; the frontend and e2e jobs cache `.npm/`. When privileged jobs are forbidden, follow the `/var/run/docker.sock` comment on the build job. Set `ENABLE_GITLAB_SAST=1` when the instance provides the SAST template. Install PyYAML (`pip install pyyaml`) so local OpenAPI checks run. Before pushing a feature branch, run `sh scripts/check-delivery-gate-local.sh <feature>`. To run that gate on every push, copy `hooks/pre-push` to `.git/hooks/pre-push` and mark it executable. After Release, regulated teams may archive evidence with `sh scripts/export-audit-pack.sh <feature>`. To remap Cursor models, copy `templates/.cursor/model-config.json.example` to `.cursor/model-config.json` and re-run install. Ensure `.gitignore` keeps `docs/build/` and `docs/verify/` committable.

## 3. Wire quality before heavy coding

Copy kit starters into the Maven build when applicable:

- `maven/quality-plugins.xml` — JaCoCo, Checkstyle, SpotBugs, OWASP Dependency-Check on `verify`
- `maven/contract-conformance.xml` — when OpenAPI is generated
- `maven/archunit/LayerRulesTest.java` — layer boundaries

See `templates/docs/quality-gates-engineering-principles.md` and
`docs/gold-standards.md` in the target repo after install.

For local container testing, copy a `docker/Dockerfile.*` starter to `Dockerfile`, then:

```bash
./scripts/run-local-container.sh
```

See `docker/README.md` in the target repo after install.

## 4. Run the gated workflow per story

For each row in `docs/milestones/p0-platform-skeleton.md`:

1. `/intake` — paste the user story as `As a [role], I want [goal], so that [benefit].`; approve Intake.
2. `/design` — contracts/ADR only when the story needs them (P0-C may reference Maven only).
3. `/build` — agents require a **green baseline** before edits (`/build` command).
4. `/verify` then `/release` per story, or `/deliver` for a single story end-to-end.

Record approvals in each feature artifact’s `Delivery approvals` table. CI uses
`ci/check-approvals.sh` and `ci/check-evidence.sh`.

## 5. Advance milestones

After P0 go/no-go (`milestone` row approved, `check-milestone.sh` green), copy
`docs/milestones/_template.md` to `p1-contracts-and-data-models.md`, etc., per
[README.md](../README.md) milestone program (P1 contracts, P2 MVP, P3 features, P4
hardening, P5 release readiness).

## References

- Non-engineering overview: [user-guide.md](user-guide.md)
- Model routing: [model-routing-matrix.md](model-routing-matrix.md)
- Brownfield / legacy repos: [brownfield-onboarding.md](brownfield-onboarding.md)
