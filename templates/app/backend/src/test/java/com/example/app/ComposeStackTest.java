package com.example.app;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComposeStackTest {

    @Test
    void composeFileDeclaresAppService() throws Exception {
        if (Boolean.getBoolean("kit.container.build")) {
            assertTrue(Files.isRegularFile(Path.of("pom.xml")));
            return;
        }
        Path repo = Path.of("").toAbsolutePath().normalize();
        while (repo != null && !Files.isDirectory(repo.resolve(".agents-v0"))) {
            repo = repo.getParent();
        }
        assertNotNull(repo, "repo root with .agents-v0");
        assertTrue(Files.isRegularFile(repo.resolve("app/backend/Dockerfile")), "app/backend/Dockerfile must exist");
        boolean hasFrontend = Files.isDirectory(repo.resolve("app/frontend"));
        if (hasFrontend) {
            assertTrue(Files.isRegularFile(repo.resolve("app/frontend/Dockerfile")), "app/frontend/Dockerfile must exist");
        }
        Path composeFile = repo.resolve("docker-compose.yml");
        assertTrue(Files.isRegularFile(composeFile), "docker-compose.yml must exist at repo root");
        String compose = Files.readString(composeFile);
        assertTrue(compose.contains("api:"), "docker-compose.yml must declare api service");
        assertTrue(compose.contains("context: ./app/backend"), "api service must build ./app/backend");
        assertTrue(compose.contains("DB_URL: jdbc:postgresql://db:5432/app"), "api service must wire PostgreSQL DB_URL");
        assertTrue(compose.contains("db:"), "docker-compose.yml must declare db service");
        assertTrue(compose.contains("postgres:15-alpine"), "db service must use postgres:15-alpine");
        assertTrue(compose.contains("pg_isready"), "db service must configure pg_isready healthcheck");
        if (hasFrontend) {
            assertTrue(compose.contains("ui:"), "docker-compose.yml must declare ui service");
            assertTrue(compose.contains("context: ./app/frontend"), "ui service must build ./app/frontend");
        }
        verifyRunningOrSmoke(repo, hasFrontend);
    }

    private void verifyRunningOrSmoke(Path repo, boolean hasFrontend) throws Exception {
        String apiPort = System.getenv().getOrDefault("APP_PORT", "8080");
        String uiPort = System.getenv().getOrDefault("UI_PORT", "8081");
        HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
        HttpResponse<String> healthResp = probe(client, "http://localhost:" + apiPort + "/health");
        if (healthResp != null) {
            assertEquals(200, healthResp.statusCode(), "/health must return HTTP 200");
            assertTrue(healthResp.body().contains("UP"), "/health payload must report UP");
            if (hasFrontend) {
                HttpResponse<String> uiResp = probe(client, "http://localhost:" + uiPort + "/");
                if (uiResp != null) {
                    assertEquals(200, uiResp.statusCode(), "UI root must return HTTP 200");
                }
            }
            return;
        }
        boolean smokeRequested = "1".equals(System.getenv("COMPOSE_SMOKE")) || Boolean.getBoolean("compose.smoke");
        if (smokeRequested) {
            Process proc = new ProcessBuilder("sh", ".agents-v0/scripts/run-local-container.sh", "--smoke")
                    .directory(repo.toFile())
                    .inheritIO()
                    .start();
            assertEquals(0, proc.waitFor(), "run-local-container.sh --smoke must succeed");
        }
    }

    private HttpResponse<String> probe(HttpClient client, String url) {
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(2))
                    .GET()
                    .build();
            return client.send(req, HttpResponse.BodyHandlers.ofString());
        } catch (Exception ignored) {
            return null;
        }
    }
}
