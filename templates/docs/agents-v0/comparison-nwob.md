# Comparative matrix: agents-v0 vs NWOB Agent Skills

Engineering comparison of the **agents-v0** delivery kit and **NWOB Agent Skills** (vendored in this repo at `nwob-agent-skills-master/`). Use with [agents-v0-kit.md](agents-v0-kit.md) and [nwob-agent-skills-master/AGENTS.md](../../../nwob-agent-skills-master/AGENTS.md).

**Legend:** ✅ full · ◐ partial or indirect · ❌ absent

**Counts (repo snapshot):** agents-v0 — 15 commands, 19 agents, 27 skills, 14 rules, ~24 CI scripts; NWOB — 6 installable personas (+ 3 planned stubs), ~30 `SKILL.md` files, ~28 slash commands, constitution v1.4.0, no CI/hooks in the NWOB package.

---

## 1. Snapshot

| Dimension | agents-v0 | NWOB agent skills |
|-----------|-----------|-------------------|
| **Organizing unit** | Lifecycle **phase** (`/v0-*` commands) | **Persona** (role) + **skill** |
| **Core principle** | Phase not complete until gate passes + human approval | Zero vibe-coding: `epic-spec` → `story-spec` → `story-tasks` before build |
| **Orchestrator** | Main session; `/v0-deliver`, `/v0-status` | User or slash command; personas do not invoke personas |
| **Install** | `scripts/install.sh` → `.cursor/` | `nwob init` (Python `nwob_cli`), persona bundles |
| **Hosting assumed** | On-prem GitLab (`glab`, `.gitlab-ci.yml`) | GitLab MR workflow; Jira traceability in constitution-custom |
| **Maturity signal** | Kit `VERSION` (e.g. 0.0.1) | Constitution semver + sync impact report |
| **Primary audience** | Engineering delivery + approvers (`user-guide.md`) | PO, SA, LB, Builder, Pod Builder, Observer pods |

---

## 2. Lifecycle coverage

| Lifecycle stage | agents-v0 | NWOB |
|-----------------|-----------|------|
| Brownfield onboarding | ✅ `/v0-onboard` — discovery scripts, per-module docs, `path:line` citations | ◐ Phase 0 path mapping (`.nwob/artifact-paths.json`); branch-entry matrix; no code-discovery skill |
| Problem definition | ◐ Discovery file for `/v0-roadmap`; no `/problem` | ✅ `/problem`, `/ideate` |
| Roadmap | ✅ `/v0-roadmap` + `roadmap` approval row | ✅ `/roadmap` → `epic-spec.md` |
| Architecture | ✅ `/v0-architecture` — C4→ops, ARC pack, `architecture` row | ✅ `/c4` … `/ops`, `/adr`, `/arc`, `/architecture` |
| Program planning / backlog | ✅ `/v0-plan`, `/v0-export` (Jira CSV) | ✅ `/features`, `/backlog` (DEEP, sprint-ready, `tickets.csv`) |
| Requirements / AC | ✅ `/v0-intake` — Gherkin `AC-*`, `Kind`, failure case, NFRs | ✅ `story-spec.md` — Gherkin AC, Fibonacci size, 5-point cap |
| Design / contracts | ✅ `/v0-design` — OpenAPI, AsyncAPI, events, ADR, UX, `design.lock` | ◐ `/contracts`, `orchestrate-design`, `co-design-solution`; no hash pin |
| UX design | ✅ `ux-designer`, `ux-spec.md`, mockups | ❌ |
| Design review | ✅ `design-reviewer` → `review.md`; amendment re-pin | ✅ `validate-design-package` (sequential after draft) |
| Build | ✅ `/v0-build` — red/green per AC, attempt budget, `debug-investigator` | ✅ `trigger-ai-build` (Plan/Build), `review-implementation` per task ID |
| Verify | ✅ `/v0-verify` — test-engineer, security + code reviewers | ◐ `/audit` peer MR audit; no separate test/security phase |
| Merge request | ✅ `/v0-release` — MR body, local delivery gate | ✅ `raise-merge-request`, `resolve-review-comments` |
| Deploy | ◐ `release-deploy` skill; optional per-env | ❌ |
| Maintenance / bugfix | ✅ `/v0-maintain`, `/v0-triage`, tiers, characterization tests | ❌ |
| Leader decks | ✅ `/v0-deck` (`leadership-deck`) | ✅ `/collect`, `/present`, `/enrich`, `/deck` (tiered gates, HTML) |
| Value stream / process | ❌ | ✅ `/value` |
| Pilot / AI observation | ❌ | ✅ Observer — `/summarize`, `/meeting`, techniques, feedback, `/handoff` |
| Resume / status | ✅ `/v0-status`, `*.state.json` | ◐ Brownfield matrix only |
| Sprint ceremonies | ❌ | ◐ SM / QA / Solution Designer planned stubs |

