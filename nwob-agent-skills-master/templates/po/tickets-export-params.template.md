# Tickets export parameters

Engagement-specific Jira import constants for `/backlog`. Copy to `nwob-docs/sdd/tickets-export-params.md` after prompter confirmation — do not treat the values below as locked skill defaults.

```markdown
# Tickets export parameters

- output_path: nwob-docs/sdd/tickets.csv
- issue_type: Technical story
- parent_id: TRIBEXX-XXXXX
- summary_prefix: "[GBox] "
- assignee: "@gcash.com"
- product: GBox
```

| Field | Required | Notes |
|-------|----------|-------|
| `output_path` | Yes | Relative to project root |
| `issue_type` | Yes | Exact string for every CSV row |
| `parent_id` | Yes | Epic / parent key for every row |
| `summary_prefix` | Yes | May be empty (`""`) |
| `assignee` | Yes | Applied to every row |
| `product` | Yes | Product / project field |
