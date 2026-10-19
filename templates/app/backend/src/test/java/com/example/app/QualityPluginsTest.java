package com.example.app;

import java.nio.file.Files;
import java.nio.file.Path;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
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
        assertTrue(
                Files.isRegularFile(Path.of("maven/checkstyle.xml"))
                        || Files.isRegularFile(Path.of("../../maven/checkstyle.xml")),
                "checkstyle.xml must be reachable from app/backend");
        assertTrue(
                Files.isRegularFile(Path.of("maven/dependency-check-suppressions.xml"))
                        || Files.isRegularFile(Path.of("../../maven/dependency-check-suppressions.xml")),
                "dependency-check-suppressions.xml must be reachable from app/backend");
        Path dockerfile = Path.of("Dockerfile");
        if (Files.isRegularFile(dockerfile)) {
            String df = Files.readString(dockerfile);
            assertTrue(df.contains("COPY maven ./maven"), "Dockerfile must copy maven/ config directory");
            assertTrue(df.contains("verify"), "Dockerfile must run the Maven verify lifecycle");
            assertFalse(df.contains("-DskipTests package"), "Dockerfile must not bypass verify with -DskipTests package");
        }
    }
}
