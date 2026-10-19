FROM eclipse-temurin:21-jdk-alpine AS build
RUN apk add --no-cache maven
WORKDIR /workspace
COPY pom.xml ./
COPY maven ./maven
COPY src ./src
RUN mvn -B -Dkit.container.build=true verify

FROM eclipse-temurin:21-jre-alpine
RUN adduser -D -h /app app
WORKDIR /app
COPY --from=build /workspace/target/*jar app.jar
USER app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
