package com.rotransit.backend.dto;

/**
 * Lightweight manifest for offline-pack sync (no buses / stops / timetable payload).
 */
public record OfflinePackMetaResponse(
        String cityId,
        String anchorMonday,
        String packVersion,
        String generatedAt
) {
}
