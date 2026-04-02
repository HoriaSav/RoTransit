package com.rotransit.backend.dto;

public record LegResponse(
        String mode,
        String fromName,
        String toName,
        long startTime,
        long endTime,
        double distance
) {
}
