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

## kitfix-20261031-guard-override

Found by the second review of `dd980e6` (2026-10-31, approved by Marlon 04:43 Asia/Manila): the kit scripts read `AGENTS_V0_SKIP_BRANCH_GUARD`, `AGENTS_V0_SKIP_COMMIT_CHECK`, `AGENTS_V0_NOW`, `AGENTS_V0_TRACE_MODE` (and `AGENTS_V0_TZ`, `AGENTS_V0_COMMIT_CHECK_IGNORE`, `AGENTS_V0_TRACE_NO_WRITE`) from the environment, and nothing stopped an agent from setting them (`AGENTS_V0_SKIP_BRANCH_GUARD=1 sh .agents-v0/scripts/sync-feature-state.sh ...` was allowed). The unattended allowlist matched only a compound command's first program, so `git commit -m x && git reset --soft HEAD~1` passed `Shell(git:commit*)`, while the kit's own printed gate command `git add -A && git commit ...` was denied.
- `core/common/hooks/hook-policy.py` (`GUARD_OVERRIDE_RE`, checked first on the whole command, so also inside `sh -c`/`bash -c`, after `&&`/`;`/`|` and in `$(...)`): an agent command that sets, exports or unsets an `AGENTS_V0_*` variable is **blocked** in attended and unattended mode (prefix assignment, `env NAME=`, `export`/`declare -x`/`typeset`/`readonly`/`local`/`unset`, `${NAME:=...}`, `os.environ[...]`/`putenv`). Reading one (`$AGENTS_V0_TZ`, `${AGENTS_V0_TZ:-}`, `grep AGENTS_V0_TZ`) is allowed. The variables stay for kit fixtures and the person's own shell.
- `hook-policy.py`: `git tag -f/--force` is blocked (phase tags are never moved); `git reset` to another commit (`--soft`, `--mixed`, `--keep`, `--merge`, or a revision such as `HEAD~1` or a SHA) and `git update-ref`/`filter-branch`/`replace` ask; unstaging (`git reset`, `git reset [HEAD] -- <path>`) stays allowed. `--no-verify` and `push --force` were already blocked.
- `core/common/hooks/lib.sh` `hook_shell_permission_ask` (unattended mode): every segment of a compound command is judged by `hook-policy.py`; each ask-level segment must match the allowlist, allow-level segments (`git add`, `cd`) pass, a block-level one denies, and an ask that comes only from a whole-command rule (a download piped into an interpreter) is denied. `hook-policy.py` is loaded without writing `__pycache__`; if it cannot be loaded the command is denied (fail closed).
- `templates/docs/agents-v0/agents-v0-kit.md` Safety Hooks.
- Tests: `scripts/test-hook-policy.py` (301 cases: the assignment forms, reads allowed, tag -f, reset, update-ref, story-branch deletion); `scripts/test-hooks.sh` (the printed gate commands allowed unattended, chained rewrites denied, AGENTS_V0_* blocked in both modes even with a broad allowlist). Mutation check: the new cases run against the `dd980e6` hooks give 85 `FAIL` lines in `test-hooks.sh` and a failing `test-hook-policy.py`.
- Harness side (same commit): H8 (no guard override) and H9 (gate commits intact and in order), see `refs/e2e-test-plan/HARNESS-FIXES-20261029.md`.
How to check: `sh scripts/test-hooks.sh` prints `test-hooks: OK`; `HOOK_CMD='AGENTS_V0_SKIP_BRANCH_GUARD=1 sh .agents-v0/scripts/sync-feature-state.sh --approve build r.md' python3 core/common/hooks/hook-policy.py shell` prints `"action": "block"`.
Not in this fix: a harness-only marker for the skip flags. Any marker the scripts can read (a variable or a file) is also within the agent's reach, so it would add no protection beyond the hook block, the protected `.agents-v0/scripts/*` path (agents cannot edit the scripts) and the harness's H8 scan. A file written by the agent and then sourced is not blocked by the hooks; H8 catches it after the turn. Printing a secret scan before the printed commit command (second review, item 6) is a follow-up.

## kitfix-20261031-keep-branches

Asked by Marlon (2026-10-31 04:47 Asia/Manila): story branches are kept after release, for reference and backtracking. No kit script, harness script or command doc deleted a story branch (checked: no `git branch -d/-D`, `git push --delete` or `:refs/heads/` step); this makes the rule explicit and enforced.
- `core/common/hooks/hook-policy.py`: `git branch -d/-D/--delete/-m/-M` of a `feature/*` or `maintain/*` branch and `git push --delete` / `git push <remote> :<story branch>` are blocked for the agent (attended and unattended). Other branches still ask.
- `core/common/commands/v0-local-release.md`, `core/common/skills/local-release/SKILL.md`: keep `feature/<feature>` / `maintain/<id>` after the release; `git worktree remove <path>` removes only the folder. `templates/.agents-v0/scripts/feature-worktree.sh`: the same note.
- `templates/.agents-v0/scripts/check-release-evidence.sh`: when the released story's `feature/<feature>` is missing it prints `WARN: feature/<feature> not found: the squash/merge cross-check was skipped ...` (exit code unchanged, so projects that deleted branches before this rule still pass).
- Tests: `scripts/test-hook-policy.py`, `scripts/test-hooks.sh`, `scripts/test-gate-commit.sh` (the WARN on a deleted branch).
How to check: `HOOK_CMD='git branch -D feature/orders' python3 core/common/hooks/hook-policy.py shell` prints `"action": "block"`.


