package com.rotransit.backend.service;

import java.time.LocalDate;
import java.time.LocalTime;

public record RouteSearchQuery(
        String origin,
        String destination,
        LocalDate serviceDate,
        LocalTime serviceTime,
        int passengerCount,
        int itineraryCount
) {
}
