---
name: system-design
description: Major-tier system design. Context map, NFR/SLO budget, threat-model notes, deployment topology before feature contracts.
---

# system-design

Run for **Major** change tier (`workflow-orchestration.mdc`) or greenfield program start (before P1).

## Steps
1. Read Intake/program goals and `docs/project-profile.md` / `docs/repo-map.md`.
2. Produce or update `docs/design/system/context-map.md` — bounded contexts, integrations, sync vs async.
3. Record NFR/SLO budget in `docs/design/system/nfr-slo.md` (latency, availability, RPO/RTO). Filled rows stay open until the P4 SLO story writes `docs/design/system/slo-evidence.md` (`slo-evidence`): a measurement or a waiver per row.
4. Threat-model notes in `docs/design/system/threat-model.md` — assets, trust boundaries, top STRIDE risks, mitigations (no full STRIDE grid required).
5. Deployment topology in `docs/network.md` + sequence diagrams for critical flows.
6. ADR for non-trivial choices (`docs/adr/`).
7. **Stop** for approval before feature-level `/design` contracts. When this skill runs inside `/plan`, the Plan gate is that stop; `program-planning` continues from these outputs.

## Rule-compliance checklist
- [ ] `architecture-and-diagrams.mdc`, `security-baseline.mdc` §11 triggers addressed.
- [ ] Async/messaging/cache justified (`project-delivery-core.mdc`).
