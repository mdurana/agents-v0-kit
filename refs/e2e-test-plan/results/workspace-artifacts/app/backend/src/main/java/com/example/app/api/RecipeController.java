package com.example.app.api;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/recipes")
public class RecipeController {

    private final Map<String, String> lookupByRecipe = new ConcurrentHashMap<>();

    @PostMapping
    @PreAuthorize("permitAll()")
    public ResponseEntity<Object> createRecipe(@RequestBody Map<String, String> payload) {
        String code = payload == null ? null : payload.get("code");
        String lookupCode = payload == null ? null : payload.get("lookupCode");
        if (code == null || code.isBlank() || lookupCode == null || lookupCode.isBlank()) {
            ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                    HttpStatus.BAD_REQUEST, "Recipe code and lookupCode must not be blank");
            problem.setTitle("Invalid Transformation Recipe");
            return ResponseEntity.badRequest().body(problem);
        }
        lookupByRecipe.put(code.trim(), lookupCode.trim());
        Map<String, Object> body = Map.of(
                "code", code.trim(),
                "lookupCode", lookupCode.trim(),
                "versionNo", 1,
                "status", "ACTIVE");
        return ResponseEntity.status(HttpStatus.CREATED).body(body);
    }

    @GetMapping("/{code}")
    @PreAuthorize("permitAll()")
    public ResponseEntity<Map<String, Object>> getRecipe(@PathVariable String code) {
        String lookupCode = lookupByRecipe.get(code);
        if (lookupCode == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(Map.of(
                "code", code,
                "lookupCode", lookupCode,
                "versionNo", 1,
                "status", "ACTIVE"));
    }
}
