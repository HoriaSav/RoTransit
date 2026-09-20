package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.RouteSearchQuery;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Executor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class DestinationResolveServiceTest {

    @Mock private CityRepository cityRepository;
    @Mock private OtpClient otpClient;
    @Mock private GtfsReadService gtfsReadService;

    private DestinationResolveService service;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private static final Executor SYNC = Runnable::run;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new DestinationResolveService(
                cityRepository, otpClient, gtfsReadService, new OtpItineraryMapper(), SYNC);
    }

    @Test
    void resolveDestinationStopForRouteSkipsOtpWhenSingleGtfsMatch() {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina")))
                .thenReturn(List.of(new NearbyStopResponse("only", "Doina", 45.1, 25.1)));

        NearbyStopResponse out = service.resolveDestinationStopForRoute(
                cityId, "45.65,25.65", "Doina", LocalDate.of(2026, 4, 3), LocalTime.of(18, 0));

        assertEquals("only", out.stopId());
        verify(otpClient, never()).searchRoutes(anyString(), any());
    }

    @Test
    void resolveDestinationStopForRoutePicksFewerTransfersAmongCandidates() throws Exception {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina")))
                .thenReturn(List.of(
                        new NearbyStopResponse("near", "Doina", 45.641, 25.65),
                        new NearbyStopResponse("far", "Doina", 45.66, 25.65)));

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
            if (q.destination().contains("45.641")) {
                return worse;
            }
            if (q.destination().contains("45.66")) {
                return better;
            }
            return objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}");
        });

        NearbyStopResponse out = service.resolveDestinationStopForRoute(
                cityId, "45.65,25.65", "Doina", LocalDate.of(2026, 4, 3), LocalTime.of(18, 0));

        assertEquals("far", out.stopId());
    }

    @Test
    void resolveDestinationStopForRouteFallsBackToClosestWhenAllOtpPlansEmpty() throws Exception {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina")))
                .thenReturn(List.of(
                        new NearbyStopResponse("far", "Doina", 45.70, 25.65),
                        new NearbyStopResponse("near", "Doina", 45.651, 25.65)));
        when(otpClient.searchRoutes(anyString(), any()))
                .thenReturn(objectMapper.readTree("{\"plan\":{\"itineraries\":[]}}"));

        NearbyStopResponse out = service.resolveDestinationStopForRoute(
                cityId, "45.65,25.65", "Doina", LocalDate.of(2026, 4, 3), LocalTime.of(18, 0));

        assertEquals("near", out.stopId());
    }

    @Test
    void resolveDestinationStopForRouteCachesWinnerAndSkipsSecondLookup() {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa4");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("doina")))
                .thenReturn(List.of(new NearbyStopResponse("only", "Doina", 45.1, 25.1)));

        LocalDate date = LocalDate.of(2026, 4, 3);
        LocalTime time = LocalTime.of(18, 0);
        service.resolveDestinationStopForRoute(cityId, "45.65,25.65", "Doina", date, time);
        service.resolveDestinationStopForRoute(cityId, "45.65,25.65", "Doina", date, time);

        verify(gtfsReadService, times(1)).findStopsByNormalizedName(eq(cityId), eq("doina"));
        verify(otpClient, never()).searchRoutes(anyString(), any());
    }

    @Test
    void resolveDestinationStopForRouteThrowsWhenNoCandidates() {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa5");
        City city = mockCity(cityId);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.findStopsByNormalizedName(eq(cityId), eq("missing")))
                .thenReturn(List.of());

        assertThrows(StopNotFoundException.class, () -> service.resolveDestinationStopForRoute(
                cityId, "45.65,25.65", "Missing", LocalDate.of(2026, 4, 3), LocalTime.of(18, 0)));
    }

    private City mockCity(UUID cityId) {
        City city = org.mockito.Mockito.mock(City.class);
        when(city.getId()).thenReturn(cityId);
        when(city.getName()).thenReturn("Brasov");
        when(city.getOtpBaseUrl()).thenReturn("http://otp:8080/otp");
        return city;
    }
}
