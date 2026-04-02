package com.rotransit.backend.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record SaveRouteRequest(
        @NotBlank String deviceUserId,
        @NotNull UUID cityId,
        String label,
        @NotBlank String routeMetadata
) {
}