---

## 3. Roles and agents

| Concern | agents-v0 | NWOB |
|---------|-----------|------|
| **Role model** | 19 task agents (e.g. `requirements-analyst`, `security-reviewer`) | 6 personas: PO, SA, LB, Builder, Pod Builder, Observer |
| **Product** | `requirements-analyst`, `program-planner` | PO — 10 skills |
| **Architecture** | `solution-architect`, `design-reviewer` | SA + LB co-equal — 14 skills each |
| **Build** | `backend-engineer`, `bff-engineer`, `frontend-engineer`, `schema-author` | Builder (4 skills), Pod Builder (7 skills) |
| **Quality / security** | `test-engineer`, `security-reviewer`, `code-reviewer` (separate reports) | `review-implementation`, `/audit` (peer; author must not self-audit) |
| **Helpers** | `explore-researcher`, `debug-investigator`, `docs-author`, `maintenance-engineer`, `codebase-documenter` | ❌ |
| **Separation of duties** | Review uses non-Build model; parallel reviewer reports | Sessions 1–4 author ≠ Session 5 `/audit`; skill-hat gates |
| **Persona switching** | N/A (command routes to agent) | `/persona`, `/switch` — one active persona in `.cursor/` |
| **Sub-agent policy** | Phase agents write brief; session launches helper | Personas do not invoke personas |
| **Model routing** | ✅ `model-routing-matrix.md`, `.cursor/model-config.json` | ❌ |

---

## 4. Artifacts and records

| Artifact | agents-v0 | NWOB |
|----------|-----------|------|
| **Root** | `docs/agents-v0/` | `nwob-docs/`; SDD via `.nwob/artifact-paths.json` |
| **Program spec** | `roadmap/`, `architecture.md`, `milestones/` | `sdd/epic-spec.md` |
| **Story requirements** | `requirements/<feature>.md` | `sdd/stories/{ID}/story-spec.md` |
| **Tasks** | `build/<feature>/plan.md` (per AC) | `story-tasks.md` |
| **Architecture** | `architecture.md`, `arc-record.md`, `adr/` | `architecture/architecture.md` ↔ `sdd/masterplan.md`, `sdd/components/*-plan.md` |
| **Contracts** | `design/<feature>/openapi.yaml`, asyncapi, `events/` | OpenAPI via SA/LB `/contracts` |
| **Execution plan** | `build-report.md` cards | `~/.cursor/plans/` only (not SDD) |
| **Verify evidence** | `verify/<feature>/` with `commit:` | `audit-report.md` |
| **Approvals** | 5-column table in artifact (Phase, Artifacts, Approver, Decision, Date) | Procedural gates A–E; no ledger |
| **State / resume** | `*.state.json` (`sync-feature-state.sh`) | ❌ |
| **Observations** | ❌ | `meetings/`, `observations/` |
| **Presentations** | `presentations/<name>.md` | `presentations/` + `intake-record.md` |
| **Write controls** | CODEOWNERS + hooks on kit/CI | Prose ACL — owning skill writes only |

---

## 5. Governance and gates

| Mechanism | agents-v0 | NWOB |
|-----------|-----------|------|
| **Gate model** | Per-phase human approval; never infer approval | SDD gates A–E + Pod Builder Sessions 1–6 STOP points |
| **Evidence** | `Approved` row; Build/Verify paths + `commit:` on disk | Artifacts on disk; increment verdicts |
| **Staleness** | CI rejects stale evidence after code change | ❌ |
| **Design immutability** | `design.lock` hash; amendments; `check-adr.sh` | ◐ ACL + formal amendment language |
| **Change tiers** | Trivial / standard / major / emergency + `classify-change.sh` | ❌ |
| **Merge authority** | Human merge; hooks block `glab mr merge/approve`; `delivery-approval` job | Human merge; agent must not approve/merge (policy) |
| **Commit / push** | Hooks prompt per authorization | No agent commit/push Sessions 2–4; Session 6 after user yes |
| **Rule precedence** | Repo wins; exceptions in `project-profile.md` / ADRs | Prompt → SDD → project → constitution defaults |
| **Overridable defaults** | Profile + org rules | Stack + data lifecycle only; rest mandatory |
| **Anti-rationalization** | ❌ | ✅ Listed forbidden excuses; skill at 1% match |

