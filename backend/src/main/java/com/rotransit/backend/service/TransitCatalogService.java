package com.rotransit.backend.service;

import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.OfflinePackMetaResponse;
import com.rotransit.backend.dto.OfflinePackResponse;
import com.rotransit.backend.dto.OfflinePackRouteStopsResponse;
import com.rotransit.backend.dto.OfflinePackTimetableEntryResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.StopTimetableEntryResponse;
import com.rotransit.backend.dto.StopTimetableResponse;
import com.rotransit.backend.repository.CityRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class TransitCatalogService {
    private static final Logger log = LoggerFactory.getLogger(TransitCatalogService.class);

    private final CityRepository cityRepository;
    private final GtfsReadService gtfsReadService;

    public TransitCatalogService(CityRepository cityRepository, GtfsReadService gtfsReadService) {
        this.cityRepository = cityRepository;
        this.gtfsReadService = gtfsReadService;
    }

    public List<BusLineResponse> listBusLines(UUID cityId) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        List<BusLineResponse> output = gtfsReadService.listBusLines(cityId);
        log.info("listBusLines cityId={} count={}", cityId, output.size());
        return output;
    }

    public List<RouteStopResponse> routeStops(UUID cityId, String routeId, String directionId) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        List<RouteStopResponse> output = gtfsReadService.routeStops(cityId, routeId, directionId);
        log.info("routeStops cityId={} routeId={} directionId={} count={}", cityId, routeId, directionId, output.size());
        return output;
    }

    public StopTimetableResponse routeStopTimes(
            UUID cityId,
            String routeId,
            String stopId,
            LocalDate serviceDate,
            String directionId
    ) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        List<StopTimetableEntryResponse> departures =
                gtfsReadService.routeStopTimes(cityId, routeId, stopId, serviceDate, directionId);
        log.info("routeStopTimes cityId={} routeId={} stopId={} serviceDate={} directionId={} count={}",
                cityId, routeId, stopId, serviceDate, directionId, departures.size());
        return new StopTimetableResponse(
                cityId.toString(),
                routeId,
                stopId,
                serviceDate.toString(),
                departures
        );
    }

    public OfflinePackMetaResponse buildOfflinePackMeta(UUID cityId, LocalDate anchorMonday) {
        OfflinePackMaterialized m = materializeOfflinePack(cityId, anchorMonday, false);
        return new OfflinePackMetaResponse(
                m.cityIdStr(),
                m.anchorStr(),
                m.packVersion(),
                m.generatedAt());
    }

    /**
     * Builds a single JSON document for mobile offline mode: all bus lines, per-direction stops,
     * and Mon/Sat/Sun timetable slices (aligned with the app's week anchor Monday).
     */
    public OfflinePackResponse buildOfflinePack(UUID cityId, LocalDate anchorMonday) {
        OfflinePackMaterialized m = materializeOfflinePack(cityId, anchorMonday, true);
        log.info("buildOfflinePack cityId={} buses={} routeStopSlices={} timetableSlices={} anchorMonday={}",
                cityId, m.buses().size(), m.routeStopsOut().size(), m.timetablesOut().size(), anchorMonday);
        return new OfflinePackResponse(
                m.cityIdStr(),
                m.anchorStr(),
                m.generatedAt(),
                m.packVersion(),
                m.buses(),
                m.routeStopsOut(),
                m.timetablesOut()
        );
    }

    private record OfflinePackMaterialized(
            String cityIdStr,
            String anchorStr,
            String generatedAt,
            String packVersion,
            List<BusLineResponse> buses,
            List<OfflinePackRouteStopsResponse> routeStopsOut,
            List<OfflinePackTimetableEntryResponse> timetablesOut
    ) {
    }

    private OfflinePackMaterialized materializeOfflinePack(
            UUID cityId,
            LocalDate anchorMonday,
            boolean includePayloadLists
    ) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        Instant generatedAt = Instant.now();
        MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
        feedUtf8(digest, cityId.toString());
        digest.update((byte) '|');
        feedUtf8(digest, anchorMonday.toString());
        digest.update((byte) '|');

        LocalDate saturday = anchorMonday.plusDays(5);
        LocalDate sunday = anchorMonday.plusDays(6);

        List<BusLineResponse> buses = gtfsReadService.listBusLines(cityId);
        feedUtf8(digest, String.valueOf(buses.size()));
        digest.update((byte) '|');

        List<OfflinePackRouteStopsResponse> routeStopsOut =
                includePayloadLists ? new ArrayList<>() : List.of();
        List<OfflinePackTimetableEntryResponse> timetablesOut =
                includePayloadLists ? new ArrayList<>() : List.of();

        record DaySlice(LocalDate date, String dayKind) {}
        List<DaySlice> daySlices = List.of(
                new DaySlice(anchorMonday, "MONFRI"),
                new DaySlice(saturday, "SATURDAY"),
                new DaySlice(sunday, "SUNDAY")
        );

        String[] directions = {"0", "1"};
        for (BusLineResponse line : buses) {
            String routeId = line.routeId();
            feedUtf8(digest, routeId);
            digest.update((byte) '|');
            for (String directionId : directions) {
                List<RouteStopResponse> stops = gtfsReadService.routeStops(cityId, routeId, directionId);
                if (stops.isEmpty()) {
                    continue;
                }
                feedUtf8(digest, directionId);
                digest.update((byte) '|');
                for (RouteStopResponse stop : stops) {
                    feedUtf8(digest, stop.stopId());
                    digest.update((byte) ',');
                }
                digest.update((byte) '|');

                if (includePayloadLists) {
                    routeStopsOut.add(new OfflinePackRouteStopsResponse(routeId, directionId, stops));
                }
                for (RouteStopResponse stop : stops) {
                    for (DaySlice day : daySlices) {
                        List<StopTimetableEntryResponse> departures = gtfsReadService.routeStopTimes(
                                cityId, routeId, stop.stopId(), day.date(), directionId);
                        feedUtf8(digest, routeId);
                        digest.update((byte) 0);
                        feedUtf8(digest, directionId);
                        digest.update((byte) 0);
                        feedUtf8(digest, stop.stopId());
                        digest.update((byte) 0);
                        feedUtf8(digest, day.dayKind());
                        digest.update((byte) 0);
                        for (StopTimetableEntryResponse d : departures) {
                            feedUtf8(digest, d.tripId());
                            digest.update((byte) 0);
                            feedUtf8(digest, d.departureTime());
                            digest.update((byte) 0);
                            feedUtf8(digest, d.headsign() != null ? d.headsign() : "");
                            digest.update((byte) ';');
                        }
                        digest.update((byte) '#');

                        if (includePayloadLists) {
                            StopTimetableResponse tt = new StopTimetableResponse(
                                    cityId.toString(),
                                    routeId,
                                    stop.stopId(),
                                    day.date().toString(),
                                    departures
                            );
                            timetablesOut.add(new OfflinePackTimetableEntryResponse(
                                    routeId, stop.stopId(), directionId, day.dayKind(), tt));
                        }
                    }
                }
            }
        }

        String packVersion = HexFormat.of().formatHex(digest.digest());
        return new OfflinePackMaterialized(
                cityId.toString(),
                anchorMonday.toString(),
                generatedAt.toString(),
                packVersion,
                buses,
                routeStopsOut,
                timetablesOut
        );
    }

    private static void feedUtf8(MessageDigest digest, String s) {
        digest.update(s.getBytes(StandardCharsets.UTF_8));
    }
}
