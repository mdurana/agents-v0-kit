---
name: system-design
description: Major-tier system design. Context map, NFR/SLO budget, threat-model notes, deployment topology before feature contracts.
---

# system-design

Run for **Major** change tier (`workflow-orchestration.mdc`) or greenfield program start (before P1).

## Steps
1. Read Intake/program goals and `docs/agents-v0/project-profile.md` / `docs/agents-v0/repo-map.md`.
2. Produce or update `docs/agents-v0/design/system/context-map.md` — bounded contexts, integrations, sync vs async.
3. Record NFR/SLO budget in `docs/agents-v0/design/system/nfr-slo.md` (latency, availability, RPO/RTO). Filled rows stay open until the P4 SLO story writes `docs/agents-v0/design/system/slo-evidence.md` (`slo-evidence`): a measurement or a waiver per row.
4. Threat-model notes in `docs/agents-v0/design/system/threat-model.md` — assets, trust boundaries, top STRIDE risks, mitigations (no full STRIDE grid required).
5. Deployment topology in `docs/agents-v0/network.md` + sequence diagrams for critical flows.
6. ADR for non-trivial choices (`docs/agents-v0/adr/`).
7. **Stop** for approval before feature-level `/v0-design` contracts. When this skill runs inside `/v0-plan`, the Plan gate is that stop; `program-planning` continues from these outputs.

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11 triggers addressed.
- [ ] Async/messaging/cache justified (`project-delivery-core.mdc`).
