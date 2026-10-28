# Maintenance note: Add AC-3 negative regression test for P1-A Lookup Table Registry

Id: p1-a-lookup-table-registry-fix-1
Tier: standard
Tier confirmed by: mdurana on 2026-10-28
Type: bug
Trigger: defect found after local release of p1-a-lookup-table-registry

## Scope

- `app/backend/src/test/java/com/example/app/api/LookupTableControllerTest.java`: Add explicit automated regression test named with `AC_3` (`ac3_createLookupTable_blankCode_rejectedWithBadRequest`) for the `Kind: negative` criterion (`AC-3`) of `p1-a-lookup-table-registry`.

## Acceptance

- **Expected:** One automated test per `Kind: negative` criterion (`AC-3`) of `p1-a-lookup-table-registry`, named with the criterion ID (`AC_3` / `@DisplayName("AC-3: reject blank lookup code")`), that passes against the code on the integration branch and fails when the protection is removed.
- **Actual:** `LookupTableControllerTest` did not include `AC-3` in the test name/display name.
- **Reproducing test:** `LookupTableControllerTest#ac3_createLookupTable_blankCode_rejectedWithBadRequest`.

## Security surface

- Touches controller input validation test (`F1`); full Verify with VAPT checklist applies.

## Rollback

- Revert merge commit of `maintain/p1-a-lookup-table-registry-fix-1` on `main`.

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
| maintain | docs/agents-v0/build/p1-a-lookup-table-registry-fix-1/build-report.md | mdurana | Approved | 2026-10-28 |
| verify | docs/agents-v0/verify/p1-a-lookup-table-registry-fix-1/quality-gate.md | mdurana | Approved | 2026-10-28 |
| release | docs/agents-v0/maintain/p1-a-lookup-table-registry-fix-1/state.json | mdurana | Approved | 2026-10-28 |
