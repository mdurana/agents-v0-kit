# System Threat Model (STRIDE)

| Threat Category | Surface | Mitigation |
|-----------------|---------|------------|
| **Spoofing** | BFF Session & OIDC Login | HttpOnly, Secure, SameSite session cookies; fail-closed on cache unavailability. |
| **Tampering** | CSV Uploads & Recipe JSON | Strict schema validation, file size cap (< 50 MB), immutable recipe versions. |
| **Repudiation** | Maker-Checker Approvals & SAP Postings | Append-only 13-month audit log recording actor email, correlation ID, and payload diff. |
| **Information Disclosure** | Error Responses & Logs | RFC 7807 Problem Details without stack traces; log sanitization of PII/secrets. |
| **Denial of Service** | Transformation Worker | Row count and runtime timeout safeguards; runtime execution lock on `JOB_QUEUED`/`RUNNING`. |
| **Elevation of Privilege** | API Endpoints & SoD | Deny-by-default endpoint mapping; strict Segregation of Duties preventing maker self-approval. |
