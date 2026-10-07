# Presentation Config Template

Copy this file to `.cursor/presentation.config.md` in your project workspace.
`/problem` (`business-problem-identification`) reads it to pre-fill delivery params when creating `nwob-docs/presentations/intake-record.md`. `/intake` may use it when updating fields.

See [presentation-standards.md](../rules/presentation-standards.md) and [product-owner-skill-boundaries.md](../rules/product-owner-skill-boundaries.md).

---

```yaml
# Project identity (derived from problem statement during /problem when not set)
project_name: My Platform
mission_statement: >-
  One or two sentences explaining what the platform does and why it matters
  to leaders and stakeholders.

# Presentation delivery parameters
audience: Mixed                    # Technical | Non-technical | Mixed
goal: New initiative kickoff       # Status update | New initiative kickoff | Architecture review | Roadmap review
output_format: HTML                # HTML | Markdown
output_path: nwob-docs/presentations/my-platform.html
# For Markdown output, use: nwob-docs/presentations/my-platform.md

# Canonical source paths (auto-populated by /problem; override only when needed)
source_paths:
  features: nwob-docs/sdd/epic-spec.md
  roadmap: nwob-docs/sdd/epic-spec.md
  architecture: nwob-docs/architecture/architecture.md
```

## Field reference

| Field | Required | Description |
|-------|----------|-------------|
| `project_name` | Yes | Name of the platform or demand (derived in `/problem` when possible) |
| `mission_statement` | Yes | Derived from problem statement during `/problem` |
| `audience` | Yes | Drives jargon depth and architecture detail level |
| `goal` | Yes | Drives section emphasis (status vs kickoff vs architecture review) |
| `output_format` | Yes | `HTML` for interactive deck; `Markdown` for narrative report |
| `output_path` | Yes | Under `nwob-docs/presentations/` |
| `source_paths` | No | Canonical `nwob-docs/` paths; `/collect` reads these only |

**Note:** Initial intake is created by `/problem`, not `/intake`. `/intake` updates delivery params only.
