---
name: onboard-discovery
description: Brownfield discovery playbook. Repo map, dependency graphs, API inventory, conventions in project-profile.
---

# onboard-discovery

Brownfield onboarding playbook for `/onboard` (`workflow-orchestration.mdc`).

## Steps
1. Run `scripts/audit-brownfield-baseline.sh` (from kit) or the target repo's documented verify command.
2. Run `scripts/generate-repo-map.sh` (seeded in target `scripts/`) to refresh `docs/repo-map.md`.
3. Run `scripts/collect-dependency-graphs.sh` → `docs/discovery/dependency-graph.txt` (and `package-graph.txt` when Node).
4. Inventory APIs: existing OpenAPI under `openapi/` or `**/openapi*.yaml`; note generated vs hand-written.
5. Update `docs/project-profile.md` (commands, Layout directory profile, contracts, `known_failures`, ratchet). Record Profile `service`, `ui`, or `app` when the tree matches `project-delivery-core.mdc`; otherwise record the discovered roots. Do not move source onto a greenfield default.
6. Update `docs/architecture.md` and `docs/network.md` as **as-is** (no future-state invention).
7. Record stack deviations from `project-delivery-core.mdc` in project-profile.
8. **Stop** for user approval before feature `/intake`.

## Rule-compliance checklist
- [ ] `workflow-orchestration.mdc`: brownfield baseline documented; project-profile complete.
- [ ] `project-delivery-core.mdc`: mandated docs refreshed when topology/behavior known.
- [ ] No weakening of security controls via undocumented project-profile exceptions.
