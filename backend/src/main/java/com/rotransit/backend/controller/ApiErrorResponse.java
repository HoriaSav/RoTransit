package com.rotransit.backend.controller;

import java.time.Instant;
import java.util.Map;

public record ApiErrorResponse(
        Instant timestamp,
        String error,
        String code,
        String message,
        String requestId,
        Map<String, Object> details
) {
}