The live check of these fixes (V3: P1-E, P2-A, P2-F, P2-P with the fail modes on; keep-branches included) is described in `refs/e2e-test-plan/v3-rerun-procedure.md`.

## kitfix-20261031-installed-no-overrides

Found by an external review (approved by Marlon, 2026-10-31 09:49 Asia/Manila). `kitfix-20261031-guard-override` blocks agent commands that *name* an `AGENTS_V0_*` variable, but the hook and the harness H8 both match text. A split name (`V=AGENTS_V0_SKIP_BRANCH; env "${V}_GUARD=1" sh .agents-v0/scripts/sync-feature-state.sh ...`) or an env file decoded from base64 and loaded with `set -a; . ./x.env` got past both, and the installed scripts honoured the variable. The fix removes the override code from installed copies, so there is nothing left to switch:
- `templates/.agents-v0/scripts/sync-feature-state.sh`, `check-gate-commit.sh` and `check-traceability.sh`: every env override sits in a `# >>> kit-test-override` … `# <<< kit-test-override` block, with the safe value set before the block. The blocks cover `AGENTS_V0_SKIP_BRANCH_GUARD`, `AGENTS_V0_SKIP_COMMIT_CHECK`, `AGENTS_V0_COMMIT_CHECK_IGNORE`, `AGENTS_V0_NOW`, `AGENTS_V0_TZ`, `AGENTS_V0_TRACE_MODE` and `AGENTS_V0_TRACE_NO_WRITE`.
- `scripts/install.sh` (first install and `--update`) runs each installed `.agents-v0/scripts` file through the new `scripts/strip-test-overrides.sh`, which drops those blocks. It fails on unbalanced markers. `--test-overrides` keeps them, for the kit's own suites only (`test-gate-commit.sh` and `test-command-flows.sh` install that way; `test-clock.sh` copies the templates).
- **Trace mode:** an installed `check-traceability.sh` reads its mode only from `.agents-v0/policy.conf` (`trace_mode=warn|fail`; an unknown value counts as `fail`; a missing file means the default `warn`). The team or the e2e harness writes that file (harness: `KIT_TRACE_MODE`). `--print-mode` prints the mode in force, and `--no-write` replaces `AGENTS_V0_TRACE_NO_WRITE`.
- An installed `sync-feature-state.sh` refuses to record a phase when `check-gate-commit.sh` or `check-traceability.sh` is missing, because moving a gate script away must not switch its check off.
- `scripts/check-installed-kit.sh [--expect-trace-mode warn|fail] <project>` checks an install read-only. Each installed script must equal the stripped kit file, and each hook must equal `core/common/hooks`. It also checks that no installed script still reads `AGENTS_V0_*` and, optionally, the trace mode. It prints `HASH-OK` / `HASH-FAIL` and flags a test-override install as `TEST-OVERRIDES-INSTALLED`.
- `core/common/hooks/hook-policy.py`: `.agents-v0/policy.conf` is a protected path (edit and shell writes blocked), and `--test-overrides` or `strip-test-overrides.sh` in an agent command is blocked. Both are text checks, so they are only a speed bump; see the limits below.
- Docs: `v0-design.md` (`trace_mode=fail` in `policy.conf`), `workflow-orchestration.mdc` (time zone from the profile only) and `agents-v0-kit.md` Safety Hooks.
- Tests: new `scripts/test-installed-overrides.sh` (31 checks, run by validate-kit). On an installed copy, the split-name and base64/`set -a` forms leave every guard working:
  - the branch guard still refuses design on main;
  - the gate-commit check still refuses;
  - the clock is not pinned;
  - `trace_mode=fail` still refuses with the env saying `warn`.

  The same probes on a `--test-overrides` copy do take effect, which shows the probes are live. Also covered: `--update` strips an old copy, a missing gate script is refused, and `check-installed-kit.sh` reports DIFF, MISSING and TRACE-MODE problems. `test-hook-policy.py` now has 312 cases.
- Mutation checks:
  - with stripping disabled in `install.sh`, 15 checks fail;
  - with the missing-script refusal disabled, 1 check fails.
- Harness side (same commit): H10 and `KIT_TRACE_MODE` / `REQUIRE_FAIL_MODES`, see `refs/e2e-test-plan/HARNESS-FIXES-20261029.md`. H8 stays, as a speed bump.

How to check: `sh scripts/check-installed-kit.sh --expect-trace-mode fail <project>` prints `HASH-OK … trace_mode=fail`; `sh scripts/test-installed-overrides.sh` prints `test-installed-overrides: OK`.

Limits (not fixed here):
- **Same OS user.** The agent runs as the same OS user that owns the files, so nothing at the file level stops a determined agent from rewriting an installed script, `policy.conf` or the harness itself. The hooks match text, so they are a speed bump. H10 catches a change that is still there at the end of a turn. An edit made and undone inside one turn is not seen, but a gate approved in that window still shows its mode in `trace.json`, which H10 checks. A real fence needs the agent to run as a separate OS user with the kit files read-only, or in a sandbox.
- **Linked projects.** `install.sh --link` / `scripts/link-project.sh` symlink `.agents-v0/scripts` to the kit templates, so a linked project keeps the overrides. Use a normal install for anything an agent runs unattended.
- **Kit fetch switch.** `AGENTS_V0_FETCH_KIT` (`resolve-kit-root.sh`) is kept: it chooses where the kit is fetched from and switches no check off.