---

## 6. Enforcement

| Layer | agents-v0 | NWOB |
|-------|-----------|------|
| **CI** | ✅ ~24 scripts; gates from default branch | ❌ (not in NWOB package) |
| **Hooks** | ✅ 7 Cursor hooks; fail-closed; block kit/CI tampering | ❌ |
| **Delivery linkage** | ✅ MR code changes name feature or maintain note | ❌ |
| **Endpoint auth** | ✅ `check-endpoint-auth.sh` | ❌ |
| **Contracts** | ✅ OpenAPI lint/compat/merge; additive events | ❌ |
| **Build-plan TDD** | ✅ AC tests must go red first | ❌ (increment review only) |
| **Coverage** | ≥80% changed lines + ratchet | 100% meaningful (non-overridable) |
| **CVE gate** | ✅ HIGH/CRITICAL unsuppressed fails | ❌ |
| **Kit self-tests** | ✅ `validate-kit.sh`, `test-*.sh` | ◐ `nwob doctor` |
| **Audit export** | ✅ `export-audit-pack.sh` (SHA-256 manifest) | ❌ |
| **Delivery metrics** | ✅ `delivery-metrics.sh` (e.g. emergency overdue) | ❌ |

---

## 7. Engineering standards

| Topic | agents-v0 | NWOB |
|-------|-----------|------|
| **Backend default** | Java 17+, Spring Boot 3.x | Java (modern); neutral in `constitution-custom.mdc` |
| **Database** | PostgreSQL 15+, Flyway | PostgreSQL, Liquibase |
| **Messaging** | Kafka/Rabbit/SCS when justified | Kafka + idempotency + DLQ |
| **Cache** | Redis / Caffeine / Hazelcast | Redis ephemeral only |
| **Observability** | OTel-aligned, Prometheus, correlation ID | Datadog default; OTel optional |
| **Errors** | RFC 7807 **or** custom envelope (one per surface) | RFC 7807 mandatory (`trace_id`, `error_code`) |
| **Data lifecycle** | Not prescribed in kit core | Soft-delete mandate, audit timestamps, async purge |
| **Stateless workloads** | Implicit | Mandatory (K8s/EKS defaults) |
| **Frontend** | Svelte or React (ask once) | No dedicated frontend rules |
| **Security** | `security-baseline`, VAPT rules; unchecked VAPT = Critical | Short DoD security bullets; no VAPT pack |
| **Complexity** | Cognitive ≤15, method ≤30 lines, class <300 | `implementation-quality-standards.md` |
| **Test naming** | `methodName_scenario_expectedOutcome` | `tc<NNN>_method_given_should` + AAA comments |
| **Git / MR** | Feature branch ↔ artifact; `render-mr-body.sh` | `git-delivery-standards.md`, conventional commits, one branch per ticket |

---

## 8. Tooling and portability

| Concern | agents-v0 | NWOB |
|---------|-----------|------|
| **Install** | `install.sh`, `--with-starters`, `--update` | External clone or submodule; `--force`, `--no-scaffold-docs` |
| **Greenfield** | `bootstrap-greenfield.sh` | `nwob init` + `nwob-docs/` scaffold |
| **Brownfield** | `audit-brownfield-baseline.sh`, `/v0-onboard` | Map external SDD in place; no forced copy |
| **Multi-service** | Service roots, per-service OpenAPI, `workspace.manifest.json` | `repositories/` + `service-map.md` |
| **Air-gap** | `CI_IMAGE_PREFIX` mirrors | Not addressed |
| **IDE** | Cursor | Cursor primary; AGENTS.md mentions Claude Code, Copilot |
| **Context discipline** | Always-on rules capped 32 KB | SKILL.md <500 lines; progressive disclosure |

---

## 9. Strengths, gaps, and conflicts

