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
@RequestMapping("/api/v1/lookup-tables")
public class LookupTableController {

    private final Map<String, Integer> versionsByCode = new ConcurrentHashMap<>();

    @PostMapping
    @PreAuthorize("permitAll()")
    public ResponseEntity<Object> createLookupTable(@RequestBody Map<String, String> payload) {
        String code = payload == null ? null : payload.get("code");
        if (code == null || code.isBlank()) {
            ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                    HttpStatus.BAD_REQUEST, "Lookup table code must not be blank");
            problem.setTitle("Invalid Lookup Table");
            return ResponseEntity.badRequest().body(problem);
        }
        int nextVersion = versionsByCode.merge(code.trim(), 1, Integer::sum);
        Map<String, Object> body = Map.of(
                "code", code.trim(),
                "versionNo", nextVersion,
                "status", "ACTIVE");
        return ResponseEntity.status(HttpStatus.CREATED).body(body);
    }

    @GetMapping("/{code}")
    @PreAuthorize("permitAll()")
    public ResponseEntity<Map<String, Object>> getLookupTable(@PathVariable String code) {
        Integer version = versionsByCode.get(code);
        if (version == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(Map.of(
                "code", code,
                "versionNo", version,
                "status", "ACTIVE"));
    }
}
