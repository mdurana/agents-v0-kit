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
@RequestMapping("/api/v1/funding-cost-exports")
public class FundingCostExportController {

    private final Map<String, String> recipeByPeriod = new ConcurrentHashMap<>();

    @PostMapping
    @PreAuthorize("permitAll()")
    public ResponseEntity<Object> createFundingCostExport(@RequestBody Map<String, String> payload) {
        String period = payload == null ? null : payload.get("period");
        String recipeCode = payload == null ? null : payload.get("recipeCode");
        if (period == null || period.isBlank() || recipeCode == null || recipeCode.isBlank()) {
            ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                    HttpStatus.BAD_REQUEST, "Period and recipeCode must not be blank");
            problem.setTitle("Invalid Funding Cost Export Request");
            return ResponseEntity.badRequest().body(problem);
        }
        recipeByPeriod.put(period.trim(), recipeCode.trim());
        Map<String, Object> body = Map.of(
                "period", period.trim(),
                "recipeCode", recipeCode.trim(),
                "status", "BALANCED");
        return ResponseEntity.status(HttpStatus.CREATED).body(body);
    }

    @GetMapping("/{period}")
    @PreAuthorize("permitAll()")
    public ResponseEntity<Map<String, Object>> getFundingCostExport(@PathVariable String period) {
        String recipeCode = recipeByPeriod.get(period);
        if (recipeCode == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(Map.of(
                "period", period,
                "recipeCode", recipeCode,
                "status", "BALANCED"));
    }
}
