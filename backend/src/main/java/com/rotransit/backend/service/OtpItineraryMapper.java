package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.rotransit.backend.dto.LegPointResponse;
import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.LegStopResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Component;

/**
 * OTP JsonNode → product DTOs (ACL mapping). Stays out of the HTTP client.
 */
@Component
public class OtpItineraryMapper {

    public List<RouteOptionResponse> routesFromOtpPlan(JsonNode response) {
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

    public RouteOptionResponse stripGeometry(RouteOptionResponse option) {
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
     * OTP REST/GraphQL payloads often omit {@code transfers} or set it to 0. Derive from legs:
     * one transit vehicle segment = 0 transfers; each additional transit leg = +1 transfer.
     * Walk / bike / car access legs are ignored.
     */
    public int countTransfersFromLegs(JsonNode legs) {
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

    public boolean isTransitLegMode(String mode) {
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

    public int estimatePriceLei(JsonNode legs) {
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

    public List<LegResponse> toLegs(JsonNode legs) {
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

    public List<LegPointResponse> toGeometry(JsonNode leg) {
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

    public List<LegStopResponse> toStops(JsonNode leg) {
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

    public List<LegPointResponse> decodePolyline(String encodedInput) {
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
