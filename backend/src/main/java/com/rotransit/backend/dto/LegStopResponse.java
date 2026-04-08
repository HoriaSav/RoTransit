package com.rotransit.backend.dto;

public record LegStopResponse(
        String name,
        double lat,
        double lon,
        int stopSequence
) {
}
