package com.example.app.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noFields;

import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import org.springframework.beans.factory.annotation.Autowired;

@AnalyzeClasses(packages = "com.example.app")
class LayerRulesTest {

    @ArchTest
    static final ArchRule domainIsIndependentOfWeb =
            noClasses()
                    .that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("..web..", "..controller..")
                    .because("domain must not depend on web layers")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule controllersDoNotUseEntities =
            noClasses()
                    .that().resideInAPackage("..controller..")
                    .should().dependOnClassesThat().resideInAPackage("..entity..")
                    .because("DTOs only at the edge")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule noFieldInjection =
            noFields()
                    .should().beAnnotatedWith(Autowired.class)
                    .because("constructor injection is required");
}
