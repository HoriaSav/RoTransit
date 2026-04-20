package com.rotransit.backend.otp;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import org.mockito.ArgumentMatchers;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.service.RouteSearchQuery;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

class OtpHttpClientTest {

    @Mock
    private RestTemplate restTemplate;

    private OtpHttpClient otpHttpClient;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        otpHttpClient = new OtpHttpClient(restTemplate);
    }

    @Test
    void searchRoutesReturnsEmptyPlanWhenRestAndGraphQlFail() {
        when(restTemplate.getForEntity(anyString(), eq(JsonNode.class))).thenThrow(new RestClientException("boom"));
        when(restTemplate.postForEntity(anyString(), any(), eq(JsonNode.class))).thenThrow(new RestClientException("boom"));

        JsonNode result = otpHttpClient.searchRoutes("http://localhost:8080/otp", sampleQuery());

        assertTrue(result.path("plan").path("itineraries").isArray());
        assertEquals(0, result.path("plan").path("itineraries").size());
    }

    @Test
    void searchRoutesFallsBackToRelaxedWhenStrictPlanEmpty() throws Exception {
        JsonNode emptyPlan = objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        JsonNode withItin = objectMapper.readTree(
                "{\"plan\":{\"itineraries\":[{\"duration\":1200,\"walkDistance\":400}]}}");

        when(restTemplate.getForEntity(
                        ArgumentMatchers.<String>argThat(
                                url -> url != null && url.contains("maxWalkDistance")),
                        eq(JsonNode.class)))
                .thenReturn(new ResponseEntity<>(emptyPlan, HttpStatus.OK));
        when(restTemplate.getForEntity(
                        ArgumentMatchers.<String>argThat(
                                url -> url != null && !url.contains("maxWalkDistance")),
                        eq(JsonNode.class)))
                .thenReturn(new ResponseEntity<>(withItin, HttpStatus.OK));

        JsonNode result = otpHttpClient.searchRoutes("http://localhost:8080/otp", sampleQuery());

        assertEquals(1, result.path("plan").path("itineraries").size());
    }

    @Test
    void findNearbyStopsFallsBackToGraphQlWhenIndexEndpointFails() throws Exception {
        when(restTemplate.getForEntity(anyString(), eq(JsonNode.class))).thenThrow(new RestClientException("index down"));
        when(restTemplate.postForEntity(anyString(), any(), eq(JsonNode.class)))
                .thenReturn(new ResponseEntity<>(graphQlStopsResponse(), HttpStatus.OK));

        List<JsonNode> stops = otpHttpClient.findNearbyStops("http://localhost:8080/otp", 45.64, 25.58, 300);

        assertEquals(1, stops.size());
        assertEquals("STOP:1", stops.get(0).path("id").asText());
        assertEquals("Livada", stops.get(0).path("name").asText());
    }

    private RouteSearchQuery sampleQuery() {
        return new RouteSearchQuery(
                "45.650,25.610",
                "45.640,25.600",
                LocalDate.of(2026, 4, 2),
                LocalTime.of(8, 30),
                2,
                30
        );
    }

    private JsonNode graphQlStopsResponse() throws Exception {
        return objectMapper.readTree("""
                {
                  "data": {
                    "stopsByRadius": {
                      "edges": [
                        {
                          "node": {
                            "stop": {
                              "gtfsId": "STOP:1",
                              "name": "Livada",
                              "lat": 45.64,
                              "lon": 25.58
                            }
                          }
                        }
                      ]
                    }
                  }
                }
                """);
    }
}
