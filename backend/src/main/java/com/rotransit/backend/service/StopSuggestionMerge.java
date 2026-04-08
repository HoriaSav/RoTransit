package com.rotransit.backend.service;

import com.rotransit.backend.dto.NearbyStopResponse;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Merges GTFS/OTP stop rows that describe the same rider-facing place (identical
 * normalized name and within about 120 m). The kept stop is the one closest to optional
 * reference coordinates (search/nearby origin), else the earliest in the incoming
 * ranking (SQL prefix order).
 * <p>
 * A second pass collapses duplicate normalized names in the result so the suggestion
 * list never shows two rows the user cannot distinguish (e.g. opposite platforms);
 * among same-named stops, the representative closest to the reference point wins.
 */
public final class StopSuggestionMerge {

    static final double MERGE_RADIUS_METERS = 120.0;
    private static final double EARTH_RADIUS_M = 6_371_000.0;

    private StopSuggestionMerge() {}

    public static List<NearbyStopResponse> dedupePreservingRank(
            List<NearbyStopResponse> ordered,
            int maxResults,
            Double refLat,
            Double refLon) {
        if (ordered == null || ordered.isEmpty() || maxResults <= 0) {
            return List.of();
        }
        int n = ordered.size();
        int[] parent = new int[n];
        for (int i = 0; i < n; i++) {
            parent[i] = i;
        }
        for (int i = 0; i < n; i++) {
            String na = normalizeName(ordered.get(i).name());
            if (na.isEmpty()) {
                continue;
            }
            for (int j = i + 1; j < n; j++) {
                if (!na.equals(normalizeName(ordered.get(j).name()))) {
                    continue;
                }
                NearbyStopResponse a = ordered.get(i);
                NearbyStopResponse b = ordered.get(j);
                if (distanceMeters(a.lat(), a.lon(), b.lat(), b.lon()) <= MERGE_RADIUS_METERS) {
                    union(parent, i, j);
                }
            }
        }
        Map<Integer, List<Integer>> byRoot = new HashMap<>();
        for (int i = 0; i < n; i++) {
            int r = find(parent, i);
            byRoot.computeIfAbsent(r, k -> new ArrayList<>()).add(i);
        }
        List<List<Integer>> clusters = new ArrayList<>(byRoot.values());
        clusters.sort(Comparator.comparingInt(idxs -> Collections.min(idxs)));

        List<NearbyStopResponse> spatial = new ArrayList<>();
        for (List<Integer> idxs : clusters) {
            spatial.add(pickRepresentative(ordered, idxs, refLat, refLon));
            if (spatial.size() >= maxResults) {
                break;
            }
        }
        return collapseDuplicateNormalizedNames(spatial, maxResults, refLat, refLon);
    }

    /**
     * At most one row per normalized stop name; keeps ranking order of first appearance.
     */
    private static List<NearbyStopResponse> collapseDuplicateNormalizedNames(
            List<NearbyStopResponse> ordered,
            int maxResults,
            Double refLat,
            Double refLon) {
        if (ordered.isEmpty() || maxResults <= 0) {
            return List.of();
        }
        Map<String, NearbyStopResponse> winner = new HashMap<>();
        Map<String, Integer> winnerIndex = new HashMap<>();
        List<NearbyStopResponse> unnamed = new ArrayList<>();
        for (int i = 0; i < ordered.size(); i++) {
            NearbyStopResponse s = ordered.get(i);
            String k = normalizeName(s.name());
            if (k.isEmpty()) {
                unnamed.add(s);
                continue;
            }
            if (!winner.containsKey(k)) {
                winner.put(k, s);
                winnerIndex.put(k, i);
            } else {
                NearbyStopResponse w = winner.get(k);
                int wi = winnerIndex.get(k);
                NearbyStopResponse better = pickBetterByRefOrIndex(w, wi, s, i, refLat, refLon);
                if (better == s) {
                    winner.put(k, s);
                    winnerIndex.put(k, i);
                }
            }
        }
        List<NearbyStopResponse> out = new ArrayList<>();
        Set<String> emitted = new HashSet<>();
        for (NearbyStopResponse s : ordered) {
            if (out.size() >= maxResults) {
                break;
            }
            String k = normalizeName(s.name());
            if (k.isEmpty()) {
                continue;
            }
            if (emitted.contains(k)) {
                continue;
            }
            emitted.add(k);
            out.add(winner.get(k));
        }
        for (NearbyStopResponse s : unnamed) {
            if (out.size() >= maxResults) {
                break;
            }
            out.add(s);
        }
        return out;
    }

    private static NearbyStopResponse pickBetterByRefOrIndex(
            NearbyStopResponse a,
            int indexA,
            NearbyStopResponse b,
            int indexB,
            Double refLat,
            Double refLon) {
        if (refLat != null && refLon != null) {
            double da = distanceMeters(refLat, refLon, a.lat(), a.lon());
            double db = distanceMeters(refLat, refLon, b.lat(), b.lon());
            if (db < da - 1e-6) {
                return b;
            }
            if (da < db - 1e-6) {
                return a;
            }
        }
        return indexA <= indexB ? a : b;
    }

    static String normalizeName(String name) {
        if (name == null) {
            return "";
        }
        return name.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);
    }

    static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
        double phi1 = Math.toRadians(lat1);
        double phi2 = Math.toRadians(lat2);
        double dPhi = Math.toRadians(lat2 - lat1);
        double dLambda = Math.toRadians(lon2 - lon1);
        double x = Math.sin(dPhi / 2) * Math.sin(dPhi / 2)
                + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) * Math.sin(dLambda / 2);
        return 2 * EARTH_RADIUS_M * Math.atan2(Math.sqrt(x), Math.sqrt(Math.max(0, 1 - x)));
    }

    private static NearbyStopResponse pickRepresentative(
            List<NearbyStopResponse> ordered,
            List<Integer> idxs,
            Double refLat,
            Double refLon) {
        if (refLat != null && refLon != null) {
            int best = idxs.get(0);
            double bestD = distanceMeters(refLat, refLon, ordered.get(best).lat(), ordered.get(best).lon());
            for (int k = 1; k < idxs.size(); k++) {
                int i = idxs.get(k);
                double d = distanceMeters(refLat, refLon, ordered.get(i).lat(), ordered.get(i).lon());
                if (d < bestD - 1e-6) {
                    best = i;
                    bestD = d;
                } else if (Math.abs(d - bestD) <= 1e-6 && i < best) {
                    best = i;
                }
            }
            return ordered.get(best);
        }
        int minIdx = idxs.stream().mapToInt(Integer::intValue).min().orElse(0);
        return ordered.get(minIdx);
    }

    private static int find(int[] parent, int i) {
        if (parent[i] != i) {
            parent[i] = find(parent, parent[i]);
        }
        return parent[i];
    }

    private static void union(int[] parent, int a, int b) {
        int ra = find(parent, a);
        int rb = find(parent, b);
        if (ra != rb) {
            parent[rb] = ra;
        }
    }
}