| | agents-v0 | NWOB |
|---|-----------|------|
| **Strengths** | Machine-enforced gates, approval ledger tied to GitLab approver, evidence `commit:`, design lock, maintain/triage/emergency, VAPT depth, model routing | Product/presentation depth, SA/LB architecture chain, Pod Builder sessions, Observer/pilot learning, constitution + overrides, bundles + `nwob doctor` |
| **Gaps** | Shallow product discovery/decks; no Observer; no soft-delete lifecycle rules; Cursor-only | No CI/hooks; no approval ledger; no maintain/deploy; no UX/VAPT; compliance is prose-dependent |
| **Main risk** | Ceremony on small changes; large kit surface | Agent or team skips skills without automation |

**Conflicts to resolve before combining:**

| Topic | agents-v0 | NWOB |
|-------|-----------|------|
| Coverage | ≥80% on changed lines (CI) | 100% meaningful, non-overridable |
| Error API | Envelope or RFC 7807 per surface | RFC 7807 always |
| Artifact tree | `docs/agents-v0/` + approval table | `nwob-docs/` + procedural gates |

---

## 10. Integration sketch (complementary use)

| NWOB upstream | agents-v0 downstream | Notes |
|---------------|----------------------|-------|
| `/problem` … `/features`, `/c4` … `/adr` | Intake → Design → Build → Verify → Release | NWOB `epic-spec.md` can feed agents-v0 roadmap/discovery |
| `story-spec.md` + Gherkin AC | `requirements/<feature>.md` + `AC-*` | Align IDs and file mapping explicitly |
| Observer outputs | — | Adds pilot telemetry agents-v0 lacks |
| Constitution (RFC 7807, lifecycle) | `project-profile.md` + CI gates | Pick one coverage and error standard per repo |

---

## Command / phase mapping (approximate)

| NWOB (intent / command) | agents-v0 |
|-------------------------|-----------|
| Phase 0 discovery | `/v0-onboard` (brownfield) or greenfield bootstrap |
| `/problem`, `/ideate`, `/roadmap` | `/v0-roadmap` (with discovery input) |
| `/c4` … `/architecture`, `/arc` | `/v0-architecture` |
| `/features`, `/backlog` | `/v0-plan`, `/v0-intake`, `/v0-export` |
| `/orchestrate-design`, `co-design-solution`, `validate-design-package` | `/v0-design` + design review pin |
| `trigger-ai-build`, `review-implementation` | `/v0-build` |
| `/audit` | `/v0-verify` (partial — no separate security phase in NWOB) |
| `raise-merge-request` | `/v0-release` |
| `/deck` | `/v0-deck` |
| — | `/v0-maintain`, `/v0-triage`, `/v0-deliver`, `/v0-status` |

---

## Adopted from NWOB (architecture side)

| NWOB feature | agents-v0 implementation |
|--------------|--------------------------|
| Data Flow Diagram on the Container topology | `## Data flow` in `architecture.md`; node IDs must match C4 Container (`ci/check-architecture-pack.sh`) |
| Conceptual, logical, physical data models | `## Data models` with `erDiagram` for logical and physical |
| State machine per aggregate | `## State machine` (`stateDiagram-v2`) |
| Failure-domain map and degradation matrix | `## Failure domains and degradation` |
| MVP and future state with triggers | `## MVP and future state` |
| Platform zone diagram with security boundaries | `## Target topology` in `network.md` |
| Service map and per-container component plans | `context-map.md` columns plus `design/system/components/<service>.md` (`_component.template.md`) |
| Topology selection rubric, trade-off analysis, migration patterns | `program-architecture` step 3 and the ADR `Patterns considered` table |
| Structural fitness functions with thresholds | `arc-record.md` structural table; SLO targets stay in `nfr-slo.md` |
| Build-and-run ownership, error budget, DB operation, readiness checklist, runbook template | `design/system/ops-readiness.md` |
| Independent validation before build | `design-reviewer` writes `design/system/architecture-review.md`; no open Critical before the `architecture` row |
| Deprecation, Hyrum's Law, material vs minor change, drift correction | `contract-first-design` step 5b; `program-architecture` Governance section |

Not adopted: dual-persist twins, AWS/EKS, Kafka and Datadog defaults, mandatory 100% coverage, mandatory RFC 7807, soft-delete mandate, and the "Approved with conditions" ARC outcome.

---

*Generated for kit maintainers. Update when either `agents-v0-kit.md` or NWOB `AGENTS.md` / constitution changes materially.*
