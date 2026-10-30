# agents-v0 kit e2e results: Linode run 20261029-1629

**Outcome: PASS.** `RUN-END exit=0`. Step 4 (chain to the first frontend story) is **PASS-SEMI**. All **20 of 20** chain stories passed (P1-A to P1-E, P2-A to P2-I, P2-K to P2-O, and the frontend story P2-P). Checks: **145 PASS, 0 FAIL**. P2-P passed all 7 of its checks on resume attempt 10.

| | |
|---|---|
| Kit commit (final) | `fc4b642cb947` (`fc4b642cb947cf38b5fea7cc1005e22d58e17eef`, branch `e2eplan-20261029`) |
| Earlier kit commits in this run | `0aa3a431ce06` (steps 2-3, P1-A..P1-E), `cca27739dde4` (P2-A..P2-D) |
| Agent | Antigravity (`agy`), model `gemini-4-argon-medium`, ask mode `allowlist` |
| Started | 2026-10-29 16:29:39 Asia/Manila (UTC+8) |
| Finished | 2026-10-30 22:05:45 Asia/Manila (UTC+8) |
| Scope | Steps 0-4 (stop after step 4; steps 5-8 out of scope) |
| Host | Linode shared VM, Ubuntu 24.04, sg-sin-2, no Docker |

## Step results

| Step | Result | Time (Asia/Manila) |
|---|---|---|
| step-0 preflight | PASS | 2026-10-29 16:29:41 |
| step-1 prerequisites | PASS | 2026-10-29 16:31:46 |
| step-2 workspace-and-onboard | PASS | 2026-10-29 16:31:50 |
| step-3 happy-1-program-and-P0-A | PASS-SEMI | 2026-10-29 17:20:16 |
| step-4 chain-to-first-frontend-story | PASS-SEMI | 2026-10-30 22:05:41 |

There were 10 resume or fix attempts: two kit updates and eight harness fixes or resumes. Some were caused by agy 429 quota limits or transient errors, not by kit bugs. See `results/summary.md` and `results/fix-attempts.tsv`.

## Memory verdict

Peak memory use during the run was about **2.2 GB**. A **4 GB VM without Docker is enough** for this plan.

## Contents

- `results/`: `summary.md`, `checks.tsv`, `results.tsv`, `fix-attempts.tsv`, `run.meta`, `chain.tsv`, `stories.tsv`, logs, and the archived `attempt-<k>/` tables.
- `status/`: `progress.log`, runner console and tty logs, step start markers.
- `evidence/`: per-step and per-turn text evidence (prompts, agent transcripts `*.jsonl`, check outputs), including the `attempt-<k>/` folders of earlier attempts.
- `findings/HARNESS-FIXES-20261029.md`: a results document of the harness and kit findings from this run. It is a copy for reference only. The harness changes it describes are **not** part of this commit.

Excluded: the `work/` trees (portal repo copies), `snapshots/` and every `*.tgz`/`*.tar*` evidence tarball, `trash/`, `kit/`, `calib/`, `agy-driver/`, `node_modules`, `*.env` launch and state files, any file over 50 MB, and any file whose name suggests secrets, OAuth, tokens, or credentials.
