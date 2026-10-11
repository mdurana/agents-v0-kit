# Token optimization assessment (item 6 — always-on trim)

**Status:** assessed, **not** implemented as a large cut.  
**Constraint:** optimize tokens without reducing agent accuracy.

## Finding

`workflow-orchestration.mdc` (~22 KB) dominates always-on load (~31 KB with the other two always-on rules). Trimming it further is the largest *theoretical* per-turn saving, but it is also the highest **accuracy risk**: gate order, never-infer-approval, Material/ARC, attempt budget, design locks, and parallel-feature stops must remain visible even when no phase command is open (`/v0-status`, freeform chat, mid-resume).

## Recommendation

| Do now | Do not do yet |
|--------|----------------|
| Keep invariants always-on (short checklist is fine) | Move approval/gate/lock rules only into `/v0-*` commands |
| Move *procedure* already done via skills + this round’s snippets | Aggressive cut below ~20 KB of orchestration without a validate-kit invariant suite |
| Deduplicate command ↔ skill (done for `/v0-build` step 6) | Duplicate thinner copies that can drift |

## Revisit when

1. Always-on is over the 32000-byte validate-kit budget again, **and**
2. `validate-kit.sh` asserts a fixed invariant list still present in `workflow-orchestration.mdc` (approval never inferred; attempt budget; failure-brief; story-size; Material/ARC; design lock), **and**
3. A dry-run `/v0-status` + freeform “continue the feature” session still stops correctly without re-invoking the phase command.

Until then, prefer snippets, fast verify, failure-brief checks, and story-size enforcement (items 1–5) over thinning always-on judgment.