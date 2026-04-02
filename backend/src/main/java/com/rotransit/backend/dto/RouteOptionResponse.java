package com.rotransit.backend.dto;

import java.util.List;

public record RouteOptionResponse(
        long durationSeconds,
        int transfers,
        long walkDistanceMeters,
        int estimatedPriceLei,
        String fareRule,
        List<LegResponse> legs
) {
}
