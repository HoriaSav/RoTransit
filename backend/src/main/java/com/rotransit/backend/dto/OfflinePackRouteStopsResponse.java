package com.rotransit.backend.dto;

import java.util.List;

public record OfflinePackRouteStopsResponse(
        String routeId,
        String directionId,
        List<RouteStopResponse> stops
) {
}
