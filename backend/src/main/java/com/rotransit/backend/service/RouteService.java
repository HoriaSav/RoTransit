package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.LegPointResponse;
import com.rotransit.backend.dto.LegStopResponse;
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
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.stream.Collectors;
import java.time.LocalDate;
import java.time.LocalTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
public class RouteService {
    private static final Logger log = LoggerFactory.getLogger(RouteService.class);

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

        JsonNode response = otpClient.searchRoutes(city.getOtpBaseUrl(), query);
        List<RouteOptionResponse> routes = new ArrayList<>();
        JsonNode itineraries = response.path("plan").path("itineraries");
        if (itineraries.isArray()) {
            for (JsonNode itinerary : itineraries) {
                JsonNode legsNode = itinerary.path("legs");
                routes.add(new RouteOptionResponse(
                        itinerary.path("duration").asLong(0),
                        countTransfersFromLegs(legsNode),
                        Math.round(itinerary.path("walkDistance").asDouble(0)),
                        estimatePriceLei(legsNode),
                        "5 lei / 90 min from first transit boarding",
                        toLegs(legsNode)
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
