# Stack pack

- **Id:** node
- **Service skill:** implement-node-service
- **Rules:** node-backend.mdc, vapt-node.mdc
- **Skills:** implement-node-service, implement-node-bff, scaffold-node-service
- **Data stores:** PostgreSQL 15
- **Backend:** Node.js, NestJS, TypeScript 5.9, npm
- **HTTP:** NestJS controllers
- **Security:** Nest guards, Passport JWT
- **Database:** PostgreSQL 15, TypeORM migrations
- **Tests:** Jest
- **Local run:** Compose API :8080, UI :8081, postgres:15-alpine
- **Backend verify:** npm test -- --ci --coverage --coverageReporters=json-summary --reporters=default --reporters=jest-junit
- **Backend verify (fast):** npm test
- **Coverage:** coverage/coverage-summary.json
- **Tests report:** junit.xml
- **Auth:** @UseGuards or @Public on every handler. Express, when the repo already uses it, uses requireAuth or an explicit public middleware
- **Quality snippet:** node/jest.quality.cjs
- **Dockerfile:** docker/Dockerfile.nestjs

A new service uses NestJS. Express stays only when the repo already uses it. Do not add `pom.xml`, a `.csproj`, or a second framework beside the one the repo has. React 19, TypeScript 5.9, and Vite 7 stay the UI.
