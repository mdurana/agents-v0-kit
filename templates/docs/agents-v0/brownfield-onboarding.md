# Brownfield onboarding (existing system)

Engineer checklist for adopting the delivery kit on a **legacy or in-flight** codebase
without blocking on a broken baseline or org coverage/CVE targets on day one.

## 1. Install the kit

```bash
./scripts/install.sh /path/to/existing-repo
# Pin the kit commit instead of copying kit files:
# ./scripts/install.sh --link --commit <sha> --url <kit-git-url> /path/to/existing-repo
# Optional starters (--with-starters copies templates/ except app/, plus core/<pack>/starters/):
# ./scripts/install.sh --pack <id> --with-starters /path/to/existing-repo
```

**Prerequisites:** `git`, a POSIX `sh`, and `python3` 3.6 or later: the gate checks (`gate-checks.sh`) and the secret scan (`secret_scan.py`) run on it, and the shell hooks need 3.8 or later. On a Mac, `python3` comes with the Xcode command line tools: run `xcode-select --install`.

On an Intel Mac, run `sh .agents-v0/scripts/host-tools-macports.sh` before the first build or maintain verify. Missing host tools named by the pack's `hostChecks` are installed with MacPorts when a port exists (JDK 21, Node, npm, Python, Go). The .NET SDK comes from the pack image, not MacPorts. PyYAML uses that script (`python3 -m pip install pyyaml`, or a `pyXY-yaml` port when Python is from MacPorts) ([gold-standards.md](gold-standards.md)).

Do **not** run `bootstrap-greenfield.sh --scaffold-app` on an existing codebase. That archive is for empty greenfield repos only; `/v0-onboard` records the tree as it is and does not move source onto `app/backend` / `app/frontend`.

Then run `/v0-onboard` in chat (agent **`codebase-documenter`**, skill **`onboard-discovery`**). It documents the
codebase as it is today, with every statement cited to code or marked `UNVERIFIED`, and stops for your approval before `/v0-roadmap`, `/v0-architecture`, `/v0-intake`, `/v0-plan`, `/v0-deliver`, `/v0-triage`, or `/v0-maintain`:

**After onboarding.** `/v0-roadmap`, `/v0-intake`, `/v0-plan`, `/v0-architecture`, `/v0-deliver`, `/v0-triage` and `/v0-maintain` refuse to start until `onboard` is approved and that approval is committed. The onboard commit runs a staged secret scan and a commit-message check, then asks you once in supervised mode; it must run through the chain documented in `/v0-onboard`, not a hand-made `git commit`. A finished onboard (awaiting approval or approved) cannot be restarted without a reopen, and reopen is not available yet.

| Output | Path |
|--------|------|
| Report (scope, baseline, security triage, open questions, `onboard` approval) | `docs/agents-v0/onboarding/report.md` |
| One document per module | `docs/agents-v0/onboarding/modules/<module>.md` |
| Project profile (commands, Layout, `Service roots`, contracts) | `docs/agents-v0/project-profile.md` |
| Repository map, dependency graphs | `docs/agents-v0/repo-map.md`, `docs/agents-v0/discovery/dependency-graph*.txt` |
| Inventories: endpoints with authorization annotation, entities, migrations, messaging, scheduled work, outbound clients, configuration **key names**, frontend routes, CI and deploy files, tests | `docs/agents-v0/discovery/*.txt` |
| Baseline numbers and proposed `known_failures` / `coverage_ratchet` rows | `docs/agents-v0/discovery/baseline.md` |
| Security baseline snapshot (triage list; nothing is fixed) | `docs/agents-v0/discovery/security-baseline.md` |
| Proposed endpoint rows (.NET, Nest, Express, FastAPI, Django, Go), same regexes as `.agents-v0/scripts/endpoint_scan.py` | `docs/agents-v0/discovery/endpoint-stacks.md` |
| As-is architecture, network, context map, inherited decisions, flows you name | `docs/agents-v0/architecture.md`, `docs/agents-v0/network.md`, `docs/agents-v0/design/system/context-map.md`, `docs/agents-v0/adr/0000-inherited-decisions.md`, `docs/agents-v0/diagrams/sequences/` |

When `Pack` is still empty, `/v0-onboard` runs `sh .agents-v0/scripts/activate-stack-pack.sh --detect`. No marker asks the person to name the pack id and to write its `pack.json`. Two markers stop so a person can choose. A `Pack` cell that already names an id stays, including an id that is not a kit example. A later roadmap or architecture does not replace that pack.

