# Design amendments: <feature>

> Copy to `docs/agents-v0/design/<feature>/amendments.md` when the first amendment is needed. Any change after Design approval to `design.md`, `openapi.yaml`, `events/`, `ux-spec.md`, `mockups/`, or the ADR named on the `ADR:` line is an amendment. A changed decision does not edit that ADR's Decision or Alternatives: set Status to `Superseded by ADR <NN>`, write the successor with Status `Accepted`, and point `design.md` at the successor.
>
> 1. Stop building the affected acceptance criterion. Re-open Design (`sh .agents-v0/scripts/sync-feature-state.sh <feature> --reopen design --active-phase design --status in_progress`).
> 2. Change the design files. When the decision changes, leave that ADR's Decision and Alternatives: set Status to `Superseded by ADR <NN>`, write the successor with Status `Accepted`, and point `design.md` at the successor.
> 3. Run `design-reviewer` on the design as it stands. `review.md` must have no open Critical. An open Critical goes back to `solution-architect` or `ux-designer`; then run the reviewer again.
> 4. Add a row below: what changed, why, and which AC and operations it touches.
> 5. Present it to the user. After explicit approval, put the approver and `Approved` in the row and run `sh .agents-v0/scripts/sync-feature-state.sh <feature> --approve design --clear-active`. Resume Build.

| # | Date | Change | Reason | Impacted AC and operations | Approver | Decision |
|---|------|--------|--------|----------------------------|----------|----------|
| <!-- TEMPLATE: 1 --> | | | | | | |
