package com.rotransit.backend.dto;

import java.util.List;

public record StopTimetableResponse(
        String cityId,
        String routeId,
        String stopId,
        String serviceDate,
        List<StopTimetableEntryResponse> departures
) {
}
