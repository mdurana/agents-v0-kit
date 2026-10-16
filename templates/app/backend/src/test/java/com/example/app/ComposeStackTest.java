package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComposeStackTest {

    @Test
    void composeFileDeclaresAppService() throws Exception {
        Path repo = Path.of("").toAbsolutePath().normalize();
        while (repo != null && !Files.isDirectory(repo.resolve(".agents-v0"))) {
            repo = repo.getParent();
        }
        assertNotNull(repo, "repo root with .agents-v0");
        assertTrue(Files.isRegularFile(repo.resolve("app/backend/Dockerfile")));
        boolean hasFrontend = Files.isDirectory(repo.resolve("app/frontend"));
        if (hasFrontend) {
            assertTrue(Files.isRegularFile(repo.resolve("app/frontend/Dockerfile")));
        }
        Path composeFile = repo.resolve("docker-compose.yml");
        if (!Files.isRegularFile(composeFile)) {
            return;
        }
        String compose = Files.readString(composeFile);
        if (compose.contains("context: ./app/")) {
            assertTrue(compose.contains("context: ./app/backend"));
            if (hasFrontend) {
                assertTrue(compose.contains("context: ./app/frontend"));
            }
        }
    }
}
