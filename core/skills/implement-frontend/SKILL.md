---
name: implement-frontend
description: Build phase playbook. Implement SvelteKit client or React admin — routes, loads, forms, a11y, XSS-safe content — with red–green tests.
---

# implement-frontend

Build phase playbook for the `frontend-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts — including the approved UX spec (`docs/design/<feature>/ux-spec.md`) and the HTML mockups it links under `docs/design/<feature>/mockups/` — and the existing frontend. If a UI change has no approved spec or a linked mockup is missing, stop.
2. **Baseline:** run the full Frontend verify command from `docs/project-profile.md` before the first edit. If it fails, stop and report the pre-existing failure; never build on a broken baseline. Put UI code under that frontend root.
3. **Wire the frontend quality gate** if missing (ESLint, coverage provider with the ≥ 70% threshold, lockfile audit) — unwired tooling makes the build script compile-only.
4. For greenfield UI, confirm the Svelte/React decision (asked once in Intake).
5. Before the first implementation edit, write or continue `docs/build/<feature>/plan.md`: one row per approved `AC-*`. Mark a row `done` only after that unit's fast command is green, and name the test. Do not add, delete, or rewrite AC rows.
6. Work **red–green (TDD where practical)** per plan row: failing test first, then implement until green (`quality-and-testing.mdc`). Each loop run uses `Frontend verify (fast)` when that cell is a real command. An empty cell or a placeholder comment means the loop uses the full Frontend verify command. Append a command-result card. The next attempt must not read `build-output.txt`. The second red result for the same test writes `docs/build/<feature>/failure-brief.md` and returns for `debug-investigator`. Attempt three applies that note. A third red result stops.
7. Implement routes/loads/components per `frontend-web.mdc`:
   - SvelteKit: `src/routes/` + `src/lib/` under the frontend root; prefer `load`/server loads; `browser` guard before `localStorage`.
   - React admin: `src/pages/`, `src/features/`, `src/components/`, `src/services/api`, `src/store/slices` under the frontend root; RHF + Zod.
   - UX spec: per-screen state matrix (loading/error/empty/success), component default behavior (honor an override when the spec records one), and layout matching the linked mockups.
8. Wire the API client in the app, not in the mockups: call only the OpenAPI operation named on each component row. Those operations come from the feature draft merged into the org catalog. Send Bearer, `X-Correlation-ID`, and `traceparent`; map success, validation error, 401, and 5xx to the states in the spec. 401 refresh/redirect per `frontend-web.mdc`.
9. Enforce route/module access in `+layout.server.ts`, hooks, or BFF — not UI hide-only.
10. Logout: clear **all** client state (`sessionStorage`, `localStorage`, cookies, in-memory); call backend logout + IdP sign-out for SSO.
11. Cookies: `httpOnly`, `secure` (prod), `sameSite`; no auth tokens via `document.cookie`.
12. XSS: sanitize/avoid `innerHTML`/`{@html}`/`dangerouslySetInnerHTML`.
13. No backend URLs/RBAC roles/permission keys in client bundles; no `PUBLIC_*`/`VITE_*` leaking internal config; `sourcemap: false` in prod.
14. Accessibility: semantic HTML, keyboard flows, focus order, ARIA only when needed, contrast, `prefers-reduced-motion` — per the UX spec.
15. Run the full Frontend verify command from `docs/project-profile.md` once for the Build gate, with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. The fast loop does not replace this gate.
16. Persist evidence to `docs/build/<feature>/build-report.md` (command, result, attempt cards, per-criterion file:line evidence) and `docs/build/<feature>/build-output.txt` (raw output; no secrets). Do not read `build-output.txt` on the next attempt.

## Rule-compliance checklist
- [ ] `frontend-web.mdc`: structure; `load`; `browser` guard; stores; Zod forms; user-visible fetch errors.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; frontend coverage ≥ 70% on changed code.
- [ ] Baseline green before the first edit; red–green loop uses `Frontend verify (fast)` when that cell is a real command; the full Frontend verify command runs once at the gate.
- [ ] `vapt-webapp.mdc` F1: validated session; clear all client state on logout; backend + IdP sign-out.
- [ ] `vapt-webapp.mdc` F2: no config/RBAC/internal URLs in client bundle; `sourcemap: false`.
- [ ] `vapt-webapp.mdc` F4: server-side route enforcement.
- [ ] `vapt-webapp.mdc` F7: cookie flags; no `document.cookie` auth tokens.
- [ ] `vapt-webapp.mdc` F3: client upload UI supplemental.
- [ ] `frontend-web.mdc` (XSS): sanitize/avoid dangerous HTML sinks.
- [ ] UX spec: state matrix, component defaults, mockup layout, accessibility, and design-system conformance implemented. API calls use named OpenAPI operations only.
- [ ] Build evidence persisted under `docs/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
