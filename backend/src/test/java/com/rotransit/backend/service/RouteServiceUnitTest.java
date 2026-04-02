package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class RouteServiceUnitTest {

    @Mock
    private CityRepository cityRepository;
    @Mock
    private OtpClient otpClient;
    @Mock
    private GtfsReadService gtfsReadService;

    private RouteService routeService;
    private final ObjectMapper objectMapper = new ObjectMapper();

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        routeService = new RouteService(cityRepository, otpClient, gtfsReadService);
    }

    @Test
    void searchRoutesReturnsEmptyWhenOtpHasNoItineraries() throws Exception {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode emptyPlan = objectMapper.readTree("""
                {"plan":{"itineraries":[]}}
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(emptyPlan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals("Brasov", result.cityName());
        assertTrue(result.routes().isEmpty());
    }

    @Test
    void searchRoutesHandlesMissingOptionalFieldsWithDefaults() throws Exception {
        UUID cityId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode missingFields = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      { "legs": [ { "from": {}, "to": {} } ] }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(missingFields);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(0L, result.routes().get(0).durationSeconds());
        assertEquals(0, result.routes().get(0).transfers());
        assertEquals("", result.routes().get(0).legs().get(0).mode());
    }

    @Test
    void nearbyStopsHandlesMalformedStopEntries() throws Exception {
        UUID cityId = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode malformed = objectMapper.readTree("""
                {"unexpected":"value"}
                """);
        when(otpClient.findNearbyStops(anyString(), anyDouble(), anyDouble(), anyInt()))
                .thenReturn(List.of(malformed));

        var stops = routeService.nearbyStops(cityId, 45.6, 25.6, 500);
        assertEquals(1, stops.size());
        assertEquals("", stops.get(0).stopId());
        assertEquals(0.0, stops.get(0).lat());
        assertEquals(0.0, stops.get(0).lon());
    }

    private RouteSearchQuery sampleQuery() {
        return new RouteSearchQuery(
                "45.650,25.610",
                "45.640,25.600",
                LocalDate.of(2026, 3, 27),
                LocalTime.of(8, 30),
                1,
                10
        );
    }

    private City mockCity(UUID cityId, String name, String otpUrl) {
        City city = org.mockito.Mockito.mock(City.class);
        when(city.getId()).thenReturn(cityId);
        when(city.getName()).thenReturn(name);
        when(city.getOtpBaseUrl()).thenReturn(otpUrl);
        return city;
    }
}
