# Kit fixes found by the e2e test plan

One section per fix, in the format of `refs/e2e-test-plan/fix-and-resume.md` §4.2. Every changed file carries the fix id in a comment.

## kitfix-20261029-step4-p1e
Defect: after the local release of a story, nothing stopped the agent from running `sync-feature-state.sh --approve release` again in the feature worktree and committing there, so `feature/<feature>` ended up ahead of the integration branch; the `v0-local-release` prompts did not forbid it, the script did not check the branch, and no check compared the branch with the integration branch.
Evidence: Linode e2e run `run-20261029-1629` (kit `0aa3a43`, agy driver), step 4 chain story P1-E: the agent merged `feature/<P1-E slug>` into `main`, ran `--approve release` on `main` and committed, then ran `--approve release` in the feature worktree and committed again (98fa7a9, left out of its final summary). The harness merged the branch a second time; the merge conflicted in the story's state.json and H1/H2/H5 failed (`fix-and-resume.md` §5.6, "Known agent logic error (P1-E)"; run backup `run-backup-20261029-p1e-end.tar.zst`).
Fix:
- `templates/.agents-v0/scripts/sync-feature-state.sh`: `--approve release` exits 1 with a clear `FAIL` message unless the current branch is the integration branch from `resolve-integration-branch.sh` (profile `Integration branch` row, else origin/HEAD's branch, else `main`/`master`). A detached HEAD is refused. P0-A needs no exception: it is released on the integration branch already. Outside a git work tree, or when no integration branch can be resolved (`HEAD`), nothing changes.
- `templates/.agents-v0/scripts/check-release-evidence.sh`: for a released story whose `feature/<feature>` branch still exists, fails (exit 1) unless `git merge-base --is-ancestor feature/<feature> <integration>` holds, and lists the commits that are only on the feature branch. No feature branch (P0-A, or deleted after the merge): nothing to check.
- `core/common/commands/v0-local-release.md` (installed as `.agents/skills/v0-local-release/SKILL.md` and the `v0-local-release` command) and `core/common/skills/local-release/SKILL.md`: after the merge, do not commit to `feature/<feature>` / `maintain/<id>` or update its state; release approval happens only on the integration branch; run `check-release-evidence.sh` after the release-state commit and stop on exit 1; the final summary lists every commit made (SHA, branch, subject).
- `core/common/commands/v0-release.md`, `core/common/skills/release-pr/SKILL.md`: the remote-release `--approve release` also runs in the integration checkout after it holds the merge (the guard applies there too).
- `scripts/test-maintain.sh`: copies `resolve-integration-branch.sh`, merges each note branch into the integration branch before `--approve release`, and checks that `--approve release` on a story branch is refused.
How to check: `sh scripts/test-maintain.sh` prints `ok: state: --approve release is refused on a story branch (kitfix-20261029-step4-p1e)` and `test-maintain: OK`; in a repo with `feature/x` checked out, `sh .agents-v0/scripts/sync-feature-state.sh --approve release docs/agents-v0/requirements/x.md` exits 1 with `FAIL: --approve release runs only on the integration branch main (current: feature/x).`; after a commit on `feature/x` that is not on `main`, `sh .agents-v0/scripts/check-release-evidence.sh docs/agents-v0/requirements/x.md` exits 1 with `... feature/x is not fully merged into main ...`; `sh scripts/validate-kit.sh` prints `validate-kit: OK`.
Not in this fix: the skeleton archive `templates/app/p0-platform-skeleton.tar.gz` still holds 57 macOS `._*` entries (P0-A finding, §5.6). A validate-kit check that rejects them would fail until the archive is repacked, so it is not added here; repack first (for example `COPYFILE_DISABLE=1` in `scripts/pack-app-template.sh`, or packing on Linux), then add the check.

## kitfix-20261031-branch-guard

Found by e2e run 20261029-1629 (P2-A run 3, 2026-10-30 01:01 Asia/Manila): one truncated Intake turn ended right after `--approve intake`, before the branch question and `feature-worktree.sh`. Design, build, verify and release were then recorded and committed on `main`. The "no worktree, stop" rule was prose in `v0-design` and `v0-build` only.
- `templates/.agents-v0/scripts/sync-feature-state.sh`: for a feature story (`docs/agents-v0/requirements/<feature>.md`, not P0-A) inside a git work tree, refuses `--active-phase design|build|verify|release` (any status except `blocked`), `--approve design|build|verify` and `--verify-passed` unless the current branch is `feature/<feature>`. P0-A must be on the integration branch. Recording `blocked` is allowed anywhere. Maintenance notes are not checked. `AGENTS_V0_SKIP_BRANCH_GUARD=1` skips the check for kit fixtures only. `--approve intake` prints `Next: ask the user to authorise branch feature/<feature>, and stop.`
- `core/common/commands/v0-intake.md` step 7: branch authorisation is its own turn after the Intake approval.
- `core/common/commands/v0-verify.md`, `core/common/commands/v0-local-release.md`: stop when no `feature/<feature>` exists (the missing half of the rule).
- `scripts/test-command-flows.sh`: 20 `branch guard:` cases. `scripts/validate-kit.sh`: greps for the guard and the command text.
How to check: `sh scripts/test-command-flows.sh` prints `ok: branch guard: --active-phase design in_progress is refused on main` and `test-command-flows: OK`; in a repo on `main`, `sh .agents-v0/scripts/sync-feature-state.sh --active-phase design --status in_progress docs/agents-v0/requirements/x.md` exits 1 with `FAIL: design for x runs only on feature/x (current: main).`
Not in this fix: maintenance-note branches (`maintain/<id>` for standard and emergency tiers); a separate `branch` gate in state (plan option B).

## kitfix-20261031-single-clock

Found by e2e run 20261029-1629 (P2-A run 4, 2026-10-30 02:11 Asia/Manila, H3 FAIL: phaseDates not non-decreasing). The script dated approvals with one clock (UTC, then local in `fc4b642`) and the agent typed table dates with another (`date -u`, or local). A table date also overwrote the script's date on every sync. The harness then ran the agent with `TZ=UTC`, which hid the problem instead of fixing it.
- `templates/.agents-v0/scripts/sync-feature-state.sh`: one clock (`kit_now`) in the project time zone: `AGENTS_V0_TZ`, else the `Timezone` row of `docs/agents-v0/project-profile.md`, else the system zone. It dates `phaseDates`, the new `phaseTimes` (ISO time with offset), `updatedAt` (now with its offset instead of `Z`) and the Date cell of the approved `Delivery approvals` row, which `--approve` now writes itself. A recorded approval date is never moved by a table cell; a mismatch prints `WARN: Delivery approvals date for <phase> (...) differs`. `AGENTS_V0_NOW` pins the clock for tests.
- `core/common/rules/workflow-orchestration.mdc`: the one-clock rule and the `phaseTimes` field. `core/common/commands/v0-intake.md`: Date `-`. `templates/docs/agents-v0/project-profile.md`: `Timezone` row. `templates/docs/agents-v0/requirements/_state.template.json`: `phaseTimes`.
- `scripts/test-clock.sh` (new, run by `validate-kit.sh`): approval at 00:30 Asia/Manila (16:30 UTC the day before) with the process in UTC, a `date -u` table cell, approvals across midnight, the profile row, the system zone, and an old state file.
How to check: `sh scripts/test-clock.sh` prints `ok: midnight Asia/Manila: phaseDates.intake is the Manila date` and `test-clock: OK`.
Not in this fix: the harness default `AGENT_TZ=UTC` is changed in the e2e harness commit (agents now run in Asia/Manila, as the real user does).

## kitfix-20261031-skeleton

Old P0-A finding (`fix-and-resume.md` §5.6), still open after run 20261029-1629: `templates/app/p0-platform-skeleton.tar.gz` held 57 macOS AppleDouble `._*` entries out of 114 (plus `LIBARCHIVE.xattr.com.apple.provenance` headers). They broke Checkstyle and Vitest on Linux.
- `scripts/pack-app-template.sh`: copies with `tar` (rsync is not always installed) and excludes `._*`, sets `COPYFILE_DISABLE=1`, packs without xattrs/ACLs, refuses a staged `._*` file. The archive is repacked: 57 entries, the same content as `templates/app/{backend,frontend,docker-compose.yml}`.
- `scripts/validate-kit.sh`: fails when the archive lists any `._*` entry and when the packer does not exclude them. `scripts/test-app-template.sh`: fails on an extracted `._*` file.
- Design evidence (P1-C, §5.6): `sync-feature-state.sh --approve design` refuses a feature story (not P0-A) without a non-empty `docs/agents-v0/design/<feature>/design.md`; `v0-design.md` says the agent writes it. Run 20261029-1629 did not show the harness writing design evidence: the P1-C and P1-E SEMI-SYNTHETIC labels in their `design-1` runs are build-gate commits after the No-contract shortcut.
How to check: `tar tzf templates/app/p0-platform-skeleton.tar.gz | grep -c '\._'` prints `0`; `sh scripts/test-command-flows.sh` prints `ok: design evidence: --approve design is refused without design/orders/design.md (kitfix-20261031-skeleton)`; `sh scripts/validate-kit.sh` prints `validate-kit: OK`.

## kitfix-20261031-tests-ran

Old P1-B finding (`fix-and-resume.md` §5.6), still open after run 20261029-1629: the PostgreSQL integration tests were named `*IT.java`, the pom had no Failsafe, and Maven skipped them without a word. Nothing checked that tests exist but none ran.
- `templates/app/backend/pom.xml` (skeleton; archive repacked) and `core/java/starters/maven/quality-plugins.xml`: `maven-failsafe-plugin`, so `*IT.java` runs in `mvnw verify` (decision D9).
- `templates/.agents-v0/scripts/check-tests-ran.sh` (new, seeded by `install.sh`): reads `target/surefire-reports` and `target/failsafe-reports`; exit 1 when test classes exist but no non-skipped test ran, or when an `*IT.java` class has no report. `v0-build` step 6 and `v0-verify` step 1 run it after the native Maven verify.
- `scripts/test-tests-ran.sh` (new, run by `validate-kit.sh`): synthetic reports for all-ran, IT skipped, none ran, all skipped, no tests, no Maven.
- Checked by hand on 2026-10-31 03:18 Asia/Manila with JDK 21: the repacked skeleton plus a `SmokeIT` ran 10 Surefire + 1 Failsafe tests under `mvnw verify` and the check printed OK; with the old pom the same tree ran 10 tests, skipped `SmokeIT`, and the check failed naming `com.example.app.SmokeIT`.
How to check: `sh scripts/test-tests-ran.sh` prints `ok: an *IT class with no report fails (P1-B: no Failsafe)` and `test-tests-ran: OK`.
Not in this fix: a Vitest/Jest equivalent for the frontend (no standard report file to read).

## kitfix-20261031-gate-commit

Asked by Marlon (2026-10-31 03:05 Asia/Manila; replaces D10): commit on every approved gate. Found by e2e run 20261029-1629: the harness's "commit pending files" fallback (SEMI-SYNTHETIC) made most build gates, P1-C and P1-E design evidence included, and a failed phase could only be rolled back to the previous story's END snapshot, losing the story's earlier approved phases.
- New `templates/.agents-v0/scripts/check-gate-commit.sh` (seeded by `scripts/install.sh`):
  - default mode, run by `sync-feature-state.sh --active-phase X --status in_progress` when no phase is in flight: exit 1 when the last approved phase is not committed (state file untracked or its approval not in HEAD, or uncommitted changes; `*.lock` and `AGENTS_V0_COMMIT_CHECK_IGNORE` prefixes ignored). It names secret-looking paths (`.env`, keys) as never-to-commit and prints the gate commit.
  - `--release`, run by `--approve release` for a non-P0-A feature story: the branch's committed state has Verify approved, `verifyPassed: true` and release awaiting approval, its worktree is clean, and the index holds the branch tip (after `git merge --squash`).
  - `--message <phase>`: prints `git add -A && git commit -m "<story>: <phase> approved"` (story id from `Story:` or the milestone row); program and onboarding phases add `git tag -a <phase>-v<n>`; a feature release writes the squash message with trailers `Story-Branch: feature/<feature>` and `Story-Tip: <sha>` to the git dir and prints `git commit -F <file>`.
  - `AGENTS_V0_SKIP_COMMIT_CHECK=1` skips it (fixtures only).
- `sync-feature-state.sh`: runs the checks above and prints the gate commit after every `--approve` (Intake: "in the branch turn, in the new worktree").
- `check-release-evidence.sh`: a squash release counts as merged when the integration branch has a `Story-Branch` commit whose `Story-Tip` is still the branch tip and that holds the branch's files outside `docs/agents-v0/`; commits after the squash fail as before.
- `feature-worktree.sh`: refuses to check out a squash-released branch.
- `core/common/hooks/hook-policy.py`: `git commit --amend` always asks ("gate commits are never amended").
- Commands: v0-intake (intake commit in the branch turn), v0-design, v0-build, v0-verify (commit the gate on `feature/<feature>`), v0-local-release (release commit on the branch, then `git merge --squash`, one squash commit), v0-roadmap, v0-architecture, v0-plan, v0-onboard (one commit each on the integration branch, tag `<phase>-v<n>`, a revision bumps the tag). Also `local-release` skill, `release-manager`, `workflow-orchestration.mdc`, `agents-v0-kit.md`, `AGENTS.md`.
- Tests: new `scripts/test-gate-commit.sh` (project phases with tags, intake in the branch turn, design/build/verify gates, release refusals, squash commit with trailers, check-release-evidence on a squash and on a moved branch, feature-worktree refusal, secrets, skip flag); `scripts/test-command-flows.sh` (refusal before the intake commit); `scripts/test-hooks.sh` (`--amend`, `-F`, `merge --squash` ask).
How to check: `sh scripts/test-gate-commit.sh` prints `test-gate-commit: OK`; `sh scripts/validate-kit.sh` runs it.
Not in this fix: maintenance-branch releases (`maintain/<id>`) and remote `/v0-release` (MR) are unchanged.

## kitfix-20261031-traceability

Asked by Marlon (2026-10-31 03:12 Asia/Manila, part of fix 5): cheap, deterministic gate-to-gate consistency checks at each approval. Found by e2e run 20261029-1629: P2-F and P2-P wrote 7 ACs where the plan said 8, and nothing tied ACs to the design, the contract to code and tests, or ACs to passing tests.
- New `templates/.agents-v0/scripts/check-traceability.sh <design|build|verify> <requirements>` (seeded by `scripts/install.sh`), run by `sync-feature-state.sh --approve design|build|verify`:
  - T1 every `### AC-<n>` in design.md (blames design); T2 AC count vs milestone `Size` (blames intake; a `## Proposed split` or `Plan deviation:` line excuses it; this is the H6 check); T3 no unknown AC ids in design.md (design);
  - T4 every `operationId` / path of the design `openapi.yaml` has code under `app/`; T5 and a test that names it or calls the path (both blame build);
  - T6 every AC has a passing row in `quality-gate.md`; blame = design (not traced), build (no test names it) or verify.
  - Output `TRACE <WARN|FAIL> <check> gate=<gate> earliest_bad_phase=<phase> artifact=<file>: <detail>`, saved in `docs/agents-v0/requirements/<feature>.trace.json` (committed with the gate; the e2e harness reads it to pick the rollback gate).
  - D8: `AGENTS_V0_TRACE_MODE=warn` by default (exit 0); `fail` refuses the approval.
  - `AGENTS_V0_TRACE_NO_WRITE=1` prints only (added with the harness rollback commit: the e2e harness re-runs the failed phase's checks to choose the rollback gate).
- Commands v0-design, v0-build, v0-verify: report every `TRACE WARN` line at the gate.
- Tests: `scripts/test-gate-commit.sh` (T1–T6, warn and fail modes, trace.json earliest bad phase).
How to check: `sh scripts/test-gate-commit.sh` prints `ok: T2: 2 ACs vs plan Size 3, blamed on intake` and `test-gate-commit: OK`.
Not in this fix: event contracts (`asyncapi.yaml`) and UX specs are not traced; switch to `AGENTS_V0_TRACE_MODE=fail` after the V3 rerun (D8).

## kitfix-20261031-no-amend

Approved by Marlon (2026-10-31 04:05 Asia/Manila), follow-up to kitfix-20261031-gate-commit: the unattended allowlist `Shell(git:commit*)` matched `git commit --amend` too, so an unattended agent could rewrite a gate commit.
- `core/common/hooks/lib.sh` `hook_shell_permission_ask`: in unattended mode (`AGY_ALLOW_TOOLS` or `.agents/hooks/unattended-allow`) a git commit command with `--amend`, or an abbreviation git accepts (`--am`, `--ame`, `--amen`), is denied before the allowlist is matched, also after `&&`, inside `sh -c "…"`, and with `-C`/`-c` options first. Message: "gate commits are never amended (make a new commit)".
- `core/common/hooks/hook-policy.py`: the abbreviations ask like `--amend`, and never count as an evidence-only commit.
- Tests: `scripts/test-hooks.sh` (allowlisted new commits allowed; ten `--amend` forms blocked for Cursor and Antigravity, also through the `unattended-allow` file; attended mode still asks); `scripts/test-hook-policy.py` (two cases, 272 total).
How to check: `sh scripts/test-hooks.sh` prints `test-hooks: OK`.
