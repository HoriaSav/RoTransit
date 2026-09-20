package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.OfflinePackMetaResponse;
import com.rotransit.backend.dto.OfflinePackResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.StopTimetableEntryResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class TransitCatalogServiceTest {

    @Mock private CityRepository cityRepository;
    @Mock private GtfsReadService gtfsReadService;

    private TransitCatalogService service;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        service = new TransitCatalogService(cityRepository, gtfsReadService);
    }

    @Test
    void buildOfflinePackMetaAndPackShareStablePackVersionForSameInputs() {
        UUID cityId = UUID.fromString("efefefef-efef-efef-efef-efefefefefef");
        LocalDate anchor = LocalDate.of(2026, 4, 6);
        City city = org.mockito.Mockito.mock(City.class);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(gtfsReadService.listBusLines(cityId)).thenReturn(List.of(
                new BusLineResponse("ROUTE:1", "1", "Route 1", "BUS")));
        when(gtfsReadService.routeStops(eq(cityId), eq("ROUTE:1"), eq("0")))
                .thenReturn(List.of(new RouteStopResponse("STOP:1", "First", 45.61, 25.60, 1)));
        when(gtfsReadService.routeStops(eq(cityId), eq("ROUTE:1"), eq("1")))
                .thenReturn(List.of());
        when(gtfsReadService.routeStopTimes(eq(cityId), eq("ROUTE:1"), eq("STOP:1"), any(), eq("0")))
                .thenReturn(List.of(
                        new StopTimetableEntryResponse("TRIP:1", "Center", "08:10:00"),
                        new StopTimetableEntryResponse("TRIP:2", "Center", "08:25:00")));

        OfflinePackMetaResponse meta = service.buildOfflinePackMeta(cityId, anchor);
        OfflinePackResponse pack = service.buildOfflinePack(cityId, anchor);

        assertNotNull(meta.packVersion());
        assertEquals(meta.packVersion(), pack.packVersion());
        assertEquals(cityId.toString(), pack.cityId());
        assertEquals(anchor.toString(), pack.anchorMonday());
        assertEquals(1, pack.buses().size());
    }
}
