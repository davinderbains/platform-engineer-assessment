package com.gertidokaj.geocento.java_full_stack_assessment.controller;

import com.gertidokaj.geocento.java_full_stack_assessment.config.TestSecurityConfig;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = "FAULT_ERROR_RATE=1")
@AutoConfigureMockMvc
@Import(TestSecurityConfig.class)
class FaultInjectionTest {

    private static final String SEARCH_BODY = """
            {
              "type": "Polygon",
              "coordinates": [[
                [-0.5, 51.0], [0.5, 51.0], [0.5, 52.0],
                [-0.5, 52.0], [-0.5, 51.0]
              ]]
            }
            """;

    @Autowired
    private MockMvc mockMvc;

    @Test
    void searchByAoi_withValidJwt_returnsInjected500() throws Exception {
        mockMvc.perform(post("/api/products/search")
                        .with(jwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(SEARCH_BODY))
                .andExpect(status().isInternalServerError())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.error").value("Injected failure (FAULT_ERROR_RATE)"));
    }
}
