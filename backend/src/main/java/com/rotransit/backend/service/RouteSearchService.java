package com.rotransit.backend.service;

import com.rotransit.backend.dto.RouteSearchQuery;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.otp.OtpException;
import com.rotransit.backend.repository.CityRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class RouteSearchService {
    private static final Logger log = LoggerFactory.getLogger(RouteSearchService.class);

    /** Step between OTP plan requests when asking for additional windows. */
    private static final int ROUTE_SEARCH_SHIFT_STEP_MINUTES = 15;

    /** Max distinct itineraries returned (payload / UI bounds). */
    private static final int ROUTE_SEARCH_MERGED_CAP = 120;

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

        /** OTP returned no itineraries (e.g. still starting up); do not cache — allow immediate retry. */
        private boolean isUnproductive() {
            return scanComplete && rawMerged.isEmpty();
        }
    }

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final OtpItineraryMapper otpItineraryMapper;
    private final WalkLegPolicy walkLegPolicy;
    private final Executor stopResolveExecutor;
    private final int additionalSearchWindows;
    private final int maxAdditionalSearchWindows;
    private final Map<String, IncrementalRouteSearchSession> routeSearchSessionCache = new ConcurrentHashMap<>();
    private final int routeSearchSliceStepMinutes;
    private final int routeSearchMaxSlices;
    private final int routeSearchParallelWorkers;
    private final int routeSearchWindowMinutes;
    private final int routeSearchSessionTtlSeconds;
    private final int routeSearchCacheMaxEntries;
    private final boolean routeSearchWindowFirstEnabled;
    private final ZoneId serviceZoneId;

    @Autowired
    public RouteSearchService(
            CityRepository cityRepository,
            OtpClient otpClient,
            OtpItineraryMapper otpItineraryMapper,
            WalkLegPolicy walkLegPolicy,
            @Qualifier("stopResolveExecutor") Executor stopResolveExecutor,
            @Value("${rotransit.routes.search.additional-windows:0}") int additionalSearchWindows,
            @Value("${rotransit.routes.search.max-additional-windows:3}") int maxAdditionalSearchWindows,
            @Value("${rotransit.routes.search.slice-step-minutes:15}") int routeSearchSliceStepMinutes,
            @Value("${rotransit.routes.search.max-slices:64}") int routeSearchMaxSlices,
            @Value("${rotransit.routes.search.parallel-workers:6}") int routeSearchParallelWorkers,
            @Value("${rotransit.routes.search.window-minutes:120}") int routeSearchWindowMinutes,
            @Value("${rotransit.routes.search.session-ttl-seconds:120}") int routeSearchSessionTtlSeconds,
            @Value("${rotransit.routes.search.cache-max-entries:128}") int routeSearchCacheMaxEntries,
            @Value("${rotransit.routes.search.window-first-enabled:true}") boolean routeSearchWindowFirstEnabled,
            @Value("${rotransit.service-timezone:Europe/Bucharest}") String serviceTimezone) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.otpItineraryMapper = otpItineraryMapper;
        this.walkLegPolicy = walkLegPolicy;
        this.stopResolveExecutor = stopResolveExecutor;
        this.additionalSearchWindows = Math.max(0, additionalSearchWindows);
        this.maxAdditionalSearchWindows = Math.max(0, maxAdditionalSearchWindows);
        this.routeSearchSliceStepMinutes = Math.max(1, routeSearchSliceStepMinutes);
        this.routeSearchMaxSlices = Math.max(1, routeSearchMaxSlices);
        this.routeSearchParallelWorkers = Math.max(1, routeSearchParallelWorkers);
        this.routeSearchWindowMinutes = Math.max(1, routeSearchWindowMinutes);
        this.routeSearchSessionTtlSeconds = Math.max(5, routeSearchSessionTtlSeconds);
        this.routeSearchCacheMaxEntries = Math.max(16, routeSearchCacheMaxEntries);
        this.routeSearchWindowFirstEnabled = routeSearchWindowFirstEnabled;
        this.serviceZoneId = ZoneId.of(serviceTimezone);
    }

    /** Test / façade helper with the same defaults as the old RouteService 4-arg constructor. */
    public RouteSearchService(
            CityRepository cityRepository,
            OtpClient otpClient,
            OtpItineraryMapper otpItineraryMapper,
            WalkLegPolicy walkLegPolicy,
            Executor stopResolveExecutor) {
        this(cityRepository, otpClient, otpItineraryMapper, walkLegPolicy, stopResolveExecutor, 0, 3,
                ROUTE_SEARCH_SHIFT_STEP_MINUTES, 64, 6, 120, 120, 128, true,
                "Europe/Bucharest");
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
        if (cacheHit && session.isUnproductive()) {
            routeSearchSessionCache.remove(sessionKey);
            session = null;
            cacheHit = false;
        }
        if (session == null) {
            session = newIncrementalSession(city.getOtpBaseUrl(), query, now);
        }
        int targetSize = safeOffset + safeLimit;
        fillSessionUntil(session, targetSize);
        if (session.isUnproductive()) {
            routeSearchSessionCache.remove(sessionKey);
        } else {
            routeSearchSessionCache.put(sessionKey, session);
        }
        List<RouteOptionResponse> routes = session.routes();
        int total = routes.size();
        boolean hasMore = !session.scanComplete();
        int fromIndex = Math.min(safeOffset, total);
        int toIndex = Math.min(fromIndex + safeLimit, total);
        List<RouteOptionResponse> page = routes.subList(fromIndex, toIndex);
        List<RouteOptionResponse> responseRoutes = includeGeometry
                ? page
                : page.stream().map(otpItineraryMapper::stripGeometry).toList();
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
                .atZone(serviceZoneId)
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
                    appendRoutesDedup(session, otpItineraryMapper.routesFromOtpPlan(windowResponse));
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
                    return otpItineraryMapper.routesFromOtpPlan(response);
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
        List<RouteOptionResponse> capped = walkLegPolicy.applyWalkLegCapWhenTransit(merged);
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
                .comparingLong(RouteSearchService::departureSortKey)
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
}
