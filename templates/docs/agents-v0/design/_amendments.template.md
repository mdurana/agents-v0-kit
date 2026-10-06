# Design amendments: <feature>

> Copy to `docs/agents-v0/design/<feature>/amendments.md` when the first amendment is needed. The approved design is pinned in `design.lock`. Any later change to `design.md`, `openapi.yaml`, `events/`, `ux-spec.md`, `mockups/`, or the ADR named on the `ADR:` line is an amendment. A changed decision does not edit that ADR's Decision or Alternatives: set Status to `Superseded by ADR <NN>`, write the successor with Status `Accepted`, and point `design.md` at the successor (`ci/check-adr.sh`).
>
> 1. Stop building the affected acceptance criterion. Set the Build phase `blocked` with the reason "design amendment".
> 2. Change the design files. When the decision changes, leave that ADR's Decision and Alternatives: set Status to `Superseded by ADR <NN>`, write the successor with Status `Accepted`, and point `design.md` at the successor. Run `sh .agents-v0/ci/check-design.sh <feature>`, `sh .agents-v0/ci/check-adr.sh`, and `sh .agents-v0/ci/check-design.sh <feature> --hash`.
> 3. Add a row below: what changed, why, which AC and operations it touches, and the first 12 characters of the new hash.
> 4. Present it to the user. After explicit approval, put the approver and `Approved` in the row, then `sh .agents-v0/ci/check-design.sh <feature> --pin "amendment <n>"`.
> 5. Re-run `design-reviewer` on the changed parts. Resume Build.
>
> CI (`ci/check-design.sh --verify-lock`) fails a design that changed without a matching Approved row.

| # | Date | Change | Reason | Impacted AC and operations | Approver | Decision | Hash (first 12) |
|---|------|--------|--------|----------------------------|----------|----------|-----------------|
| <!-- TEMPLATE: 1 --> | | | | | | | |
