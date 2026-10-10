package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ComposeStackTest {

    @Test
    void composeFileDeclaresAppService() throws Exception {
        Path repo = Path.of("").toAbsolutePath().normalize();
        while (repo != null && !Files.isDirectory(repo.resolve(".agents-v0"))) {
            repo = repo.getParent();
        }
        String compose = Files.readString(repo.resolve("docker-compose.yml"));
        assertTrue(compose.contains("context: ./app/backend"));
        assertTrue(compose.contains("context: ./app/frontend"));
        assertTrue(Files.isRegularFile(repo.resolve("app/backend/Dockerfile")));
        assertTrue(Files.isRegularFile(repo.resolve("app/frontend/Dockerfile")));
    }
}
