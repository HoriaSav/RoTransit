package com.rotransit.backend.dto;

public record RouteStopResponse(
        String stopId,
        String name,
        double lat,
        double lon,
        int stopSequence
) {
}
