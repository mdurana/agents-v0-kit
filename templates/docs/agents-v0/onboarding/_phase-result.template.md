# Phase result: onboard

> Copy to `docs/agents-v0/onboarding/phase-result.md` at the Onboard gate (`/v0-onboard` step 6) and fill in every line. `sync-feature-state.sh` reads `phase:` and `status:`; the onboarding docs check (`check-onboarding-docs.sh --gate`) requires the `commit:` line, like every document under `docs/agents-v0/onboarding/`. Replace each `TEMPLATE:` line; the docs check fails while one remains.

phase: onboard
status: awaiting_approval
commit: <full sha of the tree the onboarding documents describe; the same as report.md>

## Summary

<!-- TEMPLATE: what was documented (modules, flows, system documents) and what is still UNVERIFIED, in two or three sentences. Point to report.md for the details. -->

## Gate check

<!-- TEMPLATE: the last line of `sh .agents-v0/scripts/check-onboarding-docs.sh --gate` (the OK line), and any WARN lines you left. -->
