package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.dto.StopTimetableEntryResponse;
import com.rotransit.backend.dto.StopTimetableResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.time.LocalDate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class RouteService {
    private static final Logger log = LoggerFactory.getLogger(RouteService.class);

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final GtfsReadService gtfsReadService;

    public RouteService(CityRepository cityRepository, OtpClient otpClient, GtfsReadService gtfsReadService) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
    }

    public RouteSearchResponse searchRoutes(UUID cityId, RouteSearchQuery query, int offset, int limit) {
        City city = cityRepository.findById(cityId)
                .orElseThrow(() -> new CityNotFoundException(cityId));
        log.info("searchRoutes cityId={} origin={} destination={} offset={} limit={}",
                cityId, query.origin(), query.destination(), offset, limit);

        JsonNode response = otpClient.searchRoutes(city.getOtpBaseUrl(), query);
        List<RouteOptionResponse> routes = new ArrayList<>();
        JsonNode itineraries = response.path("plan").path("itineraries");
        if (itineraries.isArray()) {
            for (JsonNode itinerary : itineraries) {
                routes.add(new RouteOptionResponse(
                        itinerary.path("duration").asLong(0),
                        itinerary.path("transfers").asInt(0),
                        Math.round(itinerary.path("walkDistance").asDouble(0)),
                        estimatePriceLei(itinerary.path("legs")),
                        "5 lei / 90 min from first transit boarding",
                        toLegs(itinerary.path("legs"))
                ));
            }
        }
        int safeOffset = Math.max(offset, 0);
        int safeLimit = Math.max(limit, 1);
        int toIndex = Math.min(safeOffset + safeLimit, routes.size());
        List<RouteOptionResponse> paged = safeOffset >= routes.size()
                ? List.of()
                : routes.subList(safeOffset, toIndex);
        return new RouteSearchResponse(
                city.getId(),
                city.getName(),
                safeOffset,
                safeLimit,
                routes.size(),
                paged
        );
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

    public StopTimetableResponse routeStopTimes(UUID cityId, String routeId, String stopId, LocalDate serviceDate) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        List<StopTimetableEntryResponse> departures =
                gtfsReadService.routeStopTimes(cityId, routeId, stopId, serviceDate);
        log.info("routeStopTimes cityId={} routeId={} stopId={} serviceDate={} count={}",
                cityId, routeId, stopId, serviceDate, departures.size());
        return new StopTimetableResponse(
                cityId.toString(),
                routeId,
                stopId,
                serviceDate.toString(),
                departures
        );
    }


    public List<NearbyStopResponse> nearbyStops(UUID cityId, double latitude, double longitude, int radiusMeters) {
        City city = cityRepository.findById(cityId)
                .orElseThrow(() -> new CityNotFoundException(cityId));

        List<JsonNode> rawStops = otpClient.findNearbyStops(city.getOtpBaseUrl(), latitude, longitude, radiusMeters);
        List<NearbyStopResponse> stops = new ArrayList<>();
        for (JsonNode stop : rawStops) {
            stops.add(new NearbyStopResponse(
                    stop.path("id").asText(""),
                    stop.path("name").asText(""),
                    stop.path("lat").asDouble(0.0),
                    stop.path("lon").asDouble(0.0)
            ));
        }
        log.info("nearbyStops cityId={} lat={} lon={} radius={} count={}",
                cityId, latitude, longitude, radiusMeters, stops.size());
        return stops;
    }

    public List<NearbyStopResponse> searchStops(UUID cityId, String query, int limit) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));

        String normalizedQuery = query == null ? "" : query.trim();
        if (normalizedQuery.length() < 2) {
            return List.of();
        }
        int safeLimit = Math.max(limit, 1);
        List<NearbyStopResponse> stops = gtfsReadService.searchStops(cityId, normalizedQuery, safeLimit);
        log.info("searchStops cityId={} q='{}' limit={} count={}", cityId, normalizedQuery, safeLimit, stops.size());
        return stops;
    }

    private int estimatePriceLei(JsonNode legs) {
        if (!legs.isArray()) {
            return 0;
        }
        Long firstTransitStart = null;
        Long lastTransitEnd = null;
        for (JsonNode leg : legs) {
            String mode = leg.path("mode").asText("");
            if ("WALK".equalsIgnoreCase(mode)) {
                continue;
            }
            long startTime = leg.path("startTime").asLong(0L);
            long endTime = leg.path("endTime").asLong(startTime);
            if (firstTransitStart == null) {
                firstTransitStart = startTime;
            }
            lastTransitEnd = endTime;
        }
        if (firstTransitStart == null || lastTransitEnd == null || lastTransitEnd <= firstTransitStart) {
            return 0;
        }
        long durationMs = lastTransitEnd - firstTransitStart;
        long windowMs = 90L * 60L * 1000L;
        long windows = Math.max(1L, (durationMs + windowMs - 1L) / windowMs);
        return (int) (windows * 5L);
    }

    private List<LegResponse> toLegs(JsonNode legs) {
        List<LegResponse> output = new ArrayList<>();
        if (!legs.isArray()) {
            return output;
        }
        for (JsonNode leg : legs) {
            output.add(new LegResponse(
                    leg.path("mode").asText(""),
                    leg.path("from").path("name").asText(""),
                    leg.path("to").path("name").asText(""),
                    leg.path("startTime").asLong(0),
                    leg.path("endTime").asLong(0),
                    leg.path("distance").asDouble(0.0)
            ));
        }
        return output;
    }
}
