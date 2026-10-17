# Stack pack

- **Id:** java
- **Service skill:** implement-service
- **Rules:** backend.mdc, vapt.mdc
- **Skills:** implement-service, implement-bff, scaffold-service
- **Data stores:** PostgreSQL 15
- **Backend:** Java 21, Spring Boot 4.1.1, Maven wrapper
- **HTTP:** Spring MVC, embedded Tomcat 11.0.26
- **Security:** Spring Security
- **Database:** PostgreSQL 15, Flyway
- **Tests:** JUnit (spring-boot-starter-test), ArchUnit 1.4.2, H2 test profile
- **Local run:** Compose API :8080, UI :8081, postgres:15-alpine
- **Backend verify:** cd app/backend && ./mvnw -B clean verify
- **Backend verify (fast):** cd app/backend && ./mvnw -B clean verify -P!ci-security
- **Coverage:** target/site/jacoco/jacoco.xml
- **Tests report:** target/surefire-reports/TEST-*.xml
- **Auth:** @PreAuthorize on every mapping (@PreAuthorize("permitAll()") for public routes)

Pinned versions stay on this list. The pattern ADR may choose topology, sync versus events, this data store, and a brownfield migration approach. React 19, TypeScript 5.9, and Vite 7 stay the UI.
