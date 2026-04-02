package com.rotransit.backend.dto;

public record BusLineResponse(
        String routeId,
        String shortName,
        String longName,
        String mode
) {
}
