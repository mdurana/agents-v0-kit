# Design amendments: <feature>

> Copy to `docs/design/<feature>/amendments.md` when the first amendment is needed. The approved design is pinned in `design.lock`. Any later change to `design.md`, `openapi.yaml`, `events/`, `ux-spec.md`, or `mockups/` is an amendment:
>
> 1. Stop building the affected acceptance criterion. Set the Build phase `blocked` with the reason "design amendment".
> 2. Change the design files. Run `sh ci/check-design.sh <feature>` and `sh ci/check-design.sh <feature> --hash`.
> 3. Add a row below: what changed, why, which AC and operations it touches, and the first 12 characters of the new hash.
> 4. Present it to the user. After explicit approval, put the approver and `Approved` in the row, then `sh ci/check-design.sh <feature> --pin "amendment <n>"`.
> 5. Re-run `design-reviewer` on the changed parts. Resume Build.
>
> CI (`ci/check-design.sh --verify-lock`) fails a design that changed without a matching Approved row.

| # | Date | Change | Reason | Impacted AC and operations | Approver | Decision | Hash (first 12) |
|---|------|--------|--------|----------------------------|----------|----------|-----------------|
| <!-- TEMPLATE: 1 --> | | | | | | | |
