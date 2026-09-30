# Security standards

> See `security-baseline.mdc` for the authoritative org standard. This file captures repo-specific details.

## Authentication

- Protocol: OAuth2/OIDC (Okta) or JWT Bearer.
- Session: stateless JWT for REST APIs.
- MFA: required for admin/backoffice.
- Logout: invalidate server tokens, clear client state, revoke IdP session (SSO).
- Token blacklist: fail-closed on infra errors.
- Dev bypass: `permit-all` local dev only.

## Authorization

- RBAC/ABAC, least privilege; `@PreAuthorize` on every mutating/admin method.
- Server-side enforcement; never trust client role headers.
- BOLA/IDOR: authorized lookup for every `{id}` path.

## Secrets

- Environment variables / vaults only.
- No backend URLs/keys/roles in client bundles.
- `PUBLIC_*`/`VITE_*` only for intentionally public values.
- PII/tokens in body/headers, not query strings.
- Sanitize log values (`Encode.forJava`).

## Cookies

- `HttpOnly`, `Secure` (prod), `SameSite=Lax|Strict`.

## Uploads

- Server-side: size limit, magic-byte sniff + structure parse, `@PreAuthorize`; extension allowlist supplemental.

## Headers

- HSTS, `X-Content-Type-Options: nosniff`, `X-Frame-Options`, CSP, `Referrer-Policy`.

## Production hygiene

- `DEBUG` off; no demo/debug routes; sourcemaps off; `permit-all=false`.

## Compliance

- Identify regulations (GDPR, BSP, GXI).
- Security review required for: auth changes, new upload endpoints, RBAC changes, new public routes.
