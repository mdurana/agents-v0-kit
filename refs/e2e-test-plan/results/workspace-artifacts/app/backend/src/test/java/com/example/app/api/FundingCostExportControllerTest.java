package com.example.app.api;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class FundingCostExportControllerTest {

    private final MockMvc mockMvc;

    @Autowired
    FundingCostExportControllerTest(MockMvc mockMvc) {
        this.mockMvc = mockMvc;
    }

    @Test
    void createAndRetrieveFundingCostExport_validPayload_returnsCreatedAndOk() throws Exception {
        mockMvc.perform(post("/api/v1/funding-cost-exports")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"period\":\"2026-10\",\"recipeCode\":\"COMMISSION_CALC_V1\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.period").value("2026-10"))
                .andExpect(jsonPath("$.status").value("BALANCED"));

        mockMvc.perform(get("/api/v1/funding-cost-exports/2026-10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.period").value("2026-10"))
                .andExpect(jsonPath("$.status").value("BALANCED"));
    }

    @Test
    void createFundingCostExport_blankPeriod_returnsBadRequestProblemDetail() throws Exception {
        mockMvc.perform(post("/api/v1/funding-cost-exports")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"period\":\"\",\"recipeCode\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));

        mockMvc.perform(get("/api/v1/funding-cost-exports/2099-12"))
                .andExpect(status().isNotFound());
    }
}
