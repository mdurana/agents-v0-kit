---
name: implement-frontend
description: Build phase playbook. Implement the UI named by the pack's ui id — routes, loads, forms, a11y, XSS-safe content — with red–green tests. The React example is frontend-web.mdc.
---

# implement-frontend

Build phase playbook for the `frontend-engineer` agent (`workflow-orchestration.mdc`).

## Steps
1. Read the Design artifacts — including the approved UX spec (`docs/agents-v0/design/<feature>/ux-spec.md`) and the HTML mockups it links under `docs/agents-v0/design/<feature>/mockups/` — and the existing frontend. If a UI change has no approved spec or a linked mockup is missing, stop.
2. **Baseline:** run the full Frontend verify command from `docs/agents-v0/project-profile.md` before the first edit, unless `/v0-build` skips a checkout that is already the default branch tip. If it fails, stop and report the pre-existing failure; never build on a broken baseline. Put UI code under that frontend root.
3. **Wire the frontend quality gate** if missing (ESLint, coverage provider with the ≥ 70% threshold, lockfile audit) — unwired tooling makes the build script compile-only.
4. The UI is the bound pack's `ui` id. Read that UI manifest (`layout`, `verify`, `verifyFast`, `coverage`) from `pack.json`. The React example is React 19, TypeScript 5.9, Vite 7 (`frontend-web.mdc`, `core/ui/react/pack.json`).
5. Before the first implementation edit, write or continue `docs/agents-v0/build/<feature>/plan.md`: one row per approved `AC-*`. Mark a row `done` only after that unit's fast command is green, and name the test (`(no-red: <reason>)` waives one row when a red test does not apply). Do not add, delete, or rewrite AC rows. Ensure every `/api/` call in the frontend corresponds to an operation in the OpenAPI catalog.
6. Work **red–green (TDD where practical)** per plan row: failing test first, record the red test attempt card in `build-report.md`, then implement until green (`quality-and-testing.mdc`). Each loop run **must** use `Frontend verify (fast)` from the profile (a real command such as `npm test`, not a `<!--` placeholder). If that cell is empty or still a placeholder, stop and fill the profile rather than running the full Frontend verify in the loop. Append a command-result card. The next attempt must not read `build-output.txt`. Before each new attempt run `sh .agents-v0/scripts/check-attempt-budget.sh docs/agents-v0/build/<feature>/build-report.md`; exit 1 means the phase attempt budget is spent (`workflow-orchestration.mdc`): record `blocked` and stop. The second red result for the same test writes `docs/agents-v0/build/<feature>/failure-brief.md` and returns for `debug-investigator`. Before attempt three run `sh .agents-v0/scripts/check-failure-brief.sh <feature>` (must exit 0). Attempt three applies that note. A third red result stops.
7. Implement routes/loads/components using the UI pack's `layout`. The React example (`frontend-web.mdc`) uses `src/pages/`, `src/features/`, `src/components/`, `src/services/api`, `src/store/slices` under the frontend root, and RHF + Zod. An existing SvelteKit repo keeps `src/routes/` + `src/lib/`; prefer `load`/server loads; `browser` guard before `localStorage`.
   - UX spec: per-screen state matrix (loading/error/empty/success), component default behavior (honor an override when the spec records one), and layout matching the linked mockups.
8. Wire the API client in the app, not in the mockups: call only the OpenAPI operation named on each component row. Those operations come from the feature draft merged into the org catalog. Send Bearer, `X-Correlation-ID`, and `traceparent`; map success, validation error, 401, and 5xx to the states in the spec. 401 refresh/redirect per `frontend-web.mdc`.
9. Enforce route/module access on the server or in the BFF, not by hiding a control. The React example uses a route wrapper. An existing SvelteKit repo uses `+layout.server.ts`.
10. Logout: drop the in-memory access token, expire the refresh cookie, and clear leftover client state (`sessionStorage`, `localStorage`, other cookies). Call backend logout + IdP sign-out for SSO. Access tokens and refresh tokens are not written to web storage.
11. Cookies: `httpOnly`, `secure` (prod), `sameSite`; no auth tokens via `document.cookie`.
12. XSS: sanitize/avoid `innerHTML`/`{@html}`/`dangerouslySetInnerHTML`.
13. No backend URLs/RBAC roles/permission keys in client bundles; no `PUBLIC_*`/`VITE_*` leaking internal config; `sourcemap: false` in prod.
14. Accessibility: semantic HTML, keyboard flows, focus order, ARIA only when needed, contrast, `prefers-reduced-motion` — per the UX spec.
15. Run the full Frontend verify command from `docs/agents-v0/project-profile.md` once for the Build gate, with **bounded fix attempts (≤ 3 per failure)**; on exhaustion stop and present the blocker. The fast loop does not replace this gate.
16. Persist evidence to `docs/agents-v0/build/<feature>/build-report.md` (command, result, attempt cards, per-criterion file:line evidence) and `docs/agents-v0/build/<feature>/build-output.txt` (raw output; no secrets). Do not read `build-output.txt` on the next attempt.

## Rule-compliance checklist
- [ ] `frontend-web.mdc`: structure; `load`; `browser` guard; stores; Zod forms; user-visible fetch errors.
- [ ] `quality-and-testing.mdc`: red–green per behavior unit; report coverage ≥ 70% (CI fails changed lines under 80% when `DIFF_BASE` is set).
- [ ] Baseline green before the first edit; red–green loop uses a real `Frontend verify (fast)` cell; full Frontend verify once at the gate; `check-failure-brief.sh` before attempt three.
- [ ] `vapt-webapp.mdc` F1: access token in memory; refresh token in an HttpOnly cookie; clear leftover client state on logout; backend + IdP sign-out.
- [ ] `vapt-webapp.mdc` F2: no config/RBAC/internal URLs in client bundle; `sourcemap: false`.
- [ ] `vapt-webapp.mdc` F4: server-side route enforcement.
- [ ] `vapt-webapp.mdc` F8: server load or BFF authorizes another user’s `{id}` before render.
- [ ] `vapt-webapp.mdc` F7: cookie flags; no `document.cookie` auth tokens.
- [ ] `vapt-webapp.mdc` F3: client upload UI supplemental.
- [ ] `frontend-web.mdc` (XSS): sanitize/avoid dangerous HTML sinks.
- [ ] UX spec: state matrix, component defaults, mockup layout, accessibility, and design-system conformance implemented. API calls use named OpenAPI operations only.
- [ ] Build evidence persisted under `docs/agents-v0/build/<feature>/`; fix attempts bounded.
- [ ] `workflow-orchestration.mdc`: Build gate criteria met.
