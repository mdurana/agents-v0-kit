# ADR <NN>: <title>

- **Date:** YYYY-MM-DD
- **Status:** Proposed | Accepted | Superseded by ADR <NN>

<!-- An Accepted ADR stays. A later decision writes the next file and sets this line to "Superseded by ADR <NN>". Do not edit Decision or Alternatives after Accepted. -->
- **Deciders:** <names>

## Context

<!-- Why is this decision needed? What constraints? -->

## Decision

<!-- What we decided. A pattern ADR also has its own line: Pack: <id> -->

## Alternatives considered

- <!-- alt 1 --> — pros/cons.
- <!-- alt 2 --> — pros/cons.

## Patterns considered

<!-- Pattern decisions only (topology, platform, integration style, data store, migration approach). Delete this section for any other ADR. At least two rows, compared on cost, security, reliability, and operability. A brownfield migration names the pattern it uses: strangler fig, adapter, dual write, or flag-controlled cutover. -->

| Pattern | Fit | Trade-offs | Rejected because |
|---------|-----|------------|------------------|
| | | | |

## Consequences

- Positive: ...
- Negative: ...
- Neutral: ...

## Compliance

- `architecture-and-diagrams.mdc`: service boundaries / DB per service / contract-first.
- `security-baseline.mdc`: authn/authz impact.
- `project-delivery-core.mdc`: stack / async justification.
