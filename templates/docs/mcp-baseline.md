# MCP baseline (optional)

The kit does not require MCP. When teams connect Jira, Confluence, GitLab (on-prem default), GitHub, or cloud tools:

## Governance
- Pin server versions; document each server in `docs/project-profile.md` under **MCP servers**.
- Use read-only tokens where possible; separate write-capable servers for release automation.
- Copy `templates/.cursor/mcp.json.example` → `.cursor/mcp.json` (Cursor) and merge org-approved servers only.
- Claude Code: merge allowed servers in `.claude/settings.json` per org policy — never commit production credentials.

## Guardrails
- Cursor: `beforeMCPExecution` runs `pre-mcp.sh`. Claude Code: `PreToolUse` matcher `mcp__.*` runs the same script.
- Kilo Code: no hook runtime — MCP calls are not intercepted by the kit. Keep Kilo MCP servers read-only, or restrict them in Kilo's own permission settings.

### Per-server policy (`mcp-policy.json`)

`install.sh` seeds `.cursor/hooks/mcp-policy.json` / `.claude/hooks/mcp-policy.json` when missing and never overwrites it. The hooks directory is edit-protected, so changes go through a human and CODEOWNERS review.

```json
{
  "default": "ask",
  "servers": {
    "github": {
      "block": ["merge_*", "delete_*"],
      "allow": ["list_*", "get_*", "search_*"],
      "ask": ["*"],
      "default": "ask"
    },
    "gitlab": {
      "block": ["merge_*", "delete_*", "accept_*"],
      "allow": ["list_*", "get_*", "search_*", "api_get_*", "api_list_*", "api_search_*"],
      "ask": ["*"],
      "default": "ask"
    }
  }
}
```

- Matching is `fnmatch` on the tool name, checked in order **block → allow → ask**, then the server's `default`.
- Unlisted servers use the top-level `default`. The kit default is `ask`, so a server that is not listed cannot run until a human approves the call. `heuristic` remains available as an explicit override (verb-based keyword check).
- Claude tool names `mcp__<server>__<tool>` are split automatically; Cursor passes the server name in the hook payload.

## Intake / Release integrations
- Jira/Confluence: optional; `/intake` can use MCP when configured — otherwise paste specs manually.
- Status reports in `/release`: use an org MCP/Confluence integration when configured; the kit does not bundle one.
