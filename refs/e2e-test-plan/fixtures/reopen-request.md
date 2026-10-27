Maintenance request for released story <SLUG> (story <ID>).

Type: bug. Trigger: defect found after local release. Tier: standard.

Finding: the requirements file docs/agents-v0/requirements/<SLUG>.md has at least one acceptance criterion with `Kind: negative`. The first of those criteria has no automated regression test whose name or display name contains its id (for example `AC-3`) and that fails when the protection it describes is removed.

Expected: one automated test per `Kind: negative` criterion of <SLUG>, named with the criterion id, that passes against the code on the integration branch.
Actual: the first `Kind: negative` criterion has no such test.

Done means: the reproducing test is written first; if it fails against the current code, apply the minimal fix; the full native verify command is green; the change goes through Verify and Local Release. Do not edit docs/agents-v0/requirements/<SLUG>.md or its state file.
