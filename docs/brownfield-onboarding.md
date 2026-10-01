# Brownfield onboarding (existing system)

Engineer checklist for adopting the delivery kit on a **legacy or in-flight** codebase
without blocking on a broken baseline or org coverage/CVE targets on day one.

## 1. Install the kit

```bash
./scripts/install.sh /path/to/existing-repo
# Optional Maven/docker/OpenAPI starters (copies full templates/ tree):
# ./scripts/install.sh --with-starters /path/to/existing-repo
```

Then run `/onboard` in chat (agent **`codebase-documenter`**, skill **`onboard-discovery`**). It documents the
codebase as it is today, with every statement cited to code or marked `UNVERIFIED`, and stops for your approval before `/intake` or `/plan`:

| Output | Path |
|--------|------|
| Report (scope, baseline, security triage, open questions, `onboard` approval) | `docs/onboarding/report.md` |
| One document per module | `docs/onboarding/modules/<module>.md` |
| Project profile (commands, Layout, `Service roots`, contracts) | `docs/project-profile.md` |
| Repository map, dependency graphs | `docs/repo-map.md`, `docs/discovery/dependency-graph*.txt` |
| Inventories: endpoints with authorization annotation, entities, migrations, messaging, scheduled work, outbound clients, configuration **key names**, frontend routes, CI and deploy files, tests | `docs/discovery/*.txt` |
| Baseline numbers and proposed `known_failures` / `coverage_ratchet` rows | `docs/discovery/baseline.md` |
| Security baseline snapshot (triage list; nothing is fixed) | `docs/discovery/security-baseline.md` |
| Proposed non-Spring endpoint rows (FastAPI, Express, Nest, Go) | `docs/discovery/endpoint-stacks.md` |
| As-is architecture, network, context map, inherited decisions, flows you name | `docs/architecture.md`, `docs/network.md`, `docs/design/system/context-map.md`, `docs/adr/0000-inherited-decisions.md`, `docs/diagrams/sequences/` |

Checks you can run yourself: `sh scripts/discover-codebase.sh` (refresh the inventories) and `sh scripts/check-onboarding-docs.sh` (every citation resolves; no template line left; every document names its commit). Lists are capped (`DISCOVER_MAX`, default 500) and say so when they are cut. No secret value is ever written; configuration appears by key name.
Record the directory layout in the profile **This repo** table (Profile `service`, `ui`, or `app`, or the discovered roots when the tree matches none of those). Do not move source onto a greenfield default.

Org rules are installed to `.cursor/rules/org/` and refreshed on `install.sh --update`.

The install seeds `.gitlab-ci.yml` (Maven `.m2/repository` cache and npm `.npm/` cache). If the repo already has a pipeline, merge the kit delivery jobs into that file instead of replacing it. Protect the default branch and the `delivery-approval` environment. Scope `GITLAB_TOKEN` (`read_api`, masked) to that environment only, and replace `@your-team` in `CODEOWNERS`. Set `ENABLE_GITLAB_SAST=1` when the instance provides the SAST template. Optional: `cp hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push` runs the local delivery gate when the branch name matches `docs/requirements/<feature>.md`. See [greenfield-onboarding.md](greenfield-onboarding.md).

## 2. Audit the baseline (do this before `/build` or `/maintain`)

From the agents-v0 kit repo:

```bash
./scripts/audit-brownfield-baseline.sh /path/to/existing-repo
```

The script runs the repo’s standard Java or frontend verify command when detected and
prints pass/fail. **Build and maintain agents stop if the baseline is red** — fix or
document a stabilization plan before feature work.

| Outcome | Action |
|---------|--------|
| Build green | Proceed with `/maintain` or feature `/intake` |
| Tests fail | Stabilization sprint: fix or quarantine flaky tests with team approval |
| Coverage below 80% / 70% | Phased ratchet — see step 3 |
| OWASP high/critical CVEs | Patch via `/maintain` + `dependency-upgrade`, or documented suppressions — see step 4 |

## 3. Phased quality thresholds

Org defaults are in `quality-and-testing.mdc` (80% backend / 70% frontend). When the repo cannot meet those yet:

1. Get Security + architecture sign-off on a **ratchet plan** (target dates, quarterly bumps).
2. Record interim thresholds and removal dates in `docs/project-profile.md` (`coverage_ratchet`, `known_failures` table).
3. Remove the ratchet entry when the repo meets org defaults.

Do **not** document weaker VAPT or auth controls — escalate to Security instead.

## 4. Documented CVE exceptions

1. Prefer upgrading dependencies (`/maintain`, skill `dependency-upgrade`).
2. If a CVE must be suppressed, add an entry to `maven/dependency-check-suppressions.xml`
   (starter: kit `templates/maven/dependency-check-suppressions.xml`).
3. Record the exception in the Verify test report (`docs/verify/<feature>/test-report.md`)
   per `quality-and-testing.mdc`.

## 5. Ongoing maintenance

Use `/maintain` for bugs, CVEs, and doc drift. Changes that touch auth, sessions,
routes, uploads, or security config must re-enter `/verify` (VAPT checklist).

Large rewrites or new subsystems should use full `/intake` and `/design`, not
`/maintain` alone.

## References

- [greenfield-onboarding.md](greenfield-onboarding.md) — new repos and P0 milestone
- [compliance-matrix.md](compliance-matrix.md) — which gate enforces each rule
- [user-guide.md](user-guide.md) — approver-facing workflow
