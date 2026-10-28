# Harness fixes — 2026-10-28

Two bugs in the e2e test harness (`refs/e2e-test-plan/scripts`). Neither changes the kit itself.
Both were found while running the plan with the Cursor CLI driver on Linux.

## HF-01 — `AGENT_DRIVER=auto` picked different agents in step 1 and in the run

**Defect.** `prereqs.sh` and `lib.sh` each had their own auto rule:
- `prereqs.sh` chose Antigravity whenever `AGENT_TURN_CMD` or `agy` existed. `env.sh` always sets
  `AGENT_TURN_CMD`, so step 1 always checked Antigravity.
- `lib.sh` (`resolve_driver`) chose Cursor whenever the Cursor CLI (`agent`) was installed.

**Evidence.** On a machine with both `agy` and `agent` installed, `prereqs.sh --check` printed
`agent-cli PRESENT antigravity custom driver (...)`, while the run's turns were driven by Cursor.
Step 1 could pass while checking the wrong agent's sign-in and model.

**Fix.** `resolve_driver` now lives in `env.sh`, which both scripts source, and `prereqs.sh` calls it.
`lib.sh` no longer defines its own copy. The rule is unchanged from what the run used:
an explicit `AGENT_DRIVER` wins; otherwise Cursor if its CLI is installed; otherwise Antigravity.
To use Antigravity on a machine that also has the Cursor CLI, set `AGENT_DRIVER=antigravity`.
`prereqs.sh` also prints a new line, `PREREQ agent-driver PRESENT <driver>`, so the choice is in the log.

**How to check.** With both CLIs installed and `AGENT_DRIVER` unset:
`bash scripts/prereqs.sh --check | grep agent-` shows `agent-driver PRESENT cursor` and the Cursor CLI,
and `bash -c '. scripts/env.sh; . scripts/lib.sh; resolve_driver'` prints `cursor`.
With `AGENT_DRIVER=antigravity` both report Antigravity.

## HF-02 — step 1 calibration failed for a kit branch that is not the default branch

**Defect.** `run-plan.sh` step 1 cloned the kit and ran `git checkout --detach "$KIT_REF"`.
A fresh clone only has the default branch locally; other branches exist only as `origin/<name>`,
so `checkout --detach kitfix-20261022` failed and step 1 stopped.

**Evidence.** A run with `KIT_URL=https://github.com/mdurana/agents-v0-kit.git KIT_REF=kitfix-20261022`
stopped in step 1. Reproduced with a plain clone: `tech-stacks-v4` and `kitfix-20261022` fail;
commit ids and `HEAD` work.

**Fix.** Step 1 now fetches `KIT_REF` from the clone's origin and checks out `FETCH_HEAD`, the same way
`kit_checkout` already does for step 2, and falls back to the plain ref for commit ids or tags.

**How to check.** For `KIT_REF` set to `kitfix-20261022`, `tech-stacks-v4`, a commit id and `HEAD`,
`git clone -q "$KIT_URL" d && { git -C d fetch -q origin "$KIT_REF" && git -C d checkout -q --detach FETCH_HEAD; } || git -C d checkout -q --detach "$KIT_REF"`
succeeds and `git -C d rev-parse HEAD` is the expected commit. A branch that does not exist still fails.
