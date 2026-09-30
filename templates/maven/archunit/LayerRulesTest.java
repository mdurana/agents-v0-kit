/*
 * ArchUnit layer-rules starter — move to src/test/java/<base-package>/architecture/
 * and set the package and @AnalyzeClasses value below. Add the test dependency:
 *   com.tngtech.archunit:archunit-junit5 (test scope)
 * The Build gate expects layer boundaries enforced by these rules where wired
 * (workflow-orchestration.mdc; quality-and-testing.mdc — Architecture tests).
 */
package com.example.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noFields;

import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import org.springframework.beans.factory.annotation.Autowired;

@AnalyzeClasses(packages = "com.example")
class LayerRulesTest {

  @ArchTest
  static final ArchRule domainIsIndependentOfWeb =
      noClasses()
          .that().resideInAPackage("..domain..")
          .should().dependOnClassesThat().resideInAnyPackage("..web..", "..controller..")
          .because("domain must not depend on web layers (architecture-and-diagrams.mdc)");

  @ArchTest
  static final ArchRule controllersDoNotUseEntities =
      noClasses()
          .that().resideInAPackage("..controller..")
          .should().dependOnClassesThat().resideInAPackage("..entity..")
          .because("DTOs only at the edge (api-and-events.mdc)");

  @ArchTest
  static final ArchRule noFieldInjection =
      noFields()
          .should().beAnnotatedWith(Autowired.class)
          .because("constructor injection is required (java-spring-backend.mdc)");
}
