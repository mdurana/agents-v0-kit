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

On an Intel Mac, run `sh .agents-v0/scripts/host-tools-macports.sh` before the first build or maintain verify. Missing host tools named by the pack's `hostChecks` are installed with MacPorts when a port exists (JDK 21, Node, npm, Python, Go). The .NET SDK comes from the pack image, not MacPorts. PyYAML uses that script (`python3 -m pip install pyyaml`, or a `pyXY-yaml` port when Python is from MacPorts) ([gold-standards.md](gold-standards.md)).

Do **not** run `bootstrap-greenfield.sh --scaffold-app` on an existing codebase. That archive is for empty greenfield repos only; `/v0-onboard` records the tree as it is and does not move source onto `app/backend` / `app/frontend`.

### Before `/v0-onboard`: set up Cursor and git

Do these three steps once, before the first `/v0-onboard`:

1. **Set Cursor's auto-run to "ask every time".** Do this first. Cursor then asks you before each command the agent runs, and the kit's command hook still checks each one. Together they make it hard for the agent to run the approve step itself, but they are not a full guarantee: a script the agent writes and then runs, or passwordless `sudo` for your user, could get past them. Read each command before you allow it.
2. **Answer the workspace-trust prompt.** When Cursor (or `cursor-agent` in a terminal) opens the repo and asks whether you trust this folder, trust it only if it is your own repo. Cursor loads the project's hooks under `.cursor/` only in a trusted folder, so an untrusted folder runs with no kit hooks.
3. **Set your git name and email in the repo** before `guard-onboard.sh commit` makes the onboard commit, so that commit has a real author:

```bash
git config user.name "Your Name"
git config user.email "you@example.com"
```

Then run `/v0-onboard` in chat (agent **`codebase-documenter`**, skill **`onboard-discovery`**). It documents the
codebase as it is today, with every statement cited to code or marked `UNVERIFIED`, and stops for your approval before `/v0-roadmap`, `/v0-architecture`, `/v0-intake`, or `/v0-plan`.

The steps `/v0-onboard` follows are the same list as its command file, generated from `sh .agents-v0/scripts/guard-onboard.sh steps`:

<!-- BEGIN generated: sh .agents-v0/scripts/guard-onboard.sh steps (scripts/generate-onboard-steps.sh); do not edit -->
1. Run `sh .agents-v0/scripts/guard-onboard.sh start`. It begins or resumes onboarding and sets the state to `in_progress`. When it prints `REFUSED`, show its message and stop.
2. Run the inventories: `sh .agents-v0/scripts/generate-repo-map.sh`, `sh .agents-v0/scripts/collect-dependency-graphs.sh` and `sh .agents-v0/scripts/discover-codebase.sh`. When the profile `Pack` cell is empty or a placeholder, run `sh .agents-v0/scripts/activate-stack-pack.sh --detect`: exit 2 keeps the existing pack (no `--force` unless the user confirms a replacement), exit 3 asks the user for the pack id.
3. List the discovered modules. Ask the user which are in scope and which flows (up to three) need sequence diagrams. Do not guess.
4. Launch the `codebase-documenter` subagent (skill: `onboard-discovery`) with the scope answers. It reads code and writes the onboarding docs; it runs no commands. For each `docs/agents-v0/onboarding/<module>.helper-brief.md` it writes, launch one `explore-researcher` from this session and pass its result back.
5. On a blocker, run `sh .agents-v0/scripts/guard-onboard.sh block "<plain reason>"` and stop.
6. When the documenter reports the docs done, run `sh .agents-v0/scripts/guard-onboard.sh ready`. It records the baseline audit, runs the onboarding docs check and sets the state to `awaiting_approval`. When it prints `REFUSED`, have the documenter fix what it names, then run `ready` again.
7. Stop. Present the onboarding report, its open questions and the triage list. Next: Sensei reviews the onboarding docs and runs, in his own terminal outside Cursor: sh .agents-v0/scripts/guard-common.sh approve onboard. Never run approve yourself.
8. After the user says approve ran, run `sh .agents-v0/scripts/guard-onboard.sh commit`. It checks the approval, secret-scans and makes the one onboard commit with its `onboard-v<n>` tag. Then suggest: /v0-roadmap, /v0-intake, /v0-triage, or /v0-maintain.
<!-- END generated -->

`guard-onboard.sh` and `guard-common.sh` keep the onboarding state; nothing else writes it. A blocked run resumes with `guard-onboard.sh start`. Only the approver runs `approve`, in a terminal outside Cursor, and `guard-onboard.sh commit` makes the one onboard commit.

It writes:

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

When `Pack` is still empty, `/v0-onboard` runs `sh .agents-v0/scripts/activate-stack-pack.sh --detect`. No marker asks the person to name the pack id and to write its `pack.json`. Two markers stop so a person can choose. A `Pack` cell that already names an id stays, including an id that is not a kit example. A later roadmap or architecture does not replace that pack. Set `CI_PACK_IMAGE` to that pack's `ciImage`.

Checks you can run yourself: `sh .agents-v0/scripts/discover-codebase.sh` (refresh the inventories) and `sh .agents-v0/scripts/check-onboarding-docs.sh` (every citation resolves; no template line left; every document names its commit). Lists are capped (`DISCOVER_MAX`, default 500) and say so when they are cut. No secret value is ever written; configuration appears by key name.
Record the directory layout in the profile **This repo** table (Profile `service`, `ui`, or `app`, or the discovered roots when the tree matches none of those). Do not move source onto a greenfield default.

A copy install puts org rules in `.cursor/rules/org/` and refreshes them on `install.sh --update`. A `--link` install symlinks those rules to the pinned kit commit; a kit change reaches the project when the pin moves.

The install seeds `.gitlab-ci.yml` (Maven `.m2/repository` cache and npm `.npm/` cache). If the repo already has a pipeline, merge the kit delivery jobs into that file instead of replacing it. Protect the default branch, and replace `@your-team` in `CODEOWNERS`. Set `ENABLE_GITLAB_SAST=1` when the instance provides the SAST template. `install.sh --git-hooks` installs `pre-push`, which checks `docs/agents-v0/requirements/<feature>.state.json` and `docs/agents-v0/maintain/<id>/state.json` for the branch slug. See [greenfield-onboarding.md](greenfield-onboarding.md).

## 2. Audit the baseline (do this before `/v0-build` or `/v0-maintain`)

In the target repo (or `./scripts/audit-brownfield-baseline.sh /path/to/existing-repo` from the kit repo):

```bash
sh .agents-v0/scripts/audit-brownfield-baseline.sh
```

The script runs the repo’s Backend verify command from `docs/agents-v0/project-profile.md` (or detects Maven, Gradle, npm, pytest, Go, or dotnet test when the profile cell is not yet set) and
prints pass/fail. **Build and maintain agents stop if the baseline is red** — fix or
document a stabilization plan before feature work.

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
