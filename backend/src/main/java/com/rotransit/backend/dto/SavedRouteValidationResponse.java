package com.rotransit.backend.dto;

public record SavedRouteValidationResponse(
        boolean isValid,
        String reason
) {
}
