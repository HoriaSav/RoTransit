package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.LegPointResponse;
import com.rotransit.backend.dto.LegStopResponse;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.BusLineResponse;
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
import com.rotransit.backend.repository.CityRepository;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.stream.Collectors;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
public class RouteService {
    private static final Logger log = LoggerFactory.getLogger(RouteService.class);

    /** Max walking (meters): drop walk-only itineraries above this; drop transit itineraries with any WALK leg above this. */
    private static final double MAX_WALK_LEG_METERS_WHEN_TRANSIT = 1000.0;

    /** Step between OTP plan requests while scanning the rest of the service calendar day. */
    private static final int ROUTE_SEARCH_SHIFT_STEP_MINUTES = 15;

    /**
     * Hard cap on OTP plan calls per user search (full-day scan can be long; protects OTP and timeouts).
     */
    private static final int MAX_OTP_PLAN_CALLS_PER_SEARCH = 256;

    /** Max distinct itineraries returned (payload / UI bounds). */
    private static final int ROUTE_SEARCH_MERGED_CAP = 400;

    private static final int MAX_AMBIGUOUS_DESTINATION_CANDIDATES = 12;
    /** One itinerary is enough: OTP returns the best option first. */
    private static final int RESOLVE_PLAN_ITINERARY_COUNT = 1;

    private record DestinationResolveScore(
            NearbyStopResponse stop, int transfers, long durationSec, long walkRounded) {}

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final GtfsReadService gtfsReadService;
    private final Executor stopResolveExecutor;

    public RouteService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            @Qualifier("stopResolveExecutor") Executor stopResolveExecutor) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
        this.stopResolveExecutor = stopResolveExecutor;
    }

    public RouteSearchResponse searchRoutes(UUID cityId, RouteSearchQuery query, int offset, int limit) {
        City city = cityRepository.findById(cityId)
                .orElseThrow(() -> new CityNotFoundException(cityId));
        log.info("searchRoutes cityId={} origin={} destination={} offset={} limit={}",
                cityId, query.origin(), query.destination(), offset, limit);

        int safeLimit = Math.max(limit, 1);
        List<RouteOptionResponse> routes =
                mergeRoutesFromShiftedDepartureSearches(city.getOtpBaseUrl(), query);
        routes.sort(Comparator
                .comparingLong(RouteService::departureSortKey)
                .thenComparingInt(RouteOptionResponse::transfers)
                .thenComparingLong(RouteOptionResponse::durationSeconds));
        return new RouteSearchResponse(
                city.getId(),
                city.getName(),
                0,
                safeLimit,
                routes.size(),
                routes
        );
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

    /**
     * OTP plan times: requested departure, then +{@link #ROUTE_SEARCH_SHIFT_STEP_MINUTES} until end of
     * {@code serviceDate} (23:59:59), deduplicating itineraries across calls.
     */
    private List<RouteOptionResponse> mergeRoutesFromShiftedDepartureSearches(
            String otpBaseUrl, RouteSearchQuery query) {
        List<Integer> plusMinutesList = shiftOffsetsMinutesThroughEndOfServiceDay(
                query.serviceDate(), query.serviceTime());
        List<RouteOptionResponse> merged = new ArrayList<>();
        Set<String> seenKeys = new HashSet<>();
        for (int plusMinutes : plusMinutesList) {
            if (merged.size() >= ROUTE_SEARCH_MERGED_CAP) {
                break;
            }
            RouteSearchQuery shifted = plusMinutes == 0 ? query : shiftServiceTime(query, plusMinutes);
            JsonNode response = otpClient.searchRoutes(otpBaseUrl, shifted);
            List<RouteOptionResponse> batch = routesFromOtpPlan(response);
            for (RouteOptionResponse route : batch) {
                String key = itineraryDedupKey(route);
                if (seenKeys.add(key)) {
                    merged.add(route);
                    if (merged.size() >= ROUTE_SEARCH_MERGED_CAP) {
                        break;
                    }
                }
            }
            if (merged.size() >= ROUTE_SEARCH_MERGED_CAP) {
                break;
            }
        }
        // One pass on the full pool: drop transit trips with any WALK leg > 1 km (see below). Per-batch
        // fallback used to re-inject long walks from other time slices; global fallback keeps UX if OTP
        // only returns such itineraries.
        return applyWalkLegCapWhenTransit(merged);
    }

    /**
     * Minute offsets from the user’s {@code serviceTime} through the end of {@code serviceDate} (inclusive),
     * stepping by {@link #ROUTE_SEARCH_SHIFT_STEP_MINUTES}, capped by {@link #MAX_OTP_PLAN_CALLS_PER_SEARCH}.
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
        while (!t.isAfter(dayEnd) && out.size() < MAX_OTP_PLAN_CALLS_PER_SEARCH) {
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

    /**
     * Builds a single JSON document for mobile offline mode: all bus lines, per-direction stops,
     * and Mon/Sat/Sun timetable slices (aligned with the app's week anchor Monday).
     */
    public OfflinePackResponse buildOfflinePack(UUID cityId, LocalDate anchorMonday) {
        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId));
        LocalDate saturday = anchorMonday.plusDays(5);
        LocalDate sunday = anchorMonday.plusDays(6);
        Instant generatedAt = Instant.now();

        List<BusLineResponse> buses = gtfsReadService.listBusLines(cityId);
        List<OfflinePackRouteStopsResponse> routeStopsOut = new ArrayList<>();
        List<OfflinePackTimetableEntryResponse> timetablesOut = new ArrayList<>();

        record DaySlice(LocalDate date, String dayKind) {}
        List<DaySlice> daySlices = List.of(
                new DaySlice(anchorMonday, "MONFRI"),
                new DaySlice(saturday, "SATURDAY"),
                new DaySlice(sunday, "SUNDAY")
        );

        String[] directions = {"0", "1"};
        for (BusLineResponse line : buses) {
            String routeId = line.routeId();
            for (String directionId : directions) {
                List<RouteStopResponse> stops = gtfsReadService.routeStops(cityId, routeId, directionId);
                if (stops.isEmpty()) {
                    continue;
                }
                routeStopsOut.add(new OfflinePackRouteStopsResponse(routeId, directionId, stops));
                for (RouteStopResponse stop : stops) {
                    for (DaySlice day : daySlices) {
                        List<StopTimetableEntryResponse> departures = gtfsReadService.routeStopTimes(
                                cityId, routeId, stop.stopId(), day.date(), directionId);
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

        log.info("buildOfflinePack cityId={} buses={} routeStopSlices={} timetableSlices={} anchorMonday={}",
                cityId, buses.size(), routeStopsOut.size(), timetablesOut.size(), anchorMonday);

        return new OfflinePackResponse(
                cityId.toString(),
                anchorMonday.toString(),
                generatedAt.toString(),
                buses,
                routeStopsOut,
                timetablesOut
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
        List<NearbyStopResponse> candidates = gtfsReadService.findStopsByNormalizedName(cityId, norm);
        if (candidates.isEmpty()) {
            throw new StopNotFoundException("No stop matches name: " + stopDisplayName);
        }
        if (candidates.size() == 1) {
            return candidates.get(0);
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
                return pickClosestStop(candidates, o[0], o[1]);
            }
            return candidates.get(0);
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
        return best;
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
