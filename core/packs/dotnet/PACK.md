# Stack pack

- **Id:** dotnet
- **Service skill:** implement-aspnet-service
- **Rules:** aspnet-backend.mdc, vapt-aspnet.mdc
- **Skills:** implement-aspnet-service
- **Data stores:** PostgreSQL 15, SQL Server
- **Backend:** .NET 10, ASP.NET Core, EF Core
- **HTTP:** ASP.NET Core MVC / minimal APIs on Kestrel
- **Security:** ASP.NET Core authentication, [Authorize] policies
- **Database:** PostgreSQL 15, EF Core migrations. SQL Server when the ADR names it
- **Tests:** xUnit, coverlet
- **Local run:** Compose API :8080, UI :8081, postgres:15-alpine
- **Backend verify:** dotnet test --logger "trx;LogFileName=test-results.trx" --results-directory TestResults --collect:"XPlat Code Coverage"
- **Backend verify (fast):** dotnet test
- **Coverage:** coverage.cobertura.xml
- **Tests report:** TestResults/**/*.trx
- **Auth:** [Authorize] or [AllowAnonymous] on every action

Do not add a Maven module, `pom.xml`, or Flyway. Pinned versions stay on this list. The pattern ADR may choose topology, sync versus events, PostgreSQL or SQL Server, and a brownfield migration approach. React 19, TypeScript 5.9, and Vite 7 stay the UI.
