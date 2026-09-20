package com.rotransit.backend.service;

import com.rotransit.backend.dto.RouteSearchQuery;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

/**
 * Thin façade for route/stop HTTP API. Search, destination resolve, and OTP mapping
 * live in dedicated services; transit catalog is TransitCatalogService.
 */
@Service
public class RouteService {
    private static final Logger log = LoggerFactory.getLogger(RouteService.class);

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final GtfsReadService gtfsReadService;
    private final RouteSearchService routeSearchService;
    private final DestinationResolveService destinationResolveService;

    @Autowired
    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            RouteSearchService routeSearchService,
            DestinationResolveService destinationResolveService) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
        this.routeSearchService = routeSearchService;
        this.destinationResolveService = destinationResolveService;
    }

    /**
     * Backward-compatible constructor used by unit tests.
     * Builds the same collaborator graph the old monolithic constructor used.
     */
    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            Executor stopResolveExecutor) {
        this(
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
                "Europe/Bucharest",
                stopResolveExecutor);
    }

    /**
     * Unit-test constructor that mirrors the old RouteService @Value knobs
     * (search windows, cache, service timezone).
     */
    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            int additionalSearchWindows,
            int maxAdditionalSearchWindows,
            int routeSearchSliceStepMinutes,
            int routeSearchMaxSlices,
            int routeSearchParallelWorkers,
            int routeSearchWindowMinutes,
            int routeSearchSessionTtlSeconds,
            int routeSearchCacheMaxEntries,
            boolean routeSearchWindowFirstEnabled,
            String serviceTimezone,
            Executor stopResolveExecutor) {
        OtpItineraryMapper mapper = new OtpItineraryMapper();
        WalkLegPolicy walk = new WalkLegPolicy();
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
        this.routeSearchService = new RouteSearchService(
                cityRepository,
                otpClient,
                mapper,
                walk,
                stopResolveExecutor,
                additionalSearchWindows,
                maxAdditionalSearchWindows,
                routeSearchSliceStepMinutes,
                routeSearchMaxSlices,
                routeSearchParallelWorkers,
                routeSearchWindowMinutes,
                routeSearchSessionTtlSeconds,
                routeSearchCacheMaxEntries,
                routeSearchWindowFirstEnabled,
                serviceTimezone);
        this.destinationResolveService = new DestinationResolveService(
                cityRepository, otpClient, gtfsReadService, mapper, stopResolveExecutor);
    }

    /** Kept on the façade so existing unit tests keep compiling. */
    static List<Integer> shiftOffsetsMinutesThroughEndOfServiceDay(
            LocalDate serviceDate, LocalTime serviceTime) {
        return RouteSearchService.shiftOffsetsMinutesThroughEndOfServiceDay(serviceDate, serviceTime);
    }

    public RouteSearchResponse searchRoutes(
            UUID cityId,
            RouteSearchQuery query,
            int offset,
            int limit,
            boolean includeGeometry) {
        return routeSearchService.searchRoutes(cityId, query, offset, limit, includeGeometry);
    }

    public RouteSearchResponse searchRoutes(UUID cityId, RouteSearchQuery query, int offset, int limit) {
        return searchRoutes(cityId, query, offset, limit, false);
    }

    public NearbyStopResponse resolveDestinationStopForRoute(
            UUID cityId,
            String origin,
            String stopDisplayName,
            LocalDate serviceDate,
            LocalTime serviceTime) {
        return destinationResolveService.resolveDestinationStopForRoute(
                cityId, origin, stopDisplayName, serviceDate, serviceTime);
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
        List<NearbyStopResponse> merged =
                StopSuggestionMerge.dedupePreservingRank(stops, stops.size(), latitude, longitude);
        log.info("nearbyStops cityId={} lat={} lon={} radius={} raw={} deduped={}",
                cityId, latitude, longitude, radiusMeters, stops.size(), merged.size());
        return merged;
    }

    public List<NearbyStopResponse> searchStops(
            UUID cityId, String query, int limit, Double refLat, Double refLon) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));

        String normalizedQuery = query == null ? "" : query.trim();
        if (normalizedQuery.length() < 2) {
            return List.of();
        }
        int safeLimit = Math.max(limit, 1);
        int fetchCap = Math.min(Math.max(safeLimit * 12, safeLimit), 300);
        List<NearbyStopResponse> raw = gtfsReadService.searchStops(cityId, normalizedQuery, fetchCap);
        List<NearbyStopResponse> stops =
                StopSuggestionMerge.dedupePreservingRank(raw, safeLimit, refLat, refLon);
        log.info("searchStops cityId={} q='{}' limit={} raw={} deduped={}",
                cityId, normalizedQuery, safeLimit, raw.size(), stops.size());
        return stops;
    }
}
