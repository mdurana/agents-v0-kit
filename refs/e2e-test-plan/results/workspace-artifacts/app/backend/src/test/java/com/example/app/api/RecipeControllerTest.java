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
class RecipeControllerTest {

    private final MockMvc mockMvc;

    @Autowired
    RecipeControllerTest(MockMvc mockMvc) {
        this.mockMvc = mockMvc;
    }

    @Test
    void createAndRetrieveRecipe_validPayload_returnsCreatedAndOk() throws Exception {
        mockMvc.perform(post("/api/v1/recipes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"COMMISSION_CALC_V1\",\"lookupCode\":\"PARTNER_RATE_GRID\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.code").value("COMMISSION_CALC_V1"))
                .andExpect(jsonPath("$.lookupCode").value("PARTNER_RATE_GRID"))
                .andExpect(jsonPath("$.versionNo").value(1));

        mockMvc.perform(get("/api/v1/recipes/COMMISSION_CALC_V1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("COMMISSION_CALC_V1"))
                .andExpect(jsonPath("$.lookupCode").value("PARTNER_RATE_GRID"));
    }

    @Test
    void createRecipe_blankFields_returnsBadRequestProblemDetail() throws Exception {
        mockMvc.perform(post("/api/v1/recipes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"\",\"lookupCode\":\"\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));

        mockMvc.perform(get("/api/v1/recipes/MISSING_RECIPE"))
                .andExpect(status().isNotFound());
    }
}
