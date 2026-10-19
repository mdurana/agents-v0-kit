package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class KitPresenceTest {

    @Test
    void kitAlreadyPresent_doesNotReinstall() {
        if (Boolean.getBoolean("kit.container.build")) {
            assertTrue(Files.isRegularFile(Path.of("pom.xml")));
            assertTrue(Files.isRegularFile(Path.of("maven/checkstyle.xml")));
            return;
        }
        Path repo = Path.of("").toAbsolutePath().normalize();
        while (repo != null && !Files.isDirectory(repo.resolve(".agents-v0"))) {
            repo = repo.getParent();
        }
        assertNotNull(repo, "repo root with .agents-v0");
        assertTrue(Files.isDirectory(repo.resolve(".cursor")));
        assertTrue(Files.isDirectory(repo.resolve(".agents-v0")));
        assertTrue(Files.isRegularFile(
                repo.resolve("docs/agents-v0/milestones/p0-platform-skeleton.md")));
    }
}
