package com.rotransit.backend.service;

import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.stereotype.Component;

/**
 * Pure walk-cap rules for OTP itineraries (no I/O).
 */
@Component
public class WalkLegPolicy {
    /** Max walking (meters): drop walk-only itineraries above this; drop transit itineraries with any WALK leg above this. */
    public static final double MAX_WALK_LEG_METERS_WHEN_TRANSIT = 1000.0;

    /**
     * Remove walk-only itineraries whose total or per-leg walk exceeds {@link #MAX_WALK_LEG_METERS_WHEN_TRANSIT}.
     * Remove transit itineraries when any WALK leg exceeds that cap. If the latter would remove every remaining
     * transit option, return the list after walk-only filtering only (still never restores excessive walk-only).
     */
    public List<RouteOptionResponse> applyWalkLegCapWhenTransit(List<RouteOptionResponse> routes) {
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

    public boolean itineraryHasTransit(RouteOptionResponse r) {
        return r.legs().stream()
                .anyMatch(leg -> leg.mode() != null && !"WALK".equalsIgnoreCase(leg.mode().trim()));
    }

    public boolean walkOnlyItineraryExceedsMaxWalk(RouteOptionResponse r) {
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

    public boolean itineraryHasTransitWithWalkLegOverCap(RouteOptionResponse r) {
        if (!itineraryHasTransit(r)) {
            return false;
        }
        return r.legs().stream().anyMatch(this::walkLegExceedsCapWhenTransitPresent);
    }

    /** Walk length from OTP {@code distance} when present; otherwise straight-line from leg endpoints. */
    public boolean walkLegExceedsCapWhenTransitPresent(LegResponse leg) {
        if (leg.mode() == null || !"WALK".equalsIgnoreCase(leg.mode().trim())) {
            return false;
        }
        return effectiveWalkLegMeters(leg) > MAX_WALK_LEG_METERS_WHEN_TRANSIT;
    }

    public double effectiveWalkLegMeters(LegResponse leg) {
        double meters = leg.distance();
        if (meters <= 0.0) {
            meters = StopSuggestionMerge.distanceMeters(
                    leg.fromLat(), leg.fromLon(), leg.toLat(), leg.toLon());
        }
        return meters;
    }
}
