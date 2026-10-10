package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class QualityPluginsTest {

    @Test
    void qualityPluginsBoundToVerify() throws Exception {
        String pom = Files.readString(Path.of("pom.xml"));
        assertTrue(pom.contains("jacoco-maven-plugin"));
        assertTrue(pom.contains("maven-checkstyle-plugin"));
        assertTrue(pom.contains("spotbugs-maven-plugin"));
        assertTrue(pom.contains("dependency-check-maven"));
        assertTrue(pom.contains("<phase>verify</phase>"));
    }
}
