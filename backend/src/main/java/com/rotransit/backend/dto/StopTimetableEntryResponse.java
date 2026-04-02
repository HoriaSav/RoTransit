package com.rotransit.backend.dto;

public record StopTimetableEntryResponse(
        String tripId,
        String headsign,
        String departureTime
) {
}
