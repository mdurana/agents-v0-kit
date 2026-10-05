---
name: leadership-deck
description: Extract a markdown deck from an approved Intake artifact, or from approved roadmap, plan, and ARC records, or from those plus release evidence. Audience and the meeting decision come from the user.
---

# leadership-deck

Documentation playbook for `/v0-deck`. It does not record a delivery approval. It does not interview, and it does not add a mission statement or a success metric that the sources do not already contain.

## Steps
1. Require a kind, an audience of `Technical`, `Non-technical`, or `Mixed`, and the decision sentence the user wants the meeting to take. Stop when one of those is missing.
   - `intake` also requires the feature slug: `/v0-deck intake <feature> <audience> <decision>`.
   - `product` and `delivery` stay `/v0-deck product <audience> <decision>` and `/v0-deck delivery <audience> <decision>`.
2. **Intake** sources:
   - `docs/agents-v0/requirements/<feature>.md` with an `Approved` `intake` row. Refuse when that row is missing.
   - When that file has `Milestone file:`, that manifest is a source. It must contain the `Story:` id and an `Approved` `plan` row. Refuse when the line is set and either is missing. A file with no `Milestone:` line has no manifest source.
3. **Product** sources, each of which must already carry an `Approved` row except the discovery file:
   - the roadmap (`roadmap`). Read the discovery file only at its `Discovery:` path.
   - `docs/agents-v0/design/system/context-map.md`, cited by an `Approved` `plan` row.
   - `docs/agents-v0/design/system/arc-record.md` when it exists, with an `Approved` `arc` row.
   - every `docs/agents-v0/requirements/*.md` that has an `Approved` `intake` row. Skip a requirements file that does not. Do not fail the deck because some stories are not through Intake yet.
4. **Delivery** sources are the product sources plus the milestone manifests and the release evidence named on `Approved` `release` rows. Skip a release report that has no `Approved` row.
5. Refuse a source that lacks its `Approved` row. The discovery file is the exception: the roadmap row is the approval that admits it.
6. Write the deck as markdown. Every figure, date, and metric is copied from a source. When a number is not in the sources, omit it. Scenario text is copied from the requirements artifact. Do not invent a problem statement.
7. Use the outline for the kind. For `Non-technical`, an in-scope line is the scenario name only (`### AC-n — <name>`). For `Technical` and `Mixed`, also copy `Kind:` and the `Then` line.
8. Write the params file with Audience, Decision, and one source line per file (`path`, approval date). The discovery line uses the roadmap approval date. A requirements line uses the date on its `Approved` `intake` row.
9. Do not edit those sources. Do not add an `Approved` row.

### Intake outline
File: `docs/agents-v0/presentations/<feature>-intake.md`. Params: `docs/agents-v0/presentations/<feature>-intake.params.md`.

1. Decision, in the user's words.
2. User story sentence, copied.
3. In scope: the `AC-*` ids, rendered for the audience as in step 7.
4. Out of scope, regulations, and `Material:`, copied.
5. Preconditions and desk check, copied.

### Product and delivery outline
File: `docs/agents-v0/presentations/<roadmap-stem>.md` for product, and `docs/agents-v0/presentations/<roadmap-stem>-delivery.md` for delivery. Params sit beside the deck.

1. Decision, in the user's words.
2. Problem and success metric, copied from the discovery file.
3. Now, Next, and Later, copied from the roadmap.
4. Stories: one block per approved requirements artifact, using the intake outline's items 2 through 5. When no requirements artifact has an `Approved` `intake` row, write that no approved Intake artifact is on disk.
5. Delivery only: the release evidence the `Approved` `release` rows name, copied. Omit a figure the evidence does not contain.

## Rule-compliance checklist
- [ ] Audience and decision were supplied by the user. Intake also names the feature.
- [ ] Every source except the discovery file has an `Approved` row.
- [ ] The deck contains no number that the sources do not contain.
- [ ] Non-technical in-scope lines are scenario names. Technical and Mixed lines also copy `Kind` and `Then`.
- [ ] Requirements, design, and `Delivery approvals` were not edited.
