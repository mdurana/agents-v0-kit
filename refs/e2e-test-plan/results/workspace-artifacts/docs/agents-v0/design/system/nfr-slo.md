# NFR & SLO Targets

| Service / Flow | SLI | SLO Target | Window |
|----------------|-----|------------|--------|
| Portal API (CRUD & Lookups) | p95 HTTP latency | <= 250 ms | 28 days |
| Funding Cost Transformation Run (< 50 MB) | End-to-end job completion | < 60 minutes | Per run |
| Portal API Availability | Successful non-5xx responses | >= 99.9% | 28 days |
| Audit Log Retention | Immutable online storage | 13 months | Continuous |
