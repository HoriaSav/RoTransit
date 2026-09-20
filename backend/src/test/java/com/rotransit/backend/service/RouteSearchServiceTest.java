package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.RouteSearchQuery;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class RouteSearchServiceTest {

    @Mock private CityRepository cityRepository;
    @Mock private OtpClient otpClient;

    private RouteSearchService service;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private static final Executor SYNC = Runnable::run;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new RouteSearchService(
                cityRepository, otpClient, new OtpItineraryMapper(), new WalkLegPolicy(), SYNC);
    }

    @Test
    void searchRoutesPaginatesAcrossDistinctItineraries() throws Exception {
        UUID cityId = UUID.fromString("12121212-1212-1212-1212-121212121212");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt()))
                .thenReturn(objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}"));

        AtomicInteger call = new AtomicInteger();
        when(otpClient.searchRoutes(anyString(), any())).thenAnswer(inv -> {
            int n = call.getAndIncrement();
            long start = 1000L + n * 1000L;
            return objectMapper.readTree("""
                    {"plan":{"itineraries":[{"duration":%d,"walkDistance":50,"legs":[
                      {"mode":"BUS","route":{"gtfsId":"R%d"},"from":{},"to":{},"startTime":%d,"endTime":%d,"distance":100,
                       "legGeometry":{"points":"_p~iF~ps|U"}}
                    ]}]}}
                    """.formatted(1000 + n, n + 1, start, start + 500));
        });

        RouteSearchQuery query = sampleQuery();
        RouteSearchResponse page0 = service.searchRoutes(cityId, query, 0, 2, true);
        assertEquals(2, page0.routes().size());
        assertTrue(page0.total() >= 2);

        RouteSearchResponse page1 = service.searchRoutes(cityId, query, 2, 2, true);
        assertEquals(2, page1.offset());
        assertEquals(2, page1.limit());
        // Pages should not overlap on first route id when enough distinct itineraries exist
        if (page0.total() >= 4 && !page0.routes().isEmpty() && !page1.routes().isEmpty()) {
            assertFalse(page0.routes().get(0).legs().get(0).routeId()
                    .equals(page1.routes().get(0).legs().get(0).routeId()));
        }
    }

    @Test
    void searchRoutesStripsGeometryWhenIncludeGeometryFalse() throws Exception {
        UUID cityId = UUID.fromString("13131313-1313-1313-1313-131313131313");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode plan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1200,"walkDistance":100,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R1"},"from":{},"to":{},"startTime":1000,"endTime":2000,"distance":3000,
                   "legGeometry":{"points":"_p~iF~ps|U"}}
                ]}]}}
                """);
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(plan);
        when(otpClient.searchRoutes(anyString(), any()))
                .thenReturn(objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}"));

        RouteSearchQuery query = sampleQuery();
        var withGeom = service.searchRoutes(cityId, query, 0, 5, true);
        var withoutGeom = service.searchRoutes(cityId, query, 0, 5, false);

        assertFalse(withGeom.routes().get(0).legs().get(0).geometry().isEmpty());
        assertTrue(withoutGeom.routes().get(0).legs().get(0).geometry().isEmpty());
    }

    @Test
    void searchRoutesDoesNotStickyCacheEmptyOtpResults() throws Exception {
        UUID cityId = UUID.fromString("14141414-1414-1414-1414-141414141414");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        JsonNode empty = objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        JsonNode plan = objectMapper.readTree("""
                {"plan":{"itineraries":[{"duration":1200,"walkDistance":100,"legs":[
                  {"mode":"BUS","route":{"gtfsId":"R1"},"from":{},"to":{},"startTime":1000,"endTime":2000,"distance":3000}
                ]}]}}
                """);
        when(otpClient.searchRoutesWithWindow(anyString(), any(), anyInt())).thenReturn(empty, plan);
        when(otpClient.searchRoutes(anyString(), any())).thenReturn(empty);

        assertTrue(service.searchRoutes(cityId, sampleQuery(), 0, 10, false).routes().isEmpty());
        assertEquals(1, service.searchRoutes(cityId, sampleQuery(), 0, 10, false).routes().size());
        verify(otpClient, times(2)).searchRoutesWithWindow(anyString(), any(), anyInt());
    }

    private RouteSearchQuery sampleQuery() {
        return new RouteSearchQuery(
                "45.650,25.610",
                "45.640,25.600",
                LocalDate.of(2026, 3, 27),
                LocalTime.of(8, 30),
                1,
                10);
    }

    private City mockCity(UUID cityId) {
        City city = org.mockito.Mockito.mock(City.class);
        when(city.getId()).thenReturn(cityId);
        when(city.getName()).thenReturn("Brasov");
        when(city.getOtpBaseUrl()).thenReturn("http://otp:8080/otp");
        return city;
    }
}
