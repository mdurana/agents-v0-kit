package com.example.app.api;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class LookupTableControllerTest {

    private final MockMvc mockMvc;

    @Autowired
    LookupTableControllerTest(MockMvc mockMvc) {
        this.mockMvc = mockMvc;
    }

    @Test
    @WithMockUser(roles = "FINANCE_OPERATOR")
    void createAndRetrieveLookupTable_validPayload_returnsCreatedAndOk() throws Exception {
        mockMvc.perform(post("/api/v1/lookup-tables")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"PARTNER_RATE_GRID\",\"name\":\"Partner Rate Grid\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.code").value("PARTNER_RATE_GRID"))
                .andExpect(jsonPath("$.versionNo").value(1));

        mockMvc.perform(get("/api/v1/lookup-tables/PARTNER_RATE_GRID"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("PARTNER_RATE_GRID"))
                .andExpect(jsonPath("$.status").value("ACTIVE"));
    }

    @Test
    @DisplayName("AC-3: reject blank lookup table code with RFC 7807 Problem Details")
    @WithMockUser(roles = "FINANCE_OPERATOR")
    void ac3_createLookupTable_blankCode_returnsBadRequestProblemDetail() throws Exception {
        mockMvc.perform(post("/api/v1/lookup-tables")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));

        mockMvc.perform(get("/api/v1/lookup-tables/MISSING_CODE"))
                .andExpect(status().isNotFound());
    }
}
