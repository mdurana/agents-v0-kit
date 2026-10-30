# P2-P persistent-quota fixtures (run 20261029-1629)

Regression fixtures for `classify()` / `agy_api_error_kind` (tests/test-classify.sh, section D).

| Dir | Raw source in `run-20261029-1629.tar.zst` | What happened |
|---|---|---|
| `design-1/` | `trash/p2p-quota-fail-20261030-1815/evidence/S4-p2-p-…-design-1/` | `/v0-design` ran 84 steps (17:44–17:54 Asia/Manila, 30 Oct), then agy stopped: "Individual quota reached … Resets in 53h19m58s" |
| `design-3/` | `…-design-3/` | the retry failed at step 1 with the same lasting quota ("Resets in 53h18m51s") |

Both turns were classed AGENT-ERROR in the run (the error is only in the agy side files; `turn-1.stderr` is
empty and the transcript ends with an empty `result`). They must be USAGE (HALT the run), with rc 0 or 1, and
must not fall into the "empty final result -> INFRA" rule.

Built by `sanitize.py <raw dir> <out dir> <n>`: conversation and error ids replaced, host paths and tool
parameters dropped, the tool list and the unattended-run preamble removed; the agy error text is verbatim.
No credentials, tokens, account names or e-mail addresses are in these files.
