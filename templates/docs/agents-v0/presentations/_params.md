# Deck params

Kind: product | delivery | intake
Audience: Technical | Non-technical | Mixed
Decision: <the question the meeting must answer, in the user's words>

## Sources

| Path | Approval date |
|------|----------------|
| <path> | <YYYY-MM-DD> |

> `/v0-deck` (`docs-author` + `leadership-deck`) writes a sibling `<name>.md` deck and this params file,
> verified by `guard-deck.sh verify` and committed by `guard-deck.sh commit`.
> The deck is not a delivery gate. `/v0-status` does not report it.
