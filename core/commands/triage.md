---
description: Trivial lane — a docs-only or version-only change, qualified by the diff and confirmed by a person, through /maintain with the abbreviated Verify.
---

# /triage

For changes that may use the **Trivial** tier (`workflow-orchestration.mdc` Change tiers). The diff decides, not the agent that made it: a change is eligible only when `ci/classify-change.sh` says so.

## What qualifies
- Documentation only, or version numbers only in build files and lockfiles (a bump replaces lines one for one).
- No security surface (controllers, authentication, authorization, sessions, uploads, CORS, security or deployment configuration), no schema change, no major version bump, no delivery artifact (`docs/requirements`, `docs/milestones`, the onboarding report).
- At most `TRIVIAL_MAX_FILES` files (default 10) and `TRIVIAL_MAX_LINES` source lines (default 200).

## Instructions
1. Make the change in the working tree only far enough to classify it, or describe it, then run `sh ci/classify-change.sh <base>` (add `--require-trivial` to get a non-zero exit). Read the `reason:` lines.
2. Not eligible: say why and use `/maintain` with `Tier: standard`, or `/intake` for a feature. Do not argue the classifier down.
3. Eligible: create the note (`/maintain` Resume, `Tier: trivial`) and ask the user to confirm the tier. Record "Tier confirmed by" with their name and the date. Without that confirmation, do not continue.
4. Continue as `/maintain`, with the smallest diff. Skip `/intake` and `/design`; write that in the note.
5. Run the classifier again before Verify. If the change grew past the line, stop: the tier becomes `standard`, with a new confirmation.
6. Verify is the abbreviated Verify (`/verify` Abbreviated Verify). CI repeats the classifier (`ci/check-delivery-linkage.sh`) and rejects a `trivial` note the diff does not support.

Do not use `/triage` for new features, auth changes, or schema changes.
