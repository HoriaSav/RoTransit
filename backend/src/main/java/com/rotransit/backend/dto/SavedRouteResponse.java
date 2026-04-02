package com.rotransit.backend.dto;

import java.time.Instant;
import java.util.UUID;

public record SavedRouteResponse(
        UUID id,
        UUID cityId,
        String cityName,
        String label,
        String routeMetadata,
        Instant createdAt
) {
}
