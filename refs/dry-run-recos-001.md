Change the kit so a first story, a non-API story, and a release without GitLab each have an explicit path. The dry run followed the commands and still hit contradictions in those three places.

## 1. Make the gates match the checks

| Gap | Change |
|-----|--------|
| `/v0-design` requires `openapi.yaml`, but `check-openapi.sh` rejects anything outside `/api/v1/` | In `.cursor/commands/v0-design.md`, say a story with no `/api/v1` operation records `N/A` in `design.md` and does not add a draft. `check-design.sh` already allows a missing file. |
| `/v0-verify` tells the agent to set `DIFF_BASE` and run OWASP. `check-gate-metrics.sh` skips coverage and CVEs unless `DIFF_BASE` or `REQUIRE_CVE_REPORT=1` | Make the command and the script the same rule. If the story’s out-of-scope list names a later quality story, the command must say to skip those two flags and quote the skip. |
| `/v0-build` says run verify before any edit and stop on failure | In that command, a missing module on the first P0 skeleton story is the work, not a broken baseline. Stop only when a module that already exists fails. |
| `check-milestone.sh` only enforces story IDs inside one manifest | Accept a manifest path in the Dependency column, and fail Build until that manifest’s `milestone` row is approved. The identity-before-P1 rule is currently prose. |

## 2. Fix the evidence commit sequence

In `/v0-build` and `release-pr`, replace “commit the code, then stamp” with three steps: commit the code, write reports whose `commit:` line is that SHA, commit the reports, then run `check-delivery-gate-local.sh`. The dry run failed the gate because the code commit and the evidence commit were split with no stated order.

Do not record a `release` row until `glab mr create` has returned a URL. Put that URL in the Artifacts cell. In `/v0-release`, if there is no `origin` or no `glab`, set `blocked` and do not write `Approved`.

## 3. Split the greenfield template from an installed repo

In `docs/agents-v0/milestones/p0-platform-skeleton.md`, drop or branch P0-B when `.cursor/` and `.agents-v0/` are already present. The seeded sentence says “install the kit” on a repo that already has it.

In `scaffold-service` and the design examples, name `@PreAuthorize("permitAll()")` for a public route. `org.springframework.security.access.prepost.PermitAll` is not a Spring Security 6 type. Also say to exclude `UserDetailsServiceAutoConfiguration`, because the starter logs a generated password until that is done. `check-endpoint-auth.sh` already accepts `@PreAuthorize`.

## 4. Label planned topology

`docs/agents-v0/network.md` is written at plan time and lists Postgres, the React app, and syslog before they exist. Add a Status column: `planned` or `built`, and cite a file only for `built`. The release doc sync should update `architecture.md` from the commit, and should not copy planned rows in as if they were running.