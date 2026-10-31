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

## kitfix-20261031-kit-source-exec and kitfix-20261031-kit-paths

Found by the next external review (approved by Marlon, 2026-10-31 10:35 Asia/Manila). Two gaps were left after `kitfix-20261031-installed-no-overrides`:

**Item 1: unstripped copies could still be run.** The hook allowed `sh /home/e2e/kit-src/templates/.agents-v0/scripts/sync-feature-state.sh …`. That copy (and another project's, another worktree's, or an old install's) keeps the test-override blocks, so a split-name override aimed at it skipped the branch guard.
- `core/common/hooks/hook-policy.py`, **unattended mode only** (`AGY_ALLOW_TOOLS`, or `.agents/hooks/unattended-allow` next to the hook, in the payload cwd or the process cwd, as `lib.sh` decides). A command may run only the kit scripts of the checkout it works in.
  - **Which checkout:** the payload cwd's checkout, or a `cd` target in the same repository, such as the integration checkout at local release.
  - **What counts as a kit script:** a path in `.agents-v0/scripts|hooks`, or a file named like one that mentions agents-v0. The path is resolved, with symlinks followed.
  - **Where it is judged:** per segment, after `sh -c`, `env`, `xargs`, `timeout`, `nohup`, `exec`, `eval` and `$(…)` are unwrapped. Also covered: `<` redirects, `<(…)`, pipes into `sh`/`sh -s`/`python -`, and paths inside interpreter `-c` bodies.
  - **What is blocked:** running, sourcing, copying, linking, `rsync`/`install`/`tar` or `git clone` of a copy outside that checkout. So is a folder holding one, if it is not a checkout of the same repository. So is a `<rev>:<path>` blob of a kit script, and a variable or unresolved path that names one.
  - **What stays allowed:** reading a copy (`cat`, `grep`, `diff`, `ls`, `git show`), unless the command redirects the output or pipes into a shell.
  - **Linked installs:** a linked `.agents-v0/scripts` (`install.sh --link`) counts as the kit source, so it is blocked too.
  - **Attended mode is unchanged.** The existing protected-path rule already blocked `cp` of a `*/.agents-v0/scripts/*.sh` file in every mode.
- **Harness (the real fence):** see `refs/e2e-test-plan/HARNESS-FIXES-20261029.md` (2026-10-31 10:35) and `v3-rerun-procedure.md` §4 steps 6–8 (install first, then lock).
  - The kit source is moved where the agent user cannot read it.
  - With `REQUIRE_FAIL_MODES=1`, the preflight refuses to start while the agent user can read or enter a kit source path, or while any readable `*.sh` under `$HOME`, `$TEST_ROOT` or `/tmp` still holds a test-override block.
  - Main is then checked against a manifest written after `HASH-OK`, before the lock (`scripts/kit-manifest.sh`, `kit_installed_ok`), so the run needs no kit source.

**Item 2: the guard folders themselves could be moved or removed.** The per-file patterns missed:
- `mv .agents-v0/scripts /tmp/x`;
- `git rm .agents-v0/policy.conf`;
- `git mv`;
- a glob, a folder argument, or a relative path after `cd .agents-v0`.

`hook-policy.py`, all modes (agents only; a person's own terminal is not hooked): `mv`, `rm`, `rmdir`, `unlink`, `shred`, `truncate`, `chmod`/`chown`/`chgrp`/`chattr`/`setfacl`, and `cp`/`ln`/`install`/`rsync`/`link` onto a target are blocked. So are `find … -delete/-exec`, `git rm`, `git mv`, and `git checkout`/`git restore` (not `--staged` only) of an older version. This covers `.agents-v0/scripts`, `.agents-v0/hooks`, `.agents-v0/ci`, `.agents-v0/packs`, `.agents-v0/policy.conf`, `.agents/{hooks,rules,agents,commands,skills}`, `.agents/hooks.json`, `.cursor/{hooks,rules,agents,commands,skills}`, `.cursor/hooks.json`, `.cursor/cli.json`, and the parents `.agents-v0`, `.agents` and `.cursor`. Paths are matched by name and glob, and also resolved against the command's directory. H10 stays the backstop.

- **Tests:**
  - `scripts/test-hook-policy.py`: 417 cases, up from 312;
    - 40 item-2 shell cases: blocked and allowed;
    - 63 kit-source cases in scratch repositories: the kit source by 11 run forms, xargs, `bash -c`, a stdin redirect, `cat | sh`, process substitution, python subprocess, cd into kit-src, a variable path, a sibling worktree (absolute and relative), another project (path and cd), a symlink in the project, a symlink outside, and a linked install; copy, rsync, install, clone, tar and git-blob forms; allowed own-script, worktree, release-`cd`, reading and app-script cases; attended-mode cases; resolved-path item-2 cases;
    - 2 cases through the `unattended-allow` file;
  - `scripts/test-hooks.sh`: the same probes end to end through `pre-shell.sh` (Cursor and Antigravity payloads, sh and dash);
  - `refs/e2e-test-plan/tests/test-guards.sh`: 54 cases, up from 42.
- **Mutation checks:**

  | Mutation | test-hook-policy | test-hooks |
  |---|---|---|
  | unattended rule off | 36 FAIL | 60 FAIL lines (its embedded test-hook-policy run included) |
  | folder rule off | 30 FAIL | 60 FAIL lines |

  In the harness: with `kit_source_locked` always passing, test-guards fails 3. With the manifest comparison off, it fails 1.

Limits:
- **Speed bump only.** Both hook rules match command text. An encoded command (`echo <base64> | base64 -d | sh` whose output names a kit path) or a copy made earlier under a neutral name, holding no `agents-v0` text, is not recognised.
- **The fence is the OS user.** On the V3 VM, the agent user cannot read any kit source (preflight-checked).
- **Git history.** The project's own git history still holds kit scripts installed before `kitfix-20261031-installed-no-overrides`. The hook blocks the `<rev>:<path>` forms, but a raw blob id (`git cat-file -p <sha>`) is not recognised.
- **Outcome checks.** The harness outcome checks still catch the effects: H1 for the branch guard, H3 for phase times, H10 for `trace.json` mode and kit tampering.
- **Snapshot archives.** Old snapshot archives are made root-only by the procedure, not by the harness. The marker scan reads plain files only.

## kitfix-20261031-kit-git-source

Found by the next external review (approved by Marlon, 2026-10-31 11:25 Asia/Manila). The V3 procedure delivered the kit to the VM as a git bundle in `/tmp` (mode 644), and the lock step left it there. A bundle, clone or mirror of the kit holds the unstripped scripts in its git objects, where the `*.sh` scan cannot see them. In unattended mode the hook still allowed `git clone`, `git fetch` and `git bundle unbundle` against it, so the agent could get an unstripped copy back.

- `core/common/hooks/hook-policy.py`, **unattended mode only** (attended mode is unchanged). Git works on this project's own repository and its configured remotes only:
  - **Blocked outright:** `git clone`, `git bundle` (any subcommand: `unbundle`, `verify`, `list-heads`, `create`), `git archive`, `git submodule add`, `git remote add` / `set-url`, a `git config` write of `remote.*.url` or `url.*.insteadOf`, and `-c remote.*.url=` / `-c url.*.insteadOf=` on the command line.
  - **`git fetch`, `pull` and `ls-remote`:** allowed with no source, or with a source that is a remote configured in the repository the command runs in. A local URL (path or `file://`) must not be a git bundle or a kit repository. Any other source (a path, a URL, a bundle) is blocked.
  - **Other repositories:** `git -C <dir>`, `--git-dir=`, `--work-tree=`, and `GIT_DIR`, `GIT_WORK_TREE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` or `GIT_COMMON_DIR` (as a prefix, `env`, `export` or `declare -x`) are blocked when they point at a git bundle (by name or by its `# v2/v3 git bundle` header), at a git repository outside this project that holds the kit, at a folder holding kit scripts, or at an unresolved variable. So `git -C ~/kit-src show …`, `git --git-dir=kit-mirror.git cat-file …` and `GIT_DIR=… git log` are blocked. Sibling worktrees of this project and unrelated repositories stay allowed.
  - **A kit repository** is one whose objects hold a known kit root commit (`KIT_ROOT_COMMITS`: `550da9df…` "agents-v0 version 0.0.1", `fc4b642c…`), or that has `templates/.agents-v0/scripts/sync-feature-state.sh` at HEAD, FETCH_HEAD or any of its first 500 branch or tag tips. One `git cat-file --batch-check` call per repository, cached.
  - **Copying a bundle** (`cp`, `rsync`, `install`, `tar`, …) counts as copying the kit source (the existing kit-source rule now treats a bundle file as one).
  - **Still allowed** (tested): `git status`, `log`, `diff`, `show` and `cat-file` on this repository's objects, `fetch`, `fetch origin`, `fetch --all --prune`, `pull --ff-only origin main`, `ls-remote origin`, `remote -v`, `config --get`, `worktree list`, `-C` on a sibling worktree or an unrelated repository; `git push` still asks.
- **Harness (the real fence):** `kit_source_locked` also refuses to start if the agent user can read any `*.bundle`, or any git repository or bare repository holding the kit, under `KIT_SCAN_ROOTS`. See `refs/e2e-test-plan/HARNESS-FIXES-20261029.md` (2026-10-31 11:25). The procedure now moves the delivery bundle to a root-only folder right after the fetch, and the lock moves it (and any other bundle under `/tmp` and `/home/e2e`) into `/root/kit-locked/<time>` (`v3-rerun-procedure.md` §2 and §4 step 8). Nothing is deleted.
- **Tests:**
  - `scripts/test-hook-policy.py`: 471 cases, up from 417. 30 block cases (clone of a bundle, mirror or URL; fetch and pull of a bundle, a renamed bundle, a mirror, a clone, a URL that is not a remote, a remote that points at a bundle; ls-remote of a bundle; bundle unbundle/verify/list-heads; remote add/set-url; config and `-c` remote URLs; `-C`/`--git-dir` show, log and cat-file on the kit source, a clone and a mirror; the `GIT_DIR` family as prefix, `env` and `export`; `git archive | tar`; `submodule add`; `cp` of a bundle; `bash -c` fetch). 17 allow cases for the project's own git and its origin (push asks). 3 more: `fetch origin` from a worktree, and attended clone/fetch of a bundle still allowed. 3 in-process cases for the root-commit test.
  - `scripts/test-hooks.sh`: 6 block and 5 allow probes end to end through `pre-shell.sh` against a real kit repository, a bundle and a bare origin (Cursor and Antigravity payloads, sh and dash), plus attended fetch of a bundle allowed.
- **Mutation checks:**

  | Mutation | test-hook-policy | test-hooks |
  |---|---|---|
  | `_segment_git_kit_source` off | 13 FAIL | 4 FAIL lines (`git -C <kit repo> show`; the bundle probes are still caught by the kit-source copy rule) |
  | `command_git_env_kit_source` off | 5 FAIL | — |

Limits:
- **Speed bump only.** The rules match command text. An encoded command, a git alias defined earlier, or a bundle renamed and stripped of its header (it is never stripped by git) can get past them. The fence is the OS user: the agent user cannot read any bundle or kit repository (preflight-checked).
- **Network remotes.** A remote already configured in the project is trusted; an `https` remote pointing at the public kit would be fetched. The V3 project's only remote is its own origin.
- **Unknown kit lineages.** A kit repository whose root is not in `KIT_ROOT_COMMITS` and whose tips do not hold `templates/` is not recognised.
- **Git history.** As before, the project's own history still holds kit scripts installed before `kitfix-20261031-installed-no-overrides`; a raw blob id is not recognised.

## kitfix-20261031-escalation

**Supervised vs unattended (Marlon 2026-10-31 13:25).** These rules govern **agent** commands, mainly in unattended runs such as the e2e test VM. They do not limit people: a developer using the kit in a supervised environment may use Docker, and sudo on their own machine, and the hooks never see a person's terminal. By mode, for agent commands:
- **Blocked in both modes:** `sudo`, `doas` and `run0` (in any spelling), and the Docker TCP API on `localhost:2375` / `127.0.0.1:2375`.
- **Allowed in both modes:** `docker`, `docker compose` and `podman`. The kit's local container run and Testcontainers use them.
- **Blocked unattended only:** `su` and `pkexec`. Attended, the hook allows them, and the operating system asks the person.
- **The e2e VM's own fence** is the OS: e2e has no Docker access and no escalation path. A root check verifies this before each launch (`refs/e2e-test-plan/v3-rerun-procedure.md` §4 step 9, kitfix-20261031-escalation-none).

Found by the Sonnet review of `af258c7` (finding 3; approved by Marlon, 2026-10-31 12:56 Asia/Manila). Verified first: at `af258c7`, unattended, `env sudo …`, `xargs sudo …`, `command sudo …`, `nohup sudo …`, `\sudo …` and `/usr/bin/sudo …` passed the hook (only a bare `sudo` or `doas` in command position was blocked), and `su -c id`, `su root` and `pkexec id` were allowed.

- `core/common/hooks/hook-policy.py`:
  - The existing wrapper unwrapping (`_expand_wrapper`) now records every escalator it sees in command position, after stripping a leading `\` and any path (`\sudo`, `/usr/bin/sudo`). It also unwraps `doas`, `setsid`, `ionice`, `run0` and `pkexec`, and skips `xargs` options and their arguments (`xargs -n1 sudo rm`).
  - **All modes:** `sudo`, `doas` and `run0` in any of those spellings are blocked (attended and unattended), as bare `sudo` was before.
  - **Unattended only:** `su` and `pkexec` are blocked in any spelling (`env su root`, `nohup pkexec id`). Attended, they are allowed as before. Neither the kit nor the harness needs them from the agent: the V3 procedure's `su - e2e` runs as root from `vm.py`, outside any agent turn.
  - Text that only mentions them is unchanged (`git commit -m 'sudo fix'` asks, as before).
- **Tests:** in `scripts/test-hook-policy.py` (now 542 cases, up from 471, shared with the harness lock below), 15 escalation spellings are each checked attended and unattended, plus attended cases that stay unchanged. `scripts/test-hooks.sh` adds end-to-end probes through `pre-shell.sh` (Cursor and Antigravity payloads, sh and dash): 7 `sudo`/`doas` spellings blocked in both modes, and `su`, `pkexec` and `env su root` blocked unattended and allowed attended.
- **Mutation check:** with the escalator recording off, test-hook-policy has 33 FAIL lines and test-hooks 40 failed probe lines.
- **Limits:** a speed bump, as before. An encoded command, a function or alias defined earlier, or a copy of the binary under another name can get past it. The fence is the OS: the agent user must have no sudo, doas or polkit rights on the VM. Since kitfix-20261031-escalation-none a root check records this before each V3 launch, and the preflight verifies it (`v3-rerun-procedure.md` §4 step 9).

## kitfix-20261031-harness-lock (hook part)

Found by the same review (finding 2c). The hook now protects the harness and its control files as a speed bump; the real fence is the harness lock in `refs/e2e-test-plan/HARNESS-FIXES-20261029.md` (2026-10-31 12:56).

- `core/common/hooks/hook-policy.py`, **unattended mode only** (attended is unchanged):
  - **Harness paths:** any `harness-v3` folder (`/opt/harness-v3`, `~/harness-v3`), `refs/e2e-test-plan/{scripts,fixtures,tests}`, `$PLAN_DIR`, the run root `agents-v0-e2e/run-*` (and `$TEST_ROOT`) outside its `work/` folder (so `status/pending-turn.json` and the other control files, `results/`, `evidence/`, `run-*/`), and the `agents-v0-e2e` folder itself. Paths are expanded (`$TEST_ROOT`, `~`) and resolved against the hook's working directory, so `../../status/pending-turn.json` and `cd ../.. && rm …` are caught.
  - **Blocked:** writes to those paths by the shell rules the kit-file protection already uses (redirects, `tee`, `sed -i`, `cp`/`mv`/`rm`/`install`/`ln`/`chmod`, `find -delete`/`-exec`, …), a `python`/`node` heredoc that writes one, and the edit tool on one (`classify_path`).
  - **Blocked:** setting or unsetting `AGY_ALLOW_TOOLS` or `CURSOR_CONFIG_DIR` (`export`, a prefix assignment, `env VAR=…`, `env -u`, `unset`).
  - **Still allowed:** reading those files, and anything under `$TEST_ROOT/work` (the project).
- **Tests:** in `scripts/test-hook-policy.py`, 25 unattended blocks, 7 unattended allows and 4 path cases; `scripts/test-hooks.sh` probes 4 harness and control-file writes (blocked), a read of the pending file and an attended write (allowed), and a `pre-edit.sh` edit of a harness script (blocked).
- **Mutation check:** with `_segment_changes_harness` and the path rule off, test-hook-policy has 14 FAIL lines and test-hooks 14 failed probe lines; with the `AGY_ALLOW_TOOLS`/`CURSOR_CONFIG_DIR` rule off, test-hook-policy has 5.
- **Limits:** text matching only (an encoded command or a script file written in `work/` and then run can get past it). The OS lock (root-owned `/opt/harness-v3`) is what keeps the harness code safe; the runtime state outside `work/` is protected only by this hook and by the H10 checks, because the runner runs as the same user as the agent.

## kitfix-20261031-escalation-none and kitfix-20261031-launch-env (harness only)

Reviews by Sai (should-fix: a root check that e2e has no escalation or Docker access) and Sakura (medium: e2e can write the launch env, the secrets file and its dotfiles, which a relaunch re-sources), approved by Marlon 2026-10-31 13:25 Asia/Manila. No kit code changed. The harness side is in `refs/e2e-test-plan/HARNESS-FIXES-20261029.md` (2026-10-31 13:25): `scripts/escalation-check.sh`, `scripts/home-hash.sh`, `v3_launch_ok` and `escalation_none_ok` in `lib.sh`, an isolated tmux server in `start-tmux.sh`, and the root-owned `/opt/harness-v3-env/` in `v3-rerun-procedure.md` §4 step 9, §5, §6 and §8.

## kitfix-20261031-ws-exec (hook part)

From Sasuke's round-2 review, approved by Marlon 2026-10-31 13:40 Asia/Manila. The harness side is in `refs/e2e-test-plan/HARNESS-FIXES-20261029.md` (2026-10-31 13:40): the state file read without `eval`, the root-owned `/opt/agents-v0-tools`, and the turn wrapper `agy-ws-exec.sh`, which now fails closed.

- `core/common/hooks/hook-policy.py`, **unattended mode only** (attended is unchanged). Blocked:
  - `env -i` (checked on the whole command, because segment splitting already unwraps `env`);
  - `typeset`, `declare`, `export`, `readonly` or `local` naming `AGY_ALLOW_TOOLS`, `CURSOR_CONFIG_DIR`, `AGY_TURN_WS` or `TEST_ROOT`;
  - `unset` with a `$` in the name;
  - an `agy-ws-exec.sh` call (`_segment_ws_exec`) whose `--ws` is not under `$TEST_ROOT/work` (or holds a `$`), or whose `--test-root` is not `TEST_ROOT`.

  An allowed wrapper call has its quoted command classified as if run directly, so an inner block blocks and an inner ask asks.
- **Tests:** `scripts/test-hook-policy.py` has 33 new cases (575 in all): 22 unattended blocks, including Sasuke's probe `bash …/agy-ws-exec.sh --test-root /x --ws /tmp 'sudo id'`, 8 unattended allows, and 3 attended cases that stay unchanged.
- **Mutation check:**

  | Rule off | test-hook-policy FAIL |
  |---|---|
  | `env -i` | 7 |
  | wrapper unwrap | 7 |
  | the new allow-variable rules | 5 |
- **Limits:** text matching only. An indirect `env -u "$X"` is not caught. The wrapper's own fail-closed checks and the root-owned harness and tools are the real fence.


## kitfix-20261031-n1 (REVIEW-NOTES: merge order with Y-1, Jiraiya JN-1)

- **Do not merge the N-1 and Y-1 tips side by side.** `git merge-tree` of N-1 (448ca86) and Y-1 (61deabe) is textually clean in either order, but the merged tree fails: every fresh install is `HASH-FAIL` with `EXTRA .cursor/hooks/hook-python` and `EXTRA .agents/hooks/hook-python` (Y-1's `scripts/check-installed-kit.sh` `extras()` does not know the N-1 pin), `test-install-integrity` exits 1, and `test-guards` gives 169 passed / 14 failed (modes_preflight, manifest, manifest drift, "clean main refused", kio). The first V3 preflight after such a merge would refuse every install. Source: `proposals/jiraiya-review-of-n1-20261031.md`, JN-1.
- **Order:** N-1 merges first. Y-1 is then rebased on it together with Sakura's M-2: `check-installed-kit.sh` adds `hook-python` to `expected` in both hook folders and validates it there (absolute, root-owned, not group/other-writable, the same value in both adapters). Y-1's hook-side bytecode change (Yamato's addendum, `KIT_PY`) builds on `hook_py` in `core/common/hooks/lib.sh`, which already runs `-I -S -B -X pycache_prefix=…` (JN-7); `KIT_PY` stays for `templates/.agents-v0/scripts` only.
- **After the rebase:** re-run all suites on the rebased Y-1 (at least test-install-integrity, test-guards, test-hooks, test-hook-policy) and re-read `scripts/install.sh`, `refs/e2e-test-plan/scripts/lib.sh`, `refs/e2e-test-plan/tests/test-guards.sh` and `refs/e2e-test-plan/v3-rerun-procedure.md` by hand; both branches touch them.
- **V3:** the home-hash record format changed with JN-3 (NUL-safe names, symlinks), so record it again (§4 step 9) after N-1 lands.
- Nothing in Y-1 is changed on this branch.

## kitfix-20261031-jn4 (Jiraiya JN-4 with M-1)

- **Claim wording:** N-1 (kitfix-20261031-n1) closes Python start-up injection. It does not by itself guard the agent user's other home files; this entry covers the shell and session start-up files.
- **Found by:** Jiraiya's N-1 review (`proposals/jiraiya-review-of-n1-20261031.md`, JN-4): a 10-line library in `LD_PRELOAD` turned pre-shell `sudo id` and pre-edit `.agents-v0/policy.conf` into allow, with or without the pin, and the writes that put the variable where the IDE or agy picks it up (`echo … >> ~/.profile`, `~/.config/environment.d/x.conf`, Edit of `~/.bashrc`) were allowed in both modes. M-1 (Sakura): a fake `cat` first on `PATH`, which an agent can put there through a PATH line in `~/.bashrc`, also turned both hooks into allow.
- **Fix:**
  - `core/common/hooks/hook-policy.py`: shell and session start-up files in the agent user's home (`~/.profile`, `~/.bash*`, `~/.zsh*`, `~/.zprofile`, `~/.zlogin`, `~/.zlogout`, `~/.pam_environment`, `~/.config/environment.d/*`, `~/.config/pip/*`, `~/.pip/*`, X session files, csh/tcsh files, `~/.ssh/environment`/`rc`, `~/.config/fish/*`, `~/.config/systemd/user/*`, `~/.config/plasma-workspace/env/*`, `~/Library/LaunchAgents/*`, `~/.MacOSX/environment.plist`) join N-1's start-up rule through the same predicate: a shell write asks in supervised mode and is blocked unattended, an edit-tool write is blocked in both modes (JN-6). A whole tree copied into `~/.config`, `~/.config/systemd`, `~/.ssh`, `~/.MacOSX` or `~/Library` counts too. `systemctl --user set-environment|import-environment`, `launchctl setenv|putenv|config user` and `dbus-update-activation-environment` ask or block the same way. A project's own `docker/.bashrc` is not a start-up file.
  - `core/common/hooks/pre-shell.sh`, `pre-edit.sh`, `session-start.sh`, `stop.sh`: `PATH=/usr/bin:/bin` before the first command (M-1).
  - `core/common/adapters/cursor/hooks.json`, `core/common/adapters/antigravity/hooks.json`: hooks start with `/bin/sh` (M-1).
  - `core/common/hooks/lib.sh` (JN-12, folded in): the hook-time pin check refuses an interpreter whose first two bytes are `#!` (a root-owned `#!/usr/bin/env python3` script such as `/usr/bin/routel` passed the owner check and ran the first `python3` on `PATH`), and `_hook_py_run` runs the interpreter with `PATH=/usr/bin:/bin`.
  - `core/common/hooks/lib.sh` (`hook_env_problem`): pre-shell and pre-edit deny while `LD_PRELOAD`, `LD_AUDIT` or `DYLD_INSERT_LIBRARIES` names a library that is not an absolute, root-owned file in a root-owned folder.
- **Tests:** `scripts/test-hook-policy.py` (`jn4_shell_startup_cases`) and `scripts/test-hooks.sh` (the JN-4 / M-1 block: Jiraiya's LD_PRELOAD repro, a PATH line in `~/.bashrc`, the fake `cat`, every write form in both modes, Edit and agy `write_file` payloads, the adapters' `/bin/sh`; JN-12: a `/usr/bin/routel` pin with a fake `python3` on `PATH`, and a mutant without the `#!` check or the hooks' PATH line).
- **Limits:** start-up files outside the agent user's home (`/etc/profile.d`, `/etc/environment`, a `ZDOTDIR` elsewhere; normally root-owned); an environment the IDE or agy gets from its own launcher, desktop entry or settings; `LD_LIBRARY_PATH`/`DYLD_LIBRARY_PATH` (not checked, developer setups use them); a preload library that unsets its own variable before the hook's first line; `PIP_CONFIG_FILE` pointing elsewhere; the text-matching limits of the write rule (indirection, globs and braces in the destination, `dd`/`sponge`/`tar -C`, symlink aliases: H-4, H-5, JN-13); the Python ≤3.7 and JN-9..JN-11 items stay open (JN-13..JN-15 are separate commits on this branch).
