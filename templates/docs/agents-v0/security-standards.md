# Security standards

> Authoritative org standard: `security-baseline.mdc`. This file is the short copy installed repos read. When the two differ, `security-baseline.mdc` wins. ASVS 5.0.0 ids are in `docs/agents-v0/compliance-matrix.md`.

## Authentication

- Protocol: OAuth2/OIDC (Okta) or JWT Bearer.
- Browser session: access token in memory; refresh token in an HttpOnly, Secure, SameSite cookie.
- JWT: algorithm allowlist, reject `none`, validate `iss` / `aud` / `exp` / `nbf`, `kid` from known keys only. Short access-token lifetime. Refresh rotation; reuse revokes the family. Authorization identity is the validated `sub`.
- MFA for admin/backoffice. Step-up for actions the requirements artifact marks sensitive.
- Logout: drop the in-memory token, expire the refresh cookie, blacklist the server token, revoke the IdP session (SSO). Blacklist fails closed.
- Login and account-recovery responses are identical for known and unknown users.
- Dev bypass: `permit-all` local dev only.

## Authorization

- RBAC/ABAC, least privilege; `@PreAuthorize` on every mutating or sensitive method (F4, A01:2025).
- Server-side enforcement; never trust client role headers.
- BOLA: authorized lookup for every `{id}` path. The retest is a same-role peer (F8).
- Writes bind through a request DTO that rejects unknown properties.
- Policy or entitlement errors deny the request.

## Secrets and transport

- Environment variables / vaults only. Secrets and regulated personal data encrypted at rest; key in the vault.
- TLS 1.2 or 1.3 on outbound calls, with certificate verification.
- No backend URLs/keys/roles in client bundles.
- `PUBLIC_*`/`VITE_*` only for intentionally public values.
- PII/tokens in body/headers, not query strings.
- Sanitize log values (`Encode.forJava`).

## Cookies

- `HttpOnly`, `Secure` (prod), `SameSite=Lax|Strict`.
- Access token stays in memory. Refresh token is the HttpOnly cookie.

## Uploads

- Server-side: size limit, magic-byte sniff + structure parse, generated storage name, decompression limit, `@PreAuthorize`.
- Extension allowlist is supplemental. Production virus scan is required.

## Headers

- HSTS with `includeSubDomains`, `X-Content-Type-Options: nosniff`, `X-Frame-Options`, CSP (`frame-ancestors`, `base-uri 'self'`, `object-src 'none'`), `Referrer-Policy`, `Permissions-Policy`.
- `'unsafe-inline'` for scripts names the nonce or hash plan.

## API

- `/api/v1/`. Auth on non-health routes. Rate limit auth, admin, and upload.
- Parameterized queries. Sort and filter fields from an allowlist.
- User-supplied URLs fetched only against an allowlist; redirects stay on that list.
- 401/403, not 200 with an error body. No stack traces in production errors.

## Audit events

- Authentication, logout, authorization denial, token revocation, admin mutation, upload accept and reject.
- Correlation id, principal, action, result. No token or password.

## Supply chain

- Dependency scanning. No new high/critical CVE without a documented exception.
- Lockfiles committed. GitLab secret detection on the merge request.
- CycloneDX or SPDX SBOM for every service that ships. License policy when compliance requires it.

## Production hygiene

- `DEBUG` off; no demo/debug routes; sourcemaps off; `permit-all=false`.

## Compliance

- Identify regulations (GDPR, BSP, Data Privacy Act, GXI).
- Regulated personal data uses encryption in transit, encryption at rest, and §12 audit events.
- Security review required for: auth changes, new upload endpoints, RBAC changes, new public routes, and any `{id}` path.