Checks you can run yourself: `sh .agents-v0/scripts/discover-codebase.sh` (refresh the inventories) and `sh .agents-v0/scripts/check-onboarding-docs.sh` (every backticked citation resolves; no template line left; every document under `docs/agents-v0/onboarding/` has a `commit:` line). At the Onboard gate run it with `--gate`: it also requires the gate documents listed in `.agents-v0/scripts/gate-rules`, checks that every `commit:` stamp is a commit in the history of HEAD, and reports an unbackticked citation as a `WARN` line. Lists are capped (`DISCOVER_MAX`, default 500) and say so when they are cut. No secret value is ever written; configuration appears by key name.
Record the directory layout in the profile **This repo** table (Profile `service`, `ui`, or `app`, or the discovered roots when the tree matches none of those). Do not move source onto a greenfield default.

A copy install puts org rules in `.cursor/rules/org/` and refreshes them on `install.sh --update`. A `--link` install symlinks those rules to the pinned kit commit; a kit change reaches the project when the pin moves.

The kit ships no CI pipeline and no `CODEOWNERS`: the repo keeps its own CI if it has one, and the install leaves an existing `.gitlab-ci.yml` or `CODEOWNERS` untouched. The kit's checks run locally at the gates. `install.sh --git-hooks` installs `pre-push`, which checks `docs/agents-v0/requirements/<feature>.state.json` and `docs/agents-v0/maintain/<id>/state.json` for the branch slug. See [greenfield-onboarding.md](greenfield-onboarding.md).

## 2. Audit the baseline (do this before `/v0-build` or `/v0-maintain`)

In the target repo (or `./scripts/audit-brownfield-baseline.sh /path/to/existing-repo` from the kit repo):

```bash
sh .agents-v0/scripts/audit-brownfield-baseline.sh
```

The script runs the repo’s Backend verify command from `docs/agents-v0/project-profile.md` (or detects Maven, Gradle, npm, pytest, Go, or dotnet test when the profile cell is not yet set) and
prints pass/fail. Onboard records a red baseline and continues. **Build and maintain agents stop if the baseline is red** until it is fixed or every failure is
accepted by name (the scripted `baseline_ok` check is not wired into `/v0-build` and `/v0-maintain` yet; until it is, the agents stop by instruction).

| Outcome | Action |
|---------|--------|
| Build green | Proceed with `/v0-maintain` or feature `/v0-intake` |
| Tests fail | Stabilization sprint: fix or quarantine flaky tests with team approval |
| Report coverage below 80% / 70% | Phased ratchet — see step 3 |
| OWASP high/critical CVEs | Patch via `/v0-maintain` + `dependency-upgrade`, or documented suppressions — see step 4 |

## 3. Phased quality thresholds

Org report targets are in `quality-and-testing.mdc` (80% backend / 70% frontend, and 80% changed lines). A `coverage_ratchet` row is a dated waiver record verified during `/v0-verify`. When the repo cannot yet meet the report target:

1. Get Security + architecture sign-off on a **ratchet plan** (target dates, quarterly bumps).
2. Record interim thresholds and removal dates in `docs/agents-v0/project-profile.md` (`coverage_ratchet`, `known_failures` table).
3. Remove the ratchet entry when the repo meets org defaults.

Do **not** document weaker VAPT or auth controls — escalate to Security instead.

## 4. Documented CVE exceptions

1. Prefer upgrading dependencies (`/v0-maintain`, skill `dependency-upgrade`).
2. If a CVE must be suppressed in pack `java`, add an entry to `maven/dependency-check-suppressions.xml`
   (starter: kit `core/java/starters/maven/dependency-check-suppressions.xml`). Other packs record CVE suppressions in the format expected by their CVE scanner (see the pack's `pack.json`).
3. Record the exception in the Verify report (`docs/agents-v0/verify/<feature>/quality-gate.md`)
   per `quality-and-testing.mdc`.

## 5. Ongoing maintenance

Use `/v0-maintain` for bugs, CVEs, and doc drift. Changes that touch auth, sessions,
routes, uploads, or security config must re-enter `/v0-verify` (VAPT checklist).

A new program of more than one story, after the `onboard` row is approved, starts with `/v0-roadmap` and a discovery file anywhere in the repo, then `/v0-architecture`, then `/v0-plan`. Architecture extends the as-is `docs/agents-v0/architecture.md` and `docs/agents-v0/network.md`. It does not delete their citations. A named ticket starts at `/v0-intake`. Large rewrites or new subsystems use that program path, or full `/v0-intake` and `/v0-design` for one story, not `/v0-maintain` alone. The inventories under `docs/agents-v0/discovery/` are the onboard baseline. They are not the product discovery file `/v0-roadmap` reads.

## References

- [greenfield-onboarding.md](greenfield-onboarding.md) — new repos and P0 milestone
- [agents-v0-kit.md](agents-v0-kit.md) — commands, records, and the checks CI runs
- [user-guide.md](user-guide.md) — approver-facing workflow
