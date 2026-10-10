package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class KitPresenceTest {

    @Test
    void kitAlreadyPresent_doesNotReinstall() {
        Path repo = Path.of("").toAbsolutePath().normalize();
        while (repo != null && !Files.isDirectory(repo.resolve(".agents-v0"))) {
            repo = repo.getParent();
        }
        assertTrue(Files.isDirectory(repo.resolve(".cursor")));
        assertTrue(Files.isDirectory(repo.resolve(".agents-v0")));
        assertTrue(Files.isRegularFile(
                repo.resolve("docs/agents-v0/milestones/p0-platform-skeleton.md")));
    }
}
