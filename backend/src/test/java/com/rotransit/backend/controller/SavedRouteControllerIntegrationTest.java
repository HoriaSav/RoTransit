package com.rotransit.backend.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.otp.OtpClient;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class SavedRouteControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ObjectMapper objectMapper;
    @MockBean
    private OtpClient otpClient;

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('44444444-4444-4444-4444-444444444444', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void saveAndListRoutesForGuestUser() throws Exception {
        String payload = """
                {
                  "deviceUserId":"guest-device-1",
                  "cityId":"44444444-4444-4444-4444-444444444444",
                  "label":"Home to Work",
                  "routeMetadata":"{\\"routeId\\":\\"r1\\",\\"duration\\":1200}"
                }
                """;

        mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.label").value("Home to Work"))
                .andExpect(jsonPath("$.cityName").value("Brasov"));

        mockMvc.perform(get("/api/routes/saved")
                        .queryParam("deviceUserId", "guest-device-1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].label").value("Home to Work"))
                .andExpect(jsonPath("$[0].routeMetadata").isNotEmpty());
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('55555555-5555-5555-5555-555555555555', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void deleteSavedRouteWorks() throws Exception {
        String payload = """
                {
                  "deviceUserId":"guest-device-delete",
                  "cityId":"55555555-5555-5555-5555-555555555555",
                  "label":"Delete me",
                  "routeMetadata":"{\\"routeId\\":\\"r2\\"}"
                }
                """;

        String response = mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();

        String routeId = objectMapper.readTree(response).path("id").asText();

        mockMvc.perform(delete("/api/routes/saved/" + routeId)
                        .queryParam("deviceUserId", "guest-device-delete"))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/routes/saved")
                        .queryParam("deviceUserId", "guest-device-delete"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    void saveRouteReturnsBadRequestWhenDeviceUserIdMissing() throws Exception {
        String payload = """
                {
                  "deviceUserId":"",
                  "cityId":"55555555-5555-5555-5555-555555555555",
                  "label":"Invalid",
                  "routeMetadata":"{\\"routeId\\":\\"r2\\"}"
                }
                """;

        mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_ERROR"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('66666666-6666-6666-6666-666666666666', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void deleteSavedRouteWithDifferentDeviceReturnsNotFound() throws Exception {
        String payload = """
                {
                  "deviceUserId":"owner-device",
                  "cityId":"66666666-6666-6666-6666-666666666666",
                  "label":"Owner route",
                  "routeMetadata":"{\\"routeId\\":\\"r3\\"}"
                }
                """;

        String response = mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();

        String routeId = objectMapper.readTree(response).path("id").asText();

        mockMvc.perform(delete("/api/routes/saved/" + routeId)
                        .queryParam("deviceUserId", "other-device"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("SAVED_ROUTE_NOT_FOUND"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('77777777-7777-7777-7777-777777777777', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('88888888-8888-8888-8888-888888888888', 'Cluj', 'Romania', 'http://otp:8080/otp')"
    })
    void getSavedRoutesCanFilterByCityId() throws Exception {
        String cityOnePayload = """
                {
                  "deviceUserId":"city-filter-device",
                  "cityId":"77777777-7777-7777-7777-777777777777",
                  "label":"Brasov route",
                  "routeMetadata":"{\\"routeId\\":\\"r-city-1\\"}"
                }
                """;
        String cityTwoPayload = """
                {
                  "deviceUserId":"city-filter-device",
                  "cityId":"88888888-8888-8888-8888-888888888888",
                  "label":"Cluj route",
                  "routeMetadata":"{\\"routeId\\":\\"r-city-2\\"}"
                }
                """;

        mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(cityOnePayload))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(cityTwoPayload))
                .andExpect(status().isCreated());

        mockMvc.perform(get("/api/routes/saved")
                        .queryParam("deviceUserId", "city-filter-device")
                        .queryParam("cityId", "77777777-7777-7777-7777-777777777777"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].cityName").value("Brasov"));
    }

    @Test
    void deleteNonExistingSavedRouteReturnsNotFound() throws Exception {
        mockMvc.perform(delete("/api/routes/saved/99999999-9999-9999-9999-999999999999")
                        .queryParam("deviceUserId", "unknown-device"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("SAVED_ROUTE_NOT_FOUND"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('99999999-aaaa-bbbb-cccc-111111111111', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void validateSavedRouteReturnsValidWhenStrictMatchExists() throws Exception {
        String payload = """
                {
                  "deviceUserId":"validate-device",
                  "cityId":"99999999-aaaa-bbbb-cccc-111111111111",
                  "label":"Validation route",
                  "routeMetadata":"{\\"durationSeconds\\":1200,\\"transfers\\":0,\\"walkDistanceMeters\\":200,\\"legs\\":[{\\"mode\\":\\"BUS\\",\\"fromName\\":\\"Rulmentul\\",\\"toName\\":\\"Livada Postei\\",\\"startTime\\":1000,\\"endTime\\":2000,\\"distance\\":3000.0}]}"
                }
                """;
        String saveResponse = mockMvc.perform(post("/api/routes/save")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(payload))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String routeId = objectMapper.readTree(saveResponse).path("id").asText();

        JsonNode otpResponse = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 1200,
                        "transfers": 0,
                        "walkDistance": 200,
                        "legs": [
                          {
                            "mode": "BUS",
                            "from": {"name": "Rulmentul"},
                            "to": {"name": "Livada Postei"},
                            "startTime": 1000,
                            "endTime": 2000,
                            "distance": 3000
                          }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(otpResponse);

        mockMvc.perform(get("/api/routes/saved/" + routeId + "/validate")
                        .queryParam("deviceUserId", "validate-device")
                        .queryParam("serviceDate", "2026-04-01")
                        .queryParam("serviceTime", "08:30:00"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.isValid").value(true))
                .andExpect(jsonPath("$.reason").value("MATCH_FOUND"));
    }
}
