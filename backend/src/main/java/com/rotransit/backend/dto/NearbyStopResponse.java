package com.rotransit.backend.dto;

public record NearbyStopResponse(
        String stopId,
        String name,
        double lat,
        double lon
) {
}
