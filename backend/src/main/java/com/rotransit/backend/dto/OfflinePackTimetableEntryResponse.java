package com.rotransit.backend.dto;

/**
 * Timetable slice for offline storage; {@code dayKind} matches the mobile app (Mon sample / Sat / Sun).
 */
public record OfflinePackTimetableEntryResponse(
        String routeId,
        String stopId,
        String directionId,
        String dayKind,
        StopTimetableResponse timetable
) {
}
