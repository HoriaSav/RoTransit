package com.rotransit.backend.service;

import java.util.UUID;

public class SavedRouteNotFoundException extends RuntimeException {

    public SavedRouteNotFoundException(UUID routeId) {
        super("Saved route not found: " + routeId);
    }
}
