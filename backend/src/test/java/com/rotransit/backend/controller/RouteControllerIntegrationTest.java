package com.rotransit.backend.controller;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.otp.OtpException;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class RouteControllerIntegrationTest {

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
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('11111111-1111-1111-1111-111111111111', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void searchRoutesReturnsNormalizedResponse() throws Exception {
        JsonNode otpResponse = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 1320,
                        "transfers": 0,
                        "walkDistance": 410.7,
                        "legs": [
                          {
                            "mode": "WALK",
                            "from": {"name": "Start"},
                            "to": {"name": "Stop A"},
                            "startTime": 1000,
                            "endTime": 1200,
                            "distance": 120.5
                          },
                          {
                            "mode": "BUS",
                            "from": {"name": "Stop A"},
                            "to": {"name": "Stop B"},
                            "startTime": 1200,
                            "endTime": 2000,
                            "distance": 2000
                          },
                          {
                            "mode": "WALK",
                            "from": {"name": "Stop B"},
                            "to": {"name": "Hub"},
                            "startTime": 2000,
                            "endTime": 2100,
                            "distance": 80
                          },
                          {
                            "mode": "TROLLEYBUS",
                            "from": {"name": "Hub"},
                            "to": {"name": "End"},
                            "startTime": 2100,
                            "endTime": 2800,
                            "distance": 1500
                          }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(otpResponse);

        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "11111111-1111-1111-1111-111111111111")
                        .queryParam("origin", "45.650,25.610")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00")
                        .queryParam("passengerCount", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cityName").value("Brasov"))
                .andExpect(jsonPath("$.offset").value(0))
                .andExpect(jsonPath("$.limit").value(10))
                .andExpect(jsonPath("$.total").value(1))
                .andExpect(jsonPath("$.routes.length()").value(1))
                .andExpect(jsonPath("$.routes[0].durationSeconds").value(1320))
                .andExpect(jsonPath("$.routes[0].transfers").value(1))
                .andExpect(jsonPath("$.routes[0].estimatedPriceLei").value(5))
                .andExpect(jsonPath("$.routes[0].legs[0].mode").value("WALK"))
                .andExpect(jsonPath("$.routes[0].legs.length()").value(4));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('22222222-2222-2222-2222-222222222222', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void nearbyStopsReturnsList() throws Exception {
        JsonNode stop = objectMapper.readTree("""
                {"id":"STOP:1","name":"Livada Postei","lat":45.6451,"lon":25.5889}
                """);
        when(otpClient.findNearbyStops(anyString(), anyDouble(), anyDouble(), anyInt())).thenReturn(List.of(stop));

        mockMvc.perform(get("/api/stops/nearby")
                        .queryParam("cityId", "22222222-2222-2222-2222-222222222222")
                        .queryParam("lat", "45.645")
                        .queryParam("lon", "25.589")
                        .queryParam("radiusMeters", "500"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].stopId").value("STOP:1"))
                .andExpect(jsonPath("$[0].name").value("Livada Postei"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('13131313-1313-1313-1313-131313131313', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void searchRoutesReturnsFullItineraryListForClientSidePaging() throws Exception {
        JsonNode otpResponse = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {"duration": 1000, "transfers": 0, "walkDistance": 100, "legs":[{"mode":"BUS","from":{"name":"A"},"to":{"name":"B"},"startTime":1000,"endTime":2000,"distance":3000}]},
                      {"duration": 1100, "transfers": 1, "walkDistance": 120, "legs":[{"mode":"BUS","from":{"name":"A"},"to":{"name":"C"},"startTime":1000,"endTime":2300,"distance":3200}]},
                      {"duration": 1200, "transfers": 1, "walkDistance": 140, "legs":[{"mode":"BUS","from":{"name":"A"},"to":{"name":"D"},"startTime":1000,"endTime":2400,"distance":3300}]}
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(otpResponse);

        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "13131313-1313-1313-1313-131313131313")
                        .queryParam("origin", "45.650,25.610")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00")
                        .queryParam("offset", "1")
                        .queryParam("limit", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.offset").value(1))
                .andExpect(jsonPath("$.limit").value(1))
                .andExpect(jsonPath("$.total").value(3))
                .andExpect(jsonPath("$.hasMore").exists())
                .andExpect(jsonPath("$.routes.length()").value(1))
                .andExpect(jsonPath("$.routes[0].durationSeconds").value(1100));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM gtfs_stop_times",
            "DELETE FROM gtfs_trips",
            "DELETE FROM gtfs_routes",
            "DELETE FROM gtfs_stops",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('99999999-9999-9999-9999-999999999999', 'Brasov', 'Romania', 'http://otp:8080/otp')",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('99999999-9999-9999-9999-999999999999','STOP:1','Rulmentul',45.66,25.62)",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('99999999-9999-9999-9999-999999999999','STOP:1B','Rulmentul',45.66005,25.62005)",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('99999999-9999-9999-9999-999999999999','STOP:2','Piata Rulmentul',45.65,25.61)",
            "INSERT INTO gtfs_stops (city_id, stop_id, stop_name, stop_lat, stop_lon) VALUES ('99999999-9999-9999-9999-999999999999','STOP:3','Livada Postei',45.64,25.58)"
    })
    void stopSearchReturnsFilteredAndRankedMatches() throws Exception {
        mockMvc.perform(get("/api/stops/search")
                        .queryParam("cityId", "99999999-9999-9999-9999-999999999999")
                        .queryParam("q", "rul")
                        .queryParam("limit", "5"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].name").value("Rulmentul"))
                .andExpect(jsonPath("$[1].name").value("Piata Rulmentul"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('12121212-1212-1212-1212-121212121212', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void stopSearchReturnsBadRequestForBlankQuery() throws Exception {
        mockMvc.perform(get("/api/stops/search")
                        .queryParam("cityId", "12121212-1212-1212-1212-121212121212")
                        .queryParam("q", " ")
                        .queryParam("limit", "10"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void searchRoutesValidationFailsForMissingOrigin() throws Exception {
        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "33333333-3333-3333-3333-333333333333")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void searchRoutesValidationFailsForPassengerCountOutOfRange() throws Exception {
        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "33333333-3333-3333-3333-333333333333")
                        .queryParam("origin", "45.650,25.610")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00")
                        .queryParam("passengerCount", "0"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void nearbyStopsValidationFailsForInvalidCoordinates() throws Exception {
        mockMvc.perform(get("/api/stops/nearby")
                        .queryParam("cityId", "33333333-3333-3333-3333-333333333333")
                        .queryParam("lat", "145.0")
                        .queryParam("lon", "25.589")
                        .queryParam("radiusMeters", "500"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_ERROR"));
    }

    @Test
    void searchRoutesReturnsNotFoundWhenCityIsMissing() throws Exception {
        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
                        .queryParam("origin", "45.650,25.610")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("CITY_NOT_FOUND"));
    }

    @Test
    @Sql(statements = {
            "DELETE FROM saved_routes",
            "DELETE FROM users",
            "DELETE FROM cities",
            "INSERT INTO cities (id, name, country, otp_base_url) VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Brasov', 'Romania', 'http://otp:8080/otp')"
    })
    void searchRoutesReturnsBadGatewayWhenOtpFails() throws Exception {
        when(otpClient.searchRoutes(anyString(), any())).thenThrow(new OtpException("OTP down", null));

        mockMvc.perform(get("/api/routes/search")
                        .queryParam("cityId", "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
                        .queryParam("origin", "45.650,25.610")
                        .queryParam("destination", "45.640,25.600")
                        .queryParam("serviceDate", "2026-03-27")
                        .queryParam("serviceTime", "08:30:00"))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("OTP_UPSTREAM_ERROR"));
    }
}
