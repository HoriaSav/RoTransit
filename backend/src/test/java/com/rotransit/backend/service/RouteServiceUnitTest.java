package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.concurrent.Executor;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.NearbyStopResponse;
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

    /** Runs resolve tasks on the calling thread so OTP mock order stays deterministic. */
    private static final Executor SYNC_RESOLVE_EXECUTOR = r -> r.run();

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        routeService = new RouteService(cityRepository, otpClient, gtfsReadService, SYNC_RESOLVE_EXECUTOR);
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
    void searchRoutesDerivesTransfersFromMultipleTransitLegs() throws Exception {
        UUID cityId = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 2400,
                        "transfers": 0,
                        "walkDistance": 200,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 1100, "distance": 50 },
                          { "mode": "BUS", "from": {}, "to": {}, "startTime": 1100, "endTime": 2000, "distance": 3000 },
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 2000, "endTime": 2100, "distance": 80 },
                          { "mode": "TRAM", "from": {}, "to": {}, "startTime": 2100, "endTime": 3000, "distance": 2500 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(1, result.routes().get(0).transfers());
    }

    @Test
    void searchRoutesSingleTransitLegYieldsZeroTransfers() throws Exception {
        UUID cityId = UUID.fromString("f0f0f0f0-f0f0-f0f0-f0f0-f0f0f0f0f0f0");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 1200,
                        "walkDistance": 100,
                        "legs": [
                          { "mode": "BUS", "from": {}, "to": {}, "startTime": 1000, "endTime": 2000, "distance": 3000 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(0, result.routes().get(0).transfers());
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

    @Test
    void searchStopsDedupesSameNameNearbyStops() {
        UUID cityId = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("a", "Rulmentul", 45.66, 25.62),
                new NearbyStopResponse("b", "Rulmentul", 45.66005, 25.62005),
                new NearbyStopResponse("c", "Piata Rulmentul", 45.65, 25.61));
        when(gtfsReadService.searchStops(eq(cityId), eq("rul"), anyInt())).thenReturn(raw);

        var out = routeService.searchStops(cityId, "rul", 10, 45.66, 25.62);
        assertEquals(2, out.size());
        assertEquals("Rulmentul", out.get(0).name());
        assertEquals("Piata Rulmentul", out.get(1).name());
    }

    @Test
    void nearbyStopsDedupesDuplicateNamesNearQueryPoint() throws Exception {
        UUID cityId = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode s1 = objectMapper.readTree("""
                {"id":"otp-1","name":"Rulmentul","lat":45.66,"lon":25.62}
                """);
        JsonNode s2 = objectMapper.readTree("""
                {"id":"otp-2","name":"Rulmentul","lat":45.66005,"lon":25.62005}
                """);
        when(otpClient.findNearbyStops(anyString(), anyDouble(), anyDouble(), anyInt()))
                .thenReturn(List.of(s1, s2));

        var stops = routeService.nearbyStops(cityId, 45.66, 25.62, 500);
        assertEquals(1, stops.size());
        assertEquals("otp-1", stops.get(0).stopId());
    }

    @Test
    void resolveDestinationSkipsOtpWhenSingleCandidate() {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina")))
                .thenReturn(List.of(new NearbyStopResponse("only", "Doina", 45.1, 25.1)));

        var out = routeService.resolveDestinationStopForRoute(
                cityId,
                "45.65,25.65",
                "Doina",
                LocalDate.of(2026, 4, 3),
                LocalTime.of(18, 0));

        assertEquals("only", out.stopId());
        verify(otpClient, never()).searchRoutes(anyString(), any());
    }

    @Test
    void resolveDestinationPicksCandidateWithFewerTransfers() throws Exception {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        List<NearbyStopResponse> cands = List.of(
                new NearbyStopResponse("near", "Doina", 45.641, 25.65),
                new NearbyStopResponse("far", "Doina", 45.66, 25.65));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina"))).thenReturn(cands);

        JsonNode worse = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":2000,"walkDistance":100,"legs":[
                  {"mode":"WALK"},{"mode":"BUS"},{"mode":"WALK"},{"mode":"BUS"},{"mode":"WALK"}
                ]}]}}
                """);
        JsonNode better = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":5000,"walkDistance":400,"legs":[
                  {"mode":"WALK"},{"mode":"BUS"},{"mode":"WALK"}
                ]}]}}
                """);
        when(otpClient.searchRoutes(eq("http://otp:8080/otp"), any())).thenAnswer(inv -> {
            RouteSearchQuery q = inv.getArgument(1);
            String dest = q.destination();
            if (dest.contains("45.641")) {
                return worse;
            }
            if (dest.contains("45.66")) {
                return better;
            }
            return objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        });

        var out = routeService.resolveDestinationStopForRoute(
                cityId,
                "45.65,25.65",
                "Doina",
                LocalDate.of(2026, 4, 3),
                LocalTime.of(18, 0));

        assertEquals("far", out.stopId());
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
