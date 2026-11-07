# Jira export params

Project key:
Issue type:
Output path: docs/agents-v0/backlog/tickets.csv

> `/v0-export` (`guard-export.sh check`) asks before the first write when Project key or Issue type is empty.
> Confirm with `yes` or an explicit override. The CSV is regenerated from approved
> artifacts and verified by `guard-export.sh verify` before `guard-export.sh commit`. Jira is not read back.
