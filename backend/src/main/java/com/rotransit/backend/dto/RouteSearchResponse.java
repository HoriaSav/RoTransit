package com.rotransit.backend.dto;

import java.util.List;
import java.util.UUID;

public record RouteSearchResponse(
        UUID cityId,
        String cityName,
        int offset,
        int limit,
        int total,
        List<RouteOptionResponse> routes
) {
}
