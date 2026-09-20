package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class WalkLegPolicyTest {

    private WalkLegPolicy policy;

    @BeforeEach
    void setUp() {
        policy = new WalkLegPolicy();
    }

    private static LegResponse walk(double distance, double fromLat, double fromLon, double toLat, double toLon) {
        return new LegResponse(
                "WALK", null, "A", fromLat, fromLon, "B", toLat, toLon, 0, 1, distance, List.of(), List.of());
    }

    private static LegResponse bus() {
        return new LegResponse(
                "BUS", "R1", "A", 45.0, 25.0, "B", 45.01, 25.01, 0, 1, 1000, List.of(), List.of());
    }

    private static RouteOptionResponse option(long walkMeters, LegResponse... legs) {
        return new RouteOptionResponse(100, 0, walkMeters, 0, "rule", List.of(legs));
    }

    @Test
    void applyWalkLegCapWhenTransitDropsLongWalkWhenAlternativeExists() {
        RouteOptionResponse bad = option(1200, walk(1200, 0, 0, 0, 0), bus());
        RouteOptionResponse good = option(100, walk(100, 0, 0, 0, 0), bus());

        List<RouteOptionResponse> out = policy.applyWalkLegCapWhenTransit(List.of(bad, good));

        assertEquals(1, out.size());
        assertEquals(100L, out.get(0).walkDistanceMeters());
    }

    @Test
    void applyWalkLegCapWhenTransitFallsBackWhenCapWouldRemoveAllTransit() {
        RouteOptionResponse only = option(1200, walk(1200, 0, 0, 0, 0), bus());
        assertEquals(1, policy.applyWalkLegCapWhenTransit(List.of(only)).size());
    }

    @Test
    void applyWalkLegCapWhenTransitRemovesWalkOnlyOverCapAndNeverRestoresIt() {
        RouteOptionResponse walkOnly = option(2000, walk(2000, 0, 0, 0, 0));
        RouteOptionResponse transitOverCap = option(1200, walk(1200, 0, 0, 0, 0), bus());

        List<RouteOptionResponse> out = policy.applyWalkLegCapWhenTransit(List.of(walkOnly, transitOverCap));

        assertEquals(1, out.size());
        assertTrue(policy.itineraryHasTransit(out.get(0)));
    }

    @Test
    void effectiveWalkLegMetersFallsBackToHaversineWhenDistanceMissing() {
        // ~0.01 deg latitude ≈ 1.1 km > MAX_WALK_LEG_METERS_WHEN_TRANSIT
        LegResponse leg = walk(0.0, 45.0, 25.0, 45.01, 25.0);
        double meters = policy.effectiveWalkLegMeters(leg);
        assertTrue(meters > WalkLegPolicy.MAX_WALK_LEG_METERS_WHEN_TRANSIT, "got " + meters);
        assertTrue(policy.walkLegExceedsCapWhenTransitPresent(leg));
    }

    @Test
    void walkOnlyItineraryExceedsMaxWalkUsesTotalWalkDistance() {
        assertTrue(policy.walkOnlyItineraryExceedsMaxWalk(option(1500, walk(400, 0, 0, 0, 0))));
        assertFalse(policy.walkOnlyItineraryExceedsMaxWalk(option(400, walk(400, 0, 0, 0, 0))));
    }
}
