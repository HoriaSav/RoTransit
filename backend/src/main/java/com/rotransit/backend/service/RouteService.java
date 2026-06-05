package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.LegPointResponse;
import com.rotransit.backend.dto.LegStopResponse;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.OfflinePackMetaResponse;
import com.rotransit.backend.dto.OfflinePackResponse;
import com.rotransit.backend.dto.OfflinePackRouteStopsResponse;
import com.rotransit.backend.dto.OfflinePackTimetableEntryResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.dto.StopTimetableEntryResponse;
import com.rotransit.backend.dto.StopTimetableResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.otp.OtpException;
import com.rotransit.backend.repository.CityRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.concurrent.ConcurrentHashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class RouteService {
    private static final Logger log = LoggerFactory.getLogger(RouteService.class);

    /** Max walking (meters): drop walk-only itineraries above this; drop transit itineraries with any WALK leg above this. */
    private static final double MAX_WALK_LEG_METERS_WHEN_TRANSIT = 1000.0;

    /** Step between OTP plan requests when asking for additional windows. */
    private static final int ROUTE_SEARCH_SHIFT_STEP_MINUTES = 15;

    /** Max distinct itineraries returned (payload / UI bounds). */
    private static final int ROUTE_SEARCH_MERGED_CAP = 120;

    private static final int MAX_AMBIGUOUS_DESTINATION_CANDIDATES = 12;
    /** One itinerary is enough: OTP returns the best option first. */
    private static final int RESOLVE_PLAN_ITINERARY_COUNT = 1;
    private static final Duration DESTINATION_RESOLVE_CACHE_TTL = Duration.ofMinutes(30);

    /**
     * Mutable in-memory search session: window seed + incremental OTP time slices until
     * {@link #scanComplete} or {@link #ROUTE_SEARCH_MERGED_CAP} itineraries are collected.
     */
    private static final class IncrementalRouteSearchSession {
        private final String otpBaseUrl;
        private final RouteSearchQuery query;
        private final long minDepartureMillis;
        private final List<Integer> sliceOffsets;
        private final Set<String> seenKeys = new HashSet<>();
        private final List<RouteOptionResponse> rawMerged = new ArrayList<>();
        private List<RouteOptionResponse> routes = List.of();
        private int nextSliceIndex;
        private boolean scanComplete;
        private boolean windowFirstAttempted;
        private final Instant expiresAt;
        private final Instant builtAt;

        private IncrementalRouteSearchSession(
                String otpBaseUrl,
                RouteSearchQuery query,
                long minDepartureMillis,
                List<Integer> sliceOffsets,
                Instant expiresAt,
                Instant builtAt) {
            this.otpBaseUrl = otpBaseUrl;
            this.query = query;
            this.minDepartureMillis = minDepartureMillis;
            this.sliceOffsets = sliceOffsets;
            this.expiresAt = expiresAt;
            this.builtAt = builtAt;
        }

        private List<RouteOptionResponse> routes() {
            return routes;
        }

        private boolean scanComplete() {
            return scanComplete;
        }

        private boolean isExpired(Instant now) {
            return expiresAt.isBefore(now);
        }

        private Instant builtAt() {
            return builtAt;
        }

        private Instant expiresAt() {
            return expiresAt;
        }
    }

    private record CachedDestinationResolve(NearbyStopResponse stop, Instant expiresAt) {}

    private record DestinationResolveScore(
            NearbyStopResponse stop, int transfers, long durationSec, long walkRounded) {}

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final GtfsReadService gtfsReadService;
    private final Executor stopResolveExecutor;
    private final int additionalSearchWindows;
    private final int maxAdditionalSearchWindows;
    private final Map<String, CachedDestinationResolve> destinationResolveCache = new ConcurrentHashMap<>();
    private final Map<String, IncrementalRouteSearchSession> routeSearchSessionCache = new ConcurrentHashMap<>();
    private final int routeSearchSliceStepMinutes;
    private final int routeSearchMaxSlices;
    private final int routeSearchParallelWorkers;
    private final int routeSearchWindowMinutes;
    private final int routeSearchSessionTtlSeconds;
    private final int routeSearchCacheMaxEntries;
    private final boolean routeSearchWindowFirstEnabled;

    @Autowired
    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            @Value("${rotransit.routes.search.additional-windows:0}") int additionalSearchWindows,
            @Value("${rotransit.routes.search.max-additional-windows:3}") int maxAdditionalSearchWindows,
            @Value("${rotransit.routes.search.slice-step-minutes:15}") int routeSearchSliceStepMinutes,
            @Value("${rotransit.routes.search.max-slices:64}") int routeSearchMaxSlices,
            @Value("${rotransit.routes.search.parallel-workers:6}") int routeSearchParallelWorkers,
            @Value("${rotransit.routes.search.window-minutes:120}") int routeSearchWindowMinutes,
            @Value("${rotransit.routes.search.session-ttl-seconds:120}") int routeSearchSessionTtlSeconds,
            @Value("${rotransit.routes.search.cache-max-entries:128}") int routeSearchCacheMaxEntries,
            @Value("${rotransit.routes.search.window-first-enabled:true}") boolean routeSearchWindowFirstEnabled,
            @Qualifier("stopResolveExecutor") Executor stopResolveExecutor) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
        this.additionalSearchWindows = Math.max(0, additionalSearchWindows);
        this.maxAdditionalSearchWindows = Math.max(0, maxAdditionalSearchWindows);
        this.routeSearchSliceStepMinutes = Math.max(1, routeSearchSliceStepMinutes);
        this.routeSearchMaxSlices = Math.max(1, routeSearchMaxSlices);
        this.routeSearchParallelWorkers = Math.max(1, routeSearchParallelWorkers);
        this.routeSearchWindowMinutes = Math.max(1, routeSearchWindowMinutes);
        this.routeSearchSessionTtlSeconds = Math.max(5, routeSearchSessionTtlSeconds);
        this.routeSearchCacheMaxEntries = Math.max(16, routeSearchCacheMaxEntries);
        this.routeSearchWindowFirstEnabled = routeSearchWindowFirstEnabled;
        this.stopResolveExecutor = stopResolveExecutor;
    }

    // Backward-compatible constructor used by unit tests.
    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            Executor stopResolveExecutor) {
        this(cityRepository, otpClient, gtfsReadService, 0, 3,
                ROUTE_SEARCH_SHIFT_STEP_MINUTES, 64, 6, 120, 120, 128, true, stopResolveExecutor);
    }

    public RouteSearchResponse searchRoutes(
            UUID cityId,
            RouteSearchQuery query,
            int offset,
            int limit,
            boolean includeGeometry) {
        City city = cityRepository.findById(cityId)
                .orElseThrow(() -> new CityNotFoundException(cityId));
        log.info("searchRoutes cityId={} origin={} destination={} offset={} limit={}",
                cityId, query.origin(), query.destination(), offset, limit);
        Instant startedAt = Instant.now();
        long otpCallsBefore = otpClient.totalHttpCalls();

        int safeLimit = Math.max(limit, 1);
        int safeOffset = Math.max(offset, 0);
        cleanupExpiredRouteSearchSessionsIfNeeded();
        String sessionKey = routeSearchSessionKey(cityId, query);
        Instant now = Instant.now();
        IncrementalRouteSearchSession session = routeSearchSessionCache.get(sessionKey);
        boolean cacheHit = session != null && !session.isExpired(now);
        if (!cacheHit) {
            session = newIncrementalSession(city.getOtpBaseUrl(), query, now);
            routeSearchSessionCache.put(sessionKey, session);
        }
        int targetSize = safeOffset + safeLimit;
        fillSessionUntil(session, targetSize);
        List<RouteOptionResponse> routes = session.routes();
        int total = routes.size();
        boolean hasMore = !session.scanComplete();
        int fromIndex = Math.min(safeOffset, total);
        int toIndex = Math.min(fromIndex + safeLimit, total);
        List<RouteOptionResponse> page = routes.subList(fromIndex, toIndex);
        List<RouteOptionResponse> responseRoutes = includeGeometry
                ? page
                : page.stream().map(this::stripGeometry).toList();
        long otpCallsAfter = otpClient.totalHttpCalls();
        long elapsedMs = Duration.between(startedAt, now).toMillis();
        log.info(
                "searchRoutes metrics cityId={} elapsedMs={} otpHttpCalls={} total={} pageSize={} offset={} hasMore={} includeGeometry={} cacheHit={}",
                cityId,
                elapsedMs,
                Math.max(0, otpCallsAfter - otpCallsBefore),
                total,
                responseRoutes.size(),
                safeOffset,
                hasMore,
                includeGeometry,
                cacheHit);
        return new RouteSearchResponse(
                city.getId(),
                city.getName(),
                safeOffset,
                safeLimit,
                total,
                hasMore,
                responseRoutes
        );
    }

    private IncrementalRouteSearchSession newIncrementalSession(
            String otpBaseUrl, RouteSearchQuery query, Instant now) {
        long minDepartureMillis = LocalDateTime.of(query.serviceDate(), query.serviceTime())
                .atZone(java.time.ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli();
        return new IncrementalRouteSearchSession(
                otpBaseUrl,
                query,
                minDepartureMillis,
                allDaySliceOffsets(query.serviceDate(), query.serviceTime()),
                now.plusSeconds(routeSearchSessionTtlSeconds),
                now);
    }

    private void fillSessionUntil(IncrementalRouteSearchSession session, int targetSize) {
        if (!session.windowFirstAttempted && routeSearchWindowFirstEnabled) {
            session.windowFirstAttempted = true;
            try {
                JsonNode windowResponse = otpClient.searchRoutesWithWindow(
                        session.otpBaseUrl,
                        session.query,
                        routeSearchWindowMinutes);
                if (windowResponse != null) {
                    appendRoutesDedup(session, routesFromOtpPlan(windowResponse));
                    refreshSessionRoutes(session);
                }
            } catch (Exception ex) {
                log.debug("searchRoutes window-first failed: {}", ex.toString());
            }
            if (session.routes().size() >= targetSize || session.scanComplete) {
                return;
            }
        }
        while (session.routes().size() < targetSize && !session.scanComplete) {
            int progressed = appendNextSliceChunk(session);
            refreshSessionRoutes(session);
            if (progressed == 0) {
                session.scanComplete = true;
                break;
            }
        }
    }

    private int appendNextSliceChunk(IncrementalRouteSearchSession session) {
        if (session.nextSliceIndex >= session.sliceOffsets.size()) {
            session.scanComplete = true;
            return 0;
        }
        int from = session.nextSliceIndex;
        int to = Math.min(from + routeSearchParallelWorkers, session.sliceOffsets.size());
        List<Integer> chunk = session.sliceOffsets.subList(from, to);
        List<CompletableFuture<List<RouteOptionResponse>>> futures = chunk.stream()
                .map(plusMinutes -> CompletableFuture.supplyAsync(() -> {
                    RouteSearchQuery shifted = plusMinutes == 0
                            ? session.query
                            : shiftServiceTime(session.query, plusMinutes);
                    JsonNode response = otpClient.searchRoutes(session.otpBaseUrl, shifted);
                    return routesFromOtpPlan(response);
                }, stopResolveExecutor))
                .toList();
        try {
            CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
        } catch (CompletionException ex) {
            if (ex.getCause() instanceof OtpException otp) {
                throw otp;
            }
            throw ex;
        }
        for (CompletableFuture<List<RouteOptionResponse>> future : futures) {
            appendRoutesDedup(session, future.join());
            if (session.scanComplete) {
                break;
            }
        }
        session.nextSliceIndex = to;
        if (to >= session.sliceOffsets.size()) {
            session.scanComplete = true;
        }
        return chunk.size();
    }

    private void appendRoutesDedup(IncrementalRouteSearchSession session, List<RouteOptionResponse> batch) {
        for (RouteOptionResponse route : batch) {
            String key = itineraryDedupKey(route);
            if (session.seenKeys.add(key)) {
                session.rawMerged.add(route);
                if (session.rawMerged.size() >= ROUTE_SEARCH_MERGED_CAP) {
                    session.scanComplete = true;
                    return;
                }
            }
        }
    }

    private void refreshSessionRoutes(IncrementalRouteSearchSession session) {
        session.routes = normalizeMergedRoutes(session.rawMerged, session.minDepartureMillis);
    }

    private List<RouteOptionResponse> normalizeMergedRoutes(
            List<RouteOptionResponse> merged, long minDepartureMillis) {
        List<RouteOptionResponse> capped = applyWalkLegCapWhenTransit(merged);
        List<RouteOptionResponse> filtered = capped.stream()
                .filter(route -> {
                    long departure = departureSortKey(route);
                    if (departure < 86_400_000L) {
                        return true;
                    }
                    return departure >= minDepartureMillis;
                })
                .collect(Collectors.toCollection(ArrayList::new));
        filtered.sort(Comparator
                .comparingLong(RouteService::departureSortKey)
                .thenComparingInt(RouteOptionResponse::transfers)
                .thenComparingLong(RouteOptionResponse::durationSeconds));
        return filtered;
    }

    // Backward-compatible signature used by unit tests and existing call sites.
    public RouteSearchResponse searchRoutes(UUID cityId, RouteSearchQuery query, int offset, int limit) {
        return searchRoutes(cityId, query, offset, limit, false);
    }

    /**
     * Earliest journey start (first leg {@code startTime}, OTP epoch millis). Used for chronological ordering.
     */
    private static long departureSortKey(RouteOptionResponse r) {
        if (r.legs().isEmpty()) {
            return Long.MAX_VALUE;
        }
        return r.legs().get(0).startTime();
    }

    private List<Integer> allDaySliceOffsets(LocalDate serviceDate, LocalTime serviceTime) {
        LocalDateTime windowStart = LocalDateTime.of(serviceDate, serviceTime);
        LocalDateTime dayEnd = serviceDate.atTime(23, 59, 59);
        List<Integer> out = new ArrayList<>();
        if (windowStart.isAfter(dayEnd)) {
            out.add(0);
            return out;
        }
        LocalDateTime t = windowStart;
        while (!t.isAfter(dayEnd) && out.size() < routeSearchMaxSlices) {
            out.add((int) Duration.between(windowStart, t).toMinutes());
            t = t.plusMinutes(routeSearchSliceStepMinutes);
        }
        return out;
    }

    private String routeSearchSessionKey(UUID cityId, RouteSearchQuery query) {
        int minuteBucket = query.serviceTime().getHour() * 60 + query.serviceTime().getMinute();
        return cityId + "|" + query.origin() + "|" + query.destination()
                + "|" + query.serviceDate() + "|" + minuteBucket;
    }

    private void cleanupExpiredRouteSearchSessionsIfNeeded() {
        if (routeSearchSessionCache.size() < routeSearchCacheMaxEntries) {
            return;
        }
        Instant now = Instant.now();
        AtomicInteger removed = new AtomicInteger(0);
        routeSearchSessionCache.entrySet().removeIf(entry -> {
            boolean expired = entry.getValue().isExpired(now);
            if (expired) {
                removed.incrementAndGet();
            }
            return expired;
        });
        if (routeSearchSessionCache.size() > routeSearchCacheMaxEntries) {
            List<Map.Entry<String, IncrementalRouteSearchSession>> oldestFirst = routeSearchSessionCache.entrySet().stream()
                    .sorted(Comparator.comparing(e -> e.getValue().builtAt()))
                    .toList();
            int toDrop = routeSearchSessionCache.size() - routeSearchCacheMaxEntries;
            for (int i = 0; i < toDrop && i < oldestFirst.size(); i++) {
                routeSearchSessionCache.remove(oldestFirst.get(i).getKey());
                removed.incrementAndGet();
            }
        }
        if (removed.get() > 0) {
            log.debug("routeSearchSessionCache cleanup removed={} size={}", removed.get(), routeSearchSessionCache.size());
        }
    }

    /**
     * Backward-compatible helper retained for tests. In production fast mode we do not use this full-day scan.
     */
    static List<Integer> shiftOffsetsMinutesThroughEndOfServiceDay(LocalDate serviceDate, LocalTime serviceTime) {
        LocalDateTime windowStart = LocalDateTime.of(serviceDate, serviceTime);
        LocalDateTime dayEnd = serviceDate.atTime(23, 59, 59);
        List<Integer> out = new ArrayList<>();
        if (windowStart.isAfter(dayEnd)) {
            out.add(0);
            return out;
        }
        LocalDateTime t = windowStart;
        while (!t.isAfter(dayEnd) && out.size() < 256) {
            out.add((int) Duration.between(windowStart, t).toMinutes());
            t = t.plusMinutes(ROUTE_SEARCH_SHIFT_STEP_MINUTES);
        }
        return out;
    }

    private static RouteSearchQuery shiftServiceTime(RouteSearchQuery base, int plusMinutes) {
        LocalDateTime dt = LocalDateTime.of(base.serviceDate(), base.serviceTime()).plusMinutes(plusMinutes);
        return new RouteSearchQuery(
                base.origin(),
                base.destination(),
                dt.toLocalDate(),
                dt.toLocalTime(),
                base.passengerCount(),
                base.itineraryCount());
    }

    private RouteOptionResponse stripGeometry(RouteOptionResponse option) {
        List<LegResponse> legsWithoutGeometry = option.legs().stream()
                .map(leg -> new LegResponse(
                        leg.mode(),
                        leg.routeId(),
                        leg.fromName(),
                        leg.fromLat(),
                        leg.fromLon(),
                        leg.toName(),
                        leg.toLat(),
                        leg.toLon(),
                        leg.startTime(),
                        leg.endTime(),
                        leg.distance(),
                        List.of(),
                        leg.stops()))
                .toList();
        return new RouteOptionResponse(
                option.durationSeconds(),
                option.transfers(),
                option.walkDistanceMeters(),
                option.estimatedPriceLei(),
                option.fareRule(),
                legsWithoutGeometry);
    }

    /**
     * Collapse only true duplicates across shifted OTP calls (same routes and same scheduled transit legs).
     * Includes endpoints so distinct itineraries are not merged when GTFS route id is missing in the response.
     */
    private static String itineraryDedupKey(RouteOptionResponse r) {
        StringBuilder sb = new StringBuilder();
        for (LegResponse leg : r.legs()) {
            if (leg.mode() != null && "WALK".equalsIgnoreCase(leg.mode().trim())) {
                continue;
            }
            String routeKey = leg.routeId() != null && !leg.routeId().isBlank() ? leg.routeId() : leg.mode();
            sb.append(routeKey).append('|')
                    .append(leg.startTime()).append('|').append(leg.endTime()).append('|')
                    .append(leg.fromName()).append('→').append(leg.toName()).append(';');
        }
        if (!sb.isEmpty()) {
            return sb.toString();
        }
        long firstStart = r.legs().isEmpty() ? 0L : r.legs().get(0).startTime();
        return "walkonly|" + r.durationSeconds() + "|" + r.walkDistanceMeters() + "|" + firstStart;
    }

    private List<RouteOptionResponse> routesFromOtpPlan(JsonNode response) {
        List<RouteOptionResponse> routes = new ArrayList<>();
        JsonNode itineraries = response.path("plan").path("itineraries");
        if (!itineraries.isArray()) {
            return routes;
        }
        for (JsonNode itinerary : itineraries) {
            JsonNode legsNode = itinerary.path("legs");
            routes.add(new RouteOptionResponse(
                    itinerary.path("duration").asLong(0),
                    countTransfersFromLegs(legsNode),
                    Math.round(itinerary.path("walkDistance").asDouble(0)),
                    estimatePriceLei(legsNode),
                    "5 lei / 90 min from first transit boarding",
                    toLegs(legsNode)));
        }
        return routes;
    }

    /**
     * Remove walk-only itineraries whose total or per-leg walk exceeds {@link #MAX_WALK_LEG_METERS_WHEN_TRANSIT}.
     * Remove transit itineraries when any WALK leg exceeds that cap. If the latter would remove every remaining
     * transit option, return the list after walk-only filtering only (still never restores excessive walk-only).
     */
    private List<RouteOptionResponse> applyWalkLegCapWhenTransit(List<RouteOptionResponse> routes) {
        List<RouteOptionResponse> withoutWalkOnlyOverCap = routes.stream()
                .filter(r -> !walkOnlyItineraryExceedsMaxWalk(r))
                .collect(Collectors.toCollection(ArrayList::new));

        List<RouteOptionResponse> filtered = withoutWalkOnlyOverCap.stream()
                .filter(r -> !itineraryHasTransitWithWalkLegOverCap(r))
                .collect(Collectors.toCollection(ArrayList::new));

        if (filtered.isEmpty()
                && withoutWalkOnlyOverCap.stream().anyMatch(this::itineraryHasTransit)) {
            return new ArrayList<>(withoutWalkOnlyOverCap);
        }
        return filtered;
    }

    private boolean itineraryHasTransit(RouteOptionResponse r) {
        return r.legs().stream()
                .anyMatch(leg -> leg.mode() != null && !"WALK".equalsIgnoreCase(leg.mode().trim()));
    }

    private boolean walkOnlyItineraryExceedsMaxWalk(RouteOptionResponse r) {
        if (itineraryHasTransit(r)) {
            return false;
        }
        if (r.walkDistanceMeters() > MAX_WALK_LEG_METERS_WHEN_TRANSIT) {
            return true;
        }
        return r.legs().stream()
                .anyMatch(leg -> leg.mode() != null
                        && "WALK".equalsIgnoreCase(leg.mode().trim())
                        && effectiveWalkLegMeters(leg) > MAX_WALK_LEG_METERS_WHEN_TRANSIT);
    }

    private boolean itineraryHasTransitWithWalkLegOverCap(RouteOptionResponse r) {
        if (!itineraryHasTransit(r)) {
            return false;
        }
        return r.legs().stream().anyMatch(this::walkLegExceedsCapWhenTransitPresent);
    }

    /** Walk length from OTP {@code distance} when present; otherwise straight-line from leg endpoints. */
    private boolean walkLegExceedsCapWhenTransitPresent(LegResponse leg) {
        if (leg.mode() == null || !"WALK".equalsIgnoreCase(leg.mode().trim())) {
            return false;
        }
        return effectiveWalkLegMeters(leg) > MAX_WALK_LEG_METERS_WHEN_TRANSIT;
    }

    private double effectiveWalkLegMeters(LegResponse leg) {
        double meters = leg.distance();
        if (meters <= 0.0) {
            meters = StopSuggestionMerge.distanceMeters(
                    leg.fromLat(), leg.fromLon(), leg.toLat(), leg.toLon());
        }
        return meters;
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

    /**
     * When several GTFS stops share the same rider-facing name, picks the destination stop that yields
     * the best OTP itinerary from {@code origin}: fewer transfers, then shorter duration, then less walking.
     * Falls back to the stop closest to {@code origin} if every plan request fails or is empty.
     */
    public NearbyStopResponse resolveDestinationStopForRoute(
            UUID cityId,
            String origin,
            String stopDisplayName,
            LocalDate serviceDate,
            LocalTime serviceTime) {
        City city = cityRepository.findById(cityId)
                .orElseThrow(() -> new CityNotFoundException(cityId));
        String norm = StopSuggestionMerge.normalizeName(stopDisplayName);
        if (norm.isEmpty()) {
            throw new StopNotFoundException("Empty stop name");
        }
        String cacheKey = destinationResolveCacheKey(cityId, norm, origin, serviceDate, serviceTime);
        NearbyStopResponse cached = readDestinationResolveCache(cacheKey);
        if (cached != null) {
            return cached;
        }
        List<NearbyStopResponse> candidates = gtfsReadService.findStopsByNormalizedName(cityId, norm);
        if (candidates.isEmpty()) {
            throw new StopNotFoundException("No stop matches name: " + stopDisplayName);
        }
        if (candidates.size() == 1) {
            NearbyStopResponse winner = candidates.get(0);
            writeDestinationResolveCache(cacheKey, winner);
            return winner;
        }
        double[] o = parseLatLonCommaSeparated(origin);
        List<NearbyStopResponse> ranked = new ArrayList<>(candidates);
        if (o != null) {
            ranked.sort(Comparator.comparingDouble(
                    c -> StopSuggestionMerge.distanceMeters(o[0], o[1], c.lat(), c.lon())));
        }
        int tryCount = Math.min(MAX_AMBIGUOUS_DESTINATION_CANDIDATES, ranked.size());
        List<NearbyStopResponse> toTry = new ArrayList<>(ranked.subList(0, tryCount));

        List<CompletableFuture<Optional<DestinationResolveScore>>> futures = new ArrayList<>();
        for (NearbyStopResponse c : toTry) {
            futures.add(CompletableFuture.supplyAsync(
                    () -> scoreDestinationCandidate(city, origin, c, serviceDate, serviceTime),
                    stopResolveExecutor));
        }
        @SuppressWarnings("rawtypes")
        CompletableFuture[] arr = futures.toArray(new CompletableFuture[0]);
        CompletableFuture.allOf(arr).join();

        List<DestinationResolveScore> scored = futures.stream()
                .map(CompletableFuture::join)
                .flatMap(Optional::stream)
                .collect(Collectors.toCollection(ArrayList::new));
        if (scored.isEmpty()) {
            log.warn(
                    "resolveDestinationStopForRoute: no itinerary for any candidate name='{}' tried={}",
                    stopDisplayName,
                    toTry.size());
            if (o != null) {
                NearbyStopResponse winner = pickClosestStop(candidates, o[0], o[1]);
                writeDestinationResolveCache(cacheKey, winner);
                return winner;
            }
            NearbyStopResponse winner = candidates.get(0);
            writeDestinationResolveCache(cacheKey, winner);
            return winner;
        }
        scored.sort(Comparator.comparingInt(DestinationResolveScore::transfers)
                .thenComparingLong(DestinationResolveScore::durationSec)
                .thenComparingLong(DestinationResolveScore::walkRounded));
        NearbyStopResponse best = scored.get(0).stop();
        log.info(
                "resolveDestinationStopForRoute: stopId={} name='{}' candidates={}",
                best.stopId(),
                stopDisplayName,
                candidates.size());
        writeDestinationResolveCache(cacheKey, best);
        return best;
    }

    private String destinationResolveCacheKey(
            UUID cityId,
            String normalizedStopName,
            String origin,
            LocalDate serviceDate,
            LocalTime serviceTime) {
        String originCell = "na";
        double[] o = parseLatLonCommaSeparated(origin);
        if (o != null) {
            originCell = String.format(Locale.ROOT, "%.3f,%.3f",
                    Math.round(o[0] * 1000.0) / 1000.0,
                    Math.round(o[1] * 1000.0) / 1000.0);
        }
        int bucket = (serviceTime.getHour() * 60 + serviceTime.getMinute()) / 30;
        return cityId + "|" + normalizedStopName + "|" + originCell + "|" + serviceDate.getDayOfWeek() + "|" + bucket;
    }

    private NearbyStopResponse readDestinationResolveCache(String key) {
        CachedDestinationResolve cached = destinationResolveCache.get(key);
        if (cached == null) {
            return null;
        }
        if (cached.expiresAt().isBefore(Instant.now())) {
            destinationResolveCache.remove(key);
            return null;
        }
        return cached.stop();
    }

    private void writeDestinationResolveCache(String key, NearbyStopResponse stop) {
        destinationResolveCache.put(
                key,
                new CachedDestinationResolve(stop, Instant.now().plus(DESTINATION_RESOLVE_CACHE_TTL)));
    }

    private Optional<DestinationResolveScore> scoreDestinationCandidate(
            City city,
            String origin,
            NearbyStopResponse c,
            LocalDate serviceDate,
            LocalTime serviceTime) {
        String dest = c.lat() + "," + c.lon();
        RouteSearchQuery q = new RouteSearchQuery(
                origin,
                dest,
                serviceDate,
                serviceTime,
                1,
                RESOLVE_PLAN_ITINERARY_COUNT);
        try {
            JsonNode resp = otpClient.searchRoutes(city.getOtpBaseUrl(), q);
            JsonNode itineraries = resp.path("plan").path("itineraries");
            if (!itineraries.isArray() || itineraries.isEmpty()) {
                return Optional.empty();
            }
            JsonNode it = itineraries.get(0);
            JsonNode legs = it.path("legs");
            int tr = countTransfersFromLegs(legs);
            long dur = it.path("duration").asLong(Long.MAX_VALUE / 4);
            long walk = Math.round(it.path("walkDistance").asDouble(1e12));
            return Optional.of(new DestinationResolveScore(c, tr, dur, walk));
        } catch (Exception ex) {
            log.debug("resolveDestinationStopForRoute OTP failed stopId={}: {}", c.stopId(), ex.toString());
            return Optional.empty();
        }
    }

    private static NearbyStopResponse pickClosestStop(
            List<NearbyStopResponse> candidates, double refLat, double refLon) {
        NearbyStopResponse best = candidates.get(0);
        double bestD = StopSuggestionMerge.distanceMeters(refLat, refLon, best.lat(), best.lon());
        for (int i = 1; i < candidates.size(); i++) {
            NearbyStopResponse c = candidates.get(i);
            double d = StopSuggestionMerge.distanceMeters(refLat, refLon, c.lat(), c.lon());
            if (d < bestD) {
                best = c;
                bestD = d;
            }
        }
        return best;
    }

    private static double[] parseLatLonCommaSeparated(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String[] parts = value.split(",");
        if (parts.length != 2) {
            return null;
        }
        try {
            double lat = Double.parseDouble(parts[0].trim());
            double lon = Double.parseDouble(parts[1].trim());
            if (!Double.isFinite(lat) || !Double.isFinite(lon)) {
                return null;
            }
            return new double[] {lat, lon};
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    /**
     * OTP REST/GraphQL payloads often omit {@code transfers} or set it to 0. Derive from legs:
     * one transit vehicle segment = 0 transfers; each additional transit leg = +1 transfer.
     * Walk / bike / car access legs are ignored.
     */
    private static int countTransfersFromLegs(JsonNode legs) {
        if (!legs.isArray()) {
            return 0;
        }
        int transitLegs = 0;
        for (JsonNode leg : legs) {
            String mode = leg.path("mode").asText("");
            if (isTransitLegMode(mode)) {
                transitLegs++;
            }
        }
        return Math.max(0, transitLegs - 1);
    }

    private static boolean isTransitLegMode(String mode) {
        if (mode == null || mode.isBlank()) {
            return false;
        }
        return switch (mode.trim().toUpperCase(Locale.ROOT)) {
            case "WALK",
                    "BICYCLE",
                    "CAR",
                    "CAR_PARK",
                    "CAR_PICKUP",
                    "CAR_RENT",
                    "CAR_HAIL",
                    "SCOOTER" -> false;
            default -> true;
        };
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
                    leg.path("route").path("gtfsId").asText(leg.path("routeId").asText("")),
                    leg.path("from").path("name").asText(""),
                    leg.path("from").path("lat").asDouble(0.0),
                    leg.path("from").path("lon").asDouble(0.0),
                    leg.path("to").path("name").asText(""),
                    leg.path("to").path("lat").asDouble(0.0),
                    leg.path("to").path("lon").asDouble(0.0),
                    leg.path("startTime").asLong(0),
                    leg.path("endTime").asLong(0),
                    leg.path("distance").asDouble(0.0),
                    toGeometry(leg),
                    toStops(leg)
            ));
        }
        return output;
    }

    private List<LegPointResponse> toGeometry(JsonNode leg) {
        JsonNode points = leg.path("legGeometry").path("points");
        if (points.isMissingNode() || points.isNull() || points.asText("").isBlank()) {
            points = leg.path("geometry").path("points");
        }
        if (points.isMissingNode() || points.isNull() || points.asText("").isBlank()) {
            points = leg.path("geometry");
        }
        String encoded = points.asText("");
        if (encoded.isBlank()) {
            return List.of();
        }
        return decodePolyline(encoded);
    }

    private List<LegStopResponse> toStops(JsonNode leg) {
        List<LegStopResponse> output = new ArrayList<>();
        JsonNode via = leg.path("intermediateStops");
        if (via.isArray()) {
            int seq = 1;
            for (JsonNode stop : via) {
                output.add(new LegStopResponse(
                        stop.path("name").asText(""),
                        stop.path("lat").asDouble(0.0),
                        stop.path("lon").asDouble(0.0),
                        stop.path("stopSequence").asInt(seq)
                ));
                seq++;
            }
        }
        if (output.isEmpty()) {
            JsonNode from = leg.path("from");
            JsonNode to = leg.path("to");
            output.add(new LegStopResponse(
                    from.path("name").asText(""),
                    from.path("lat").asDouble(0.0),
                    from.path("lon").asDouble(0.0),
                    1
            ));
            output.add(new LegStopResponse(
                    to.path("name").asText(""),
                    to.path("lat").asDouble(0.0),
                    to.path("lon").asDouble(0.0),
                    2
            ));
        }
        return output;
    }

    private List<LegPointResponse> decodePolyline(String encodedInput) {
        String encoded = encodedInput;
        List<LegPointResponse> poly = new ArrayList<>();
        int index = 0;
        int lat = 0;
        int lon = 0;

        while (index < encoded.length()) {
            int b;
            int shift = 0;
            int result = 0;
            do {
                if (index >= encoded.length()) {
                    return poly;
                }
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
            lat += dlat;

            shift = 0;
            result = 0;
            do {
                if (index >= encoded.length()) {
                    return poly;
                }
                b = encoded.charAt(index++) - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
            lon += dlng;

            poly.add(new LegPointResponse(lat / 1e5, lon / 1e5));
        }
        return poly;
    }
}
