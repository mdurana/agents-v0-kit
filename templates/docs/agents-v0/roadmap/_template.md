# Roadmap: <program>

Discovery: <repo-relative path the user passed to /v0-roadmap> (sha256: <sha256-hash>)

<!-- Stack preference: copy a discovery line `Stack preference: <id>` here when that file has one. Otherwise delete this comment. It does not activate a pack. -->

## Problem

<copied from the discovery file>

## Success metric

<copied from the discovery file>

## Chosen option

<copied from the discovery file>

## Now

- <one in-scope item, copied>

## Next

- <one in-scope item, copied>

## Later

- <one in-scope item, copied>

## Out of scope

<copied from the discovery file>

## Delivery approvals

| Phase | Artifacts | Approver | Decision | Date |
|-------|-----------|----------|----------|------|
<!-- Append the Approved row only after explicit user approval, e.g.:
roadmap | <this file, the discovery path> | <name> | Approved | <YYYY-MM-DD>
-->

> The `roadmap` row covers the sequence. The discovery file has no kit approval row.
> `/v0-architecture` runs next and does not write stories. `/v0-plan` then reads this file and does not add a theme it does not name.
> `.agents-v0/ci/check-roadmap.sh <this file>` checks the roadmap content gate before approval; `.agents-v0/ci/check-roadmap.sh --approved <this file>` (or `.agents-v0/ci/check-approvals.sh <this file> roadmap`) verifies the approved roadmap.
