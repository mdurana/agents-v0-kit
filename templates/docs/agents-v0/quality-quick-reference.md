# Quality quick reference

> One-page summary. (`quality-and-testing.mdc`)

- **Before merge:** `./mvnw -B clean verify` from the backend root (Java) or `npm test` (frontend). See `docs/agents-v0/gold-standards.md`.
- **Coverage:** 80% backend / 70% frontend.
- **Method:** ≤ 30 lines; cognitive complexity ≤ 15.
- **Class:** < 300 lines.
- **Tests:** AAA; naming `methodName_scenario_expectedOutcome` (Java) / `should_expectation_whenCondition` (frontend).
- **Mocks:** external I/O only; domain tests deterministic.
- **CVEs:** no new high/critical without documented exception.
- **Integration:** Testcontainers (API+DB+messaging) where the repo depends on it.
- **Contracts:** Pact for BFF↔service.
