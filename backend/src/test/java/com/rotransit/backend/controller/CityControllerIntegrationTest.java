package com.rotransit.backend.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class CityControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @Sql(statements = {
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES (RANDOM_UUID(), 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES (RANDOM_UUID(), 'Cluj-Napoca', 'Romania', 'http://otp-cluj:8080/otp')"
    })
    void getCitiesReturnsSortedDtoList() throws Exception {
        mockMvc.perform(get("/api/cities"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].name").value("Brasov"))
                .andExpect(jsonPath("$[0].country").value("Romania"))
                .andExpect(jsonPath("$[0].id").isNotEmpty())
                .andExpect(jsonPath("$[1].name").value("Cluj-Napoca"))
                .andExpect(jsonPath("$[1].country").value("Romania"))
                .andExpect(jsonPath("$[1].id").isNotEmpty())
                .andExpect(jsonPath("$[0].otpBaseUrl").doesNotExist());
    }
}
