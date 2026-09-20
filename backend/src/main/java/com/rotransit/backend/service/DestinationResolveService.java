package com.rotransit.backend.service;

import com.rotransit.backend.dto.RouteSearchQuery;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.otp.OtpClient;
import com.rotransit.backend.repository.CityRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
public class DestinationResolveService {
    private static final Logger log = LoggerFactory.getLogger(DestinationResolveService.class);

    private static final int MAX_AMBIGUOUS_DESTINATION_CANDIDATES = 12;
    /** One itinerary is enough: OTP returns the best option first. */
    private static final int RESOLVE_PLAN_ITINERARY_COUNT = 1;
    private static final Duration DESTINATION_RESOLVE_CACHE_TTL = Duration.ofMinutes(30);

    private record CachedDestinationResolve(NearbyStopResponse stop, Instant expiresAt) {}

    private record DestinationResolveScore(
            NearbyStopResponse stop, int transfers, long durationSec, long walkRounded) {}

    private final CityRepository cityRepository;
    private final OtpClient otpClient;
    private final GtfsReadService gtfsReadService;
    private final OtpItineraryMapper otpItineraryMapper;
    private final Executor stopResolveExecutor;
    private final Map<String, CachedDestinationResolve> destinationResolveCache = new ConcurrentHashMap<>();

    @Autowired
    public DestinationResolveService(
            CityRepository cityRepository,
            OtpClient otpClient,
            GtfsReadService gtfsReadService,
            OtpItineraryMapper otpItineraryMapper,
            @Qualifier("stopResolveExecutor") Executor stopResolveExecutor) {
        this.cityRepository = cityRepository;
        this.otpClient = otpClient;
        this.gtfsReadService = gtfsReadService;
        this.otpItineraryMapper = otpItineraryMapper;
        this.stopResolveExecutor = stopResolveExecutor;
    }

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
            int tr = otpItineraryMapper.countTransfersFromLegs(legs);
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
}
