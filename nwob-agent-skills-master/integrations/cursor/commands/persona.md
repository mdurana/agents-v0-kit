Load and follow `.cursor/skills/switch-persona/SKILL.md` exactly.

The user wants to switch NWOB persona. Parse the target persona from their message.

If no persona specified, list installed personas from `.nwob/manifest.json` and ask which to activate.

If `nwob` CLI is available, run `nwob persona switch <persona>` to swap `.cursor/skills` and `.cursor/rules`.

Do not implement application code — persona routing only.
