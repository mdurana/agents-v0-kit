---
description: Trivial change tier — maintain lane with abbreviated path; record tier in requirements or maintain note.
---

# /triage

For **Trivial** tier changes (`workflow-orchestration.mdc`): docs-only, typos, dependency patch without behavior change.

1. Confirm the change does not touch auth, sessions, uploads, public routes, or schema.
2. Run `/maintain` with the smallest diff; skip `/intake` and `/design` when N/A with recorded reason.
3. Route to abbreviated Verify when security surface unchanged; full Verify when any security trigger applies.
4. Record `tier: trivial` in the maintain note or linked requirements artifact.

Do not use `/triage` for new features or auth changes — use `/intake` (Standard/Major).
