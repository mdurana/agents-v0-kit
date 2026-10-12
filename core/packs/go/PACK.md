# Stack pack

- **Id:** go
- **Service skill:** implement-go-service
- **Rules:** go-backend.mdc, vapt-go.mdc
- **Skills:** implement-go-service, implement-go-bff, scaffold-go-service
- **Data stores:** PostgreSQL 15
- **Backend:** Go 1.26, Gin
- **HTTP:** Gin handlers
- **Security:** Gin auth middleware
- **Database:** PostgreSQL 15, golang-migrate
- **Tests:** go test
- **Local run:** Compose API :8080, UI :8081, postgres:15-alpine
- **Backend verify:** go test ./... -coverprofile=coverage.out -json > go-test.json
- **Backend verify (fast):** go test ./...
- **Coverage:** coverage.out
- **Tests report:** go-test.json
- **Auth:** auth middleware on every route, or an explicit public registration
- **Quality snippet:** go/Makefile
- **Dockerfile:** docker/Dockerfile.go

A new service uses Gin. chi or `net/http` stays only when the repo already uses it. Do not add `pom.xml` or a second router. React 19, TypeScript 5.9, and Vite 7 stay the UI.
