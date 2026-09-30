---
description: Brownfield onboarding — discovery artifact, project profile, and baseline audit before feature delivery.
---

# /onboard

For an **existing** repo after `scripts/install.sh`:

1. Follow the `onboard-discovery` skill (repo map, dependency graphs, API inventory).
2. Run `scripts/audit-brownfield-baseline.sh` and record results in `docs/project-profile.md` (`known_failures` when baseline is red).
3. Run `scripts/generate-repo-map.sh` and optional `scripts/collect-dependency-graphs.sh` when present.
4. Produce or update `docs/project-profile.md` (build/test/lint commands, Layout directory profile, contract paths, MCP servers per `docs/mcp-baseline.md`, coverage ratchet link). Record Profile `service`, `ui`, or `app` when the tree matches `project-delivery-core.mdc`; otherwise record the discovered Backend root, Frontend root, and BFF root. Do not move source onto a greenfield default.
5. Refresh `docs/architecture.md` and `docs/network.md` **as-is** summaries (do not invent future state).
6. Inventory public APIs (OpenAPI on disk or generated) and record stack deviations from `project-delivery-core.mdc`.
7. When the program spans multiple repos, copy `templates/docs/workspace.manifest.json` to `docs/workspace.manifest.json` and record paths.
8. **Stop** for user approval before `/intake` on feature work.

Optional starters (`maven/`, `docker/`, `openapi/`): copy from kit `templates/` only when the user requests `--with-starters` install or explicit consent.

Rules: `workflow-orchestration.mdc`, `docs/brownfield-onboarding.md`.
