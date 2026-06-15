package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
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
    void searchRoutesUsesShiftedDepartureTimesAndDedupesRepeatedPlans() throws Exception {
        UUID cityId = UUID.fromString("d4d4d4d4-d4d4-d4d4-d4d4-d4d4d4d4d4d4");
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
                          { "mode": "BUS", "route": {"gtfsId": "R1"}, "from": {}, "to": {}, "startTime": 1000, "endTime": 2000, "distance": 3000 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);
        JsonNode emptyPlan = objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(emptyPlan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);

        ArgumentCaptor<RouteSearchQuery> queryCap = ArgumentCaptor.forClass(RouteSearchQuery.class);
        verify(otpClient, org.mockito.Mockito.atLeast(2)).searchRoutes(anyString(), queryCap.capture());
        List<RouteSearchQuery> queries = queryCap.getAllValues();
        assertEquals(LocalTime.of(8, 30), queries.get(0).serviceTime());
        assertEquals(LocalTime.of(8, 45), queries.get(1).serviceTime());

        assertEquals(1, result.routes().size());
    }

    @Test
    void searchRoutesContinuesSliceScanAfterWindowFirstReturnsOneItinerary() throws Exception {
        UUID cityId = UUID.fromString("12121212-1212-1212-1212-121212121212");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode windowPlan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1000,"walkDistance":50,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"W1"},"from":{},"to":{},"startTime":1000,"endTime":2000,"distance":100}
                ]}]}}
                """);
        JsonNode slicePlan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1100,"walkDistance":50,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"S1"},"from":{},"to":{},"startTime":2000,"endTime":3000,"distance":100}
                ]}]}}
                """);
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(windowPlan);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(slicePlan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 5);

        verify(otpClient, times(1)).searchRoutesWithWindow(anyString(), any(), anyInt());
        verify(otpClient, org.mockito.Mockito.atLeast(1)).searchRoutes(anyString(), any());
        assertTrue(result.total() >= 2, "slice scan should add itineraries beyond window-first");
        assertTrue(result.routes().size() <= 5);
    }

    @Test
    void shiftOffsetsStepThroughEndOfServiceDay() {
        List<Integer> offsets = RouteService.shiftOffsetsMinutesThroughEndOfServiceDay(
                LocalDate.of(2026, 3, 27), LocalTime.of(8, 30));
        assertEquals(0, offsets.get(0).intValue());
        assertEquals(15, offsets.get(1).intValue());
        assertTrue(offsets.size() >= 60, "8:30→23:59 should need many 15-min OTP slots");
        assertTrue(offsets.size() <= 256);
    }

    @Test
    void searchRoutesKeepsDistinctItinerariesAcrossShiftedCalls() throws Exception {
        UUID cityId = UUID.fromString("e5e5e5e5-e5e5-e5e5-e5e5-e5e5e5e5e5e5");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode planR1 = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1000,"walkDistance":50,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R1"},"from":{},"to":{},"startTime":100,"endTime":200,"distance":100}
                ]}]}}
                """);
        JsonNode planR2 = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1100,"walkDistance":50,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R2"},"from":{},"to":{},"startTime":900,"endTime":1000,"distance":100}
                ]}]}}
                """);
        AtomicInteger call = new AtomicInteger(0);
        when(otpClient.searchRoutes(anyString(), any())).thenAnswer(inv -> call.getAndIncrement() == 1 ? planR2 : planR1);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);

        assertEquals(2, result.routes().size());
        assertEquals(1000L, result.routes().get(0).durationSeconds());
        assertEquals(1100L, result.routes().get(1).durationSeconds());
    }

    @Test
    void searchRoutesDropsTransitItineraryWhenAnyWalkLegExceedsCap() throws Exception {
        UUID cityId = UUID.fromString("a1a1a1a1-a1a1-a1a1-a1a1-a1a1a1a1a1a1");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 900,
                        "walkDistance": 1300,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 1100, "distance": 1200 },
                          { "mode": "BUS", "from": {}, "to": {}, "startTime": 1100, "endTime": 2000, "distance": 3000 }
                        ]
                      },
                      {
                        "duration": 2000,
                        "walkDistance": 100,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 1100, "distance": 100 },
                          { "mode": "BUS", "from": {}, "to": {}, "startTime": 1100, "endTime": 3000, "distance": 4000 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(2000L, result.routes().get(0).durationSeconds());
    }

    @Test
    void searchRoutesFallsBackToUnfilteredWhenCapWouldRemoveAllTransitItineraries() throws Exception {
        UUID cityId = UUID.fromString("b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 900,
                        "walkDistance": 1300,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 1100, "distance": 1200 },
                          { "mode": "BUS", "from": {}, "to": {}, "startTime": 1100, "endTime": 2000, "distance": 3000 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(900L, result.routes().get(0).durationSeconds());
    }

    @Test
    void searchRoutesRemovesWalkOnlyItineraryWhenWalkExceedsCap() throws Exception {
        UUID cityId = UUID.fromString("c3c3c3c3-c3c3-c3c3-c3c3-c3c3c3c3c3c3");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 3600,
                        "walkDistance": 2000,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 5000, "distance": 2000 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertTrue(result.routes().isEmpty());
    }

    @Test
    void searchRoutesKeepsWalkOnlyItineraryWhenWalkUnderCap() throws Exception {
        UUID cityId = UUID.fromString("e6e6e6e6-e6e6-e6e6-e6e6-e6e6e6e6e6e6");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {
                  "plan": {
                    "itineraries": [
                      {
                        "duration": 600,
                        "walkDistance": 400,
                        "legs": [
                          { "mode": "WALK", "from": {}, "to": {}, "startTime": 1000, "endTime": 2000, "distance": 400 }
                        ]
                      }
                    ]
                  }
                }
                """);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(plan);

        var result = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, result.routes().size());
        assertEquals(600L, result.routes().get(0).durationSeconds());
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

    @Test
    void searchRoutesRetriesWhenCachedSessionHadNoOtpItineraries() throws Exception {
        UUID cityId = UUID.fromString("18181818-1818-1818-1818-181818181818");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode emptyPlan = objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        JsonNode plan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1200,"walkDistance":100,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R1"},"from":{},"to":{},"startTime":1000,"endTime":2000,"distance":3000}
                ]}]}}
                """);
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(emptyPlan, plan);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(emptyPlan);

        var first = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertTrue(first.routes().isEmpty());

        var second = routeService.searchRoutes(cityId, sampleQuery(), 0, 10);
        assertEquals(1, second.routes().size());
        verify(otpClient, times(2)).searchRoutesWithWindow(anyString(), any(), anyInt());
    }

    @Test
    void searchRoutesKeepsItinerariesAtOrAfterServiceTimeInServiceTimezone() throws Exception {
        UUID cityId = UUID.fromString("17171717-1717-1717-1717-171717171717");
        City city = mockCity(cityId, "Brasov", "http://otp:8080/otp");
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));

        LocalDate serviceDate = LocalDate.of(2026, 6, 8);
        LocalTime serviceTime = LocalTime.of(17, 25);
        long departureAtServiceTime = LocalDateTime.of(serviceDate, serviceTime)
                .atZone(ZoneId.of("Europe/Bucharest"))
                .toInstant()
                .toEpochMilli();
        JsonNode plan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1200,"walkDistance":100,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R1"},"from":{},"to":{},"startTime":%d,"endTime":%d,"distance":3000}
                ]}]}}
                """.formatted(departureAtServiceTime, departureAtServiceTime + 600_000));
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(plan);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(
                objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}"));

        RouteSearchQuery query = new RouteSearchQuery(
                "45.650,25.610",
                "45.640,25.600",
                serviceDate,
                serviceTime,
                1,
                10);

        var withServiceTimezone = routeServiceWithTimezone("Europe/Bucharest");
        assertEquals(1, withServiceTimezone.searchRoutes(cityId, query, 0, 10).routes().size());

        var withUtcTimezone = routeServiceWithTimezone("UTC");
        assertTrue(
                withUtcTimezone.searchRoutes(cityId, query, 0, 10).routes().isEmpty(),
                "UTC service timezone should drop Bucharest-local departures before the shifted cutoff");
    }

    private RouteService routeServiceWithTimezone(String serviceTimezone) {
        return new RouteService(
                cityRepository,
                otpClient,
                gtfsReadService,
                0,
                3,
                15,
                64,
                6,
                120,
                120,
                128,
                true,
                serviceTimezone,
                SYNC_RESOLVE_EXECUTOR);
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
