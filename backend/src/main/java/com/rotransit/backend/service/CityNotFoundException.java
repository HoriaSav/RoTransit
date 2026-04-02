package com.rotransit.backend.service;

import java.util.UUID;

public class CityNotFoundException extends RuntimeException {

    public CityNotFoundException(UUID cityId) {
        super("City not found: " + cityId);
    }
}
