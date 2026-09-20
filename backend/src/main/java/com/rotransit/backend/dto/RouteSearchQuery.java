package com.rotransit.backend.dto;

import java.time.LocalDate;
import java.time.LocalTime;

/**
 * OTP / route-search request shape shared by controllers, search service, and OtpClient.
 */
public record RouteSearchQuery(
        String origin,
        String destination,
        LocalDate serviceDate,
        LocalTime serviceTime,
        int passengerCount,
        int itineraryCount
) {
    /** Clamps OTP numItineraries from page offset/limit (was in RouteController). */
    public static int itineraryCountForPage(int offset, int limit) {
        return Math.min(40, Math.max(8, (Math.max(offset, 0) + Math.max(limit, 1)) * 2));
    }

    public static RouteSearchQuery forPagedSearch(
            String origin,
            String destination,
            LocalDate serviceDate,
            LocalTime serviceTime,
            int passengerCount,
            int offset,
            int limit) {
        return new RouteSearchQuery(
                origin,
                destination,
                serviceDate,
                serviceTime,
                passengerCount,
                itineraryCountForPage(offset, limit));
    }
}
