# P0 platform skeleton (app template)

Canonical greenfield codebase for profile `app` (and slices for `service` / `ui`).

- **Source of truth:** `backend/` and `frontend/` in this directory.
- **Install artifact:** `p0-platform-skeleton.tar.gz` (paths `app/backend`, `app/frontend`, `docker-compose.yml`).
- Pack: `./scripts/pack-app-template.sh`
- Extract into a target repo: `bootstrap-greenfield.sh --scaffold-app` or `./scripts/scaffold-app-template.sh <target>`

Stack: Java 21, Spring Boot 4.1.1, Tomcat 11.0.26, Spring Security, PostgreSQL 15, Flyway, React 19, TypeScript 5.9, Vite 7, Vitest 3. Health/shell only — no product domain.
