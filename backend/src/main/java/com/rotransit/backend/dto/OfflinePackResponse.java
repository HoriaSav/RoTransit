package com.rotransit.backend.dto;

import java.util.List;

public record OfflinePackResponse(
        String cityId,
        String anchorMonday,
        String generatedAt,
        String packVersion,
        List<BusLineResponse> buses,
        List<OfflinePackRouteStopsResponse> routeStops,
        List<OfflinePackTimetableEntryResponse> timetables
) {
}
