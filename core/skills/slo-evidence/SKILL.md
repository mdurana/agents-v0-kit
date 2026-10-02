---
name: slo-evidence
description: Close filled NFR/SLO rows with a measurement or a named waiver. Used by the P4 SLO story at Verify.
---

# slo-evidence

Verify-phase playbook for the P4 SLO story (`workflow-orchestration.mdc`). The `test-engineer` runs it. It does not add a load-test tool and it does not change the org SLO. It records whether each filled row was measured or waived.

## When
Run when the requirements artifact is the P4 SLO story, or when it cites `docs/agents-v0/design/system/nfr-slo.md`. Skip with a recorded N/A when the story does not close SLO rows.

## Steps
1. Read `docs/agents-v0/design/system/nfr-slo.md`. A row is filled when its name cell is non-empty and at least one other cell in that row is non-empty.
2. Write `docs/agents-v0/design/system/slo-evidence.md` using the table below. One evidence row per filled NFR/SLO row, matched on the surface or tier name.
3. `measured`: put the command in **Command or waiver** and a repo-relative output file in **Output or approver**. The file must exist and must not contain `..`. Put the run date as `YYYY-MM-DD`.
4. `waiver`: put the reason in **Command or waiver**, the approver's name in **Output or approver**, and the date as `YYYY-MM-DD`. A waiver is a recorded decision, not a measurement.
5. When `nfr-slo.md` has no filled rows, write one `waiver` row whose surface is `none`, reason `no SLO rows recorded`, with an approver and a date.
6. Stop if any filled row has no evidence row. `ci/check-milestone.sh` fails P4 `verify` and `release` when this file is missing or a row is incomplete.

## Evidence table

| Surface | Kind | Command or waiver | Output or approver | Date |
|---------|------|-------------------|--------------------|------|
| checkout API | measured | k6 run scenarios/checkout.js | docs/agents-v0/verify/p4-a-slo/k6-summary.txt | 2026-09-30 |
| batch archive | waiver | Not measured this release | Ada Architect | 2026-09-30 |

## Rule-compliance checklist
- [ ] Every filled row in `docs/agents-v0/design/system/nfr-slo.md` appears in `docs/agents-v0/design/system/slo-evidence.md`.
- [ ] Each evidence row is `measured` (command + existing output file + date) or `waiver` (reason + approver + date).
- [ ] `workflow-orchestration.mdc`: P4 verify gate names this file.
