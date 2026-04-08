package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.rotransit.backend.dto.NearbyStopResponse;
import java.util.List;
import org.junit.jupiter.api.Test;

class StopSuggestionMergeTest {

    @Test
    void mergesSameNameWithinRadius() {
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("1", "Rulmentul", 45.66, 25.62),
                new NearbyStopResponse("2", "Rulmentul", 45.66005, 25.62005),
                new NearbyStopResponse("3", "Piata Rulmentul", 45.65, 25.61));
        List<NearbyStopResponse> out =
                StopSuggestionMerge.dedupePreservingRank(raw, 10, null, null);
        assertEquals(2, out.size());
        assertEquals("Rulmentul", out.get(0).name());
        assertEquals("1", out.get(0).stopId());
        assertEquals("Piata Rulmentul", out.get(1).name());
    }

    @Test
    void collapsesSameNameFarApartToSingleSuggestion() {
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("a", "Centru", 45.64, 25.58),
                new NearbyStopResponse("b", "Centru", 45.75, 25.58));
        List<NearbyStopResponse> out =
                StopSuggestionMerge.dedupePreservingRank(raw, 10, null, null);
        assertEquals(1, out.size());
        assertEquals("a", out.get(0).stopId());
    }

    @Test
    void picksClosestToReference() {
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("far", "Rulmentul", 45.6605, 25.6205),
                new NearbyStopResponse("near", "Rulmentul", 45.6601, 25.6201));
        double refLat = 45.66005;
        double refLon = 25.62005;
        List<NearbyStopResponse> out =
                StopSuggestionMerge.dedupePreservingRank(raw, 10, refLat, refLon);
        assertEquals(1, out.size());
        assertEquals("near", out.get(0).stopId());
    }

    @Test
    void respectsMaxResults() {
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("1", "A", 45.0, 25.0),
                new NearbyStopResponse("2", "B", 45.1, 25.1));
        List<NearbyStopResponse> out = StopSuggestionMerge.dedupePreservingRank(raw, 1, null, null);
        assertEquals(1, out.size());
        assertTrue(out.get(0).name().equals("A"));
    }

    @Test
    void nameNormalizationIgnoresExtraSpacesAndCase() {
        List<NearbyStopResponse> raw = List.of(
                new NearbyStopResponse("1", "Rulmentul", 45.66, 25.62),
                new NearbyStopResponse("2", "  RULMENTUL ", 45.66002, 25.62002));
        List<NearbyStopResponse> out =
                StopSuggestionMerge.dedupePreservingRank(raw, 10, null, null);
        assertEquals(1, out.size());
    }
}
