package com.rotransit.backend.dto;

public record LegResponse(
        String mode,
        String routeId,
        String fromName,
        double fromLat,
        double fromLon,
        String toName,
        double toLat,
        double toLon,
        long startTime,
        long endTime,
        double distance,
        java.util.List<LegPointResponse> geometry,
        java.util.List<LegStopResponse> stops
) {
}
