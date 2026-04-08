package com.rotransit.backend.controller;

import com.rotransit.backend.dto.NearbyStopResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.service.RouteSearchQuery;
import com.rotransit.backend.service.RouteService;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api")
public class RouteController {

    private final RouteService routeService;

    public RouteController(RouteService routeService) {
        this.routeService = routeService;
    }

    @GetMapping("/routes/search")
    public RouteSearchResponse searchRoutes(
            @RequestParam UUID cityId,
            @RequestParam @NotBlank String origin,
            @RequestParam @NotBlank String destination,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate serviceDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.TIME) LocalTime serviceTime,
            @RequestParam(defaultValue = "1") @Min(1) @Max(10) int passengerCount,
            @RequestParam(defaultValue = "0") @Min(0) int offset,
            @RequestParam(defaultValue = "10") @Min(1) @Max(50) int limit
    ) {
        int itineraryCount = Math.min(100, Math.max(offset + limit, limit));
        return routeService.searchRoutes(cityId, new RouteSearchQuery(
                origin,
                destination,
                serviceDate,
                serviceTime,
                passengerCount,
                itineraryCount
        ), offset, limit);
    }

    @GetMapping("/stops/nearby")
    public List<NearbyStopResponse> getNearbyStops(
            @RequestParam UUID cityId,
            @RequestParam @Min(-90) @Max(90) double lat,
            @RequestParam @Min(-180) @Max(180) double lon,
            @RequestParam(defaultValue = "500") @Min(50) @Max(5000) int radiusMeters
    ) {
        return routeService.nearbyStops(cityId, lat, lon, radiusMeters);
    }

    @GetMapping("/stops/search")
    public List<NearbyStopResponse> searchStops(
            @RequestParam UUID cityId,
            @RequestParam @NotBlank String q,
            @RequestParam(defaultValue = "10") @Min(1) @Max(20) int limit,
            @RequestParam(required = false) @Min(-90) @Max(90) Double refLat,
            @RequestParam(required = false) @Min(-180) @Max(180) Double refLon
    ) {
        Double lat = null;
        Double lon = null;
        if (refLat != null && refLon != null) {
            lat = refLat;
            lon = refLon;
        }
        return routeService.searchStops(cityId, q, limit, lat, lon);
    }

    /**
     * Picks the concrete GTFS stop for a rider-facing name by comparing OTP itineraries from {@code origin}
     * (fewer transfers, then shorter trip time, then less walking).
     */
    @GetMapping("/stops/resolve-for-route")
    public NearbyStopResponse resolveStopForRoute(
            @RequestParam UUID cityId,
            @RequestParam @NotBlank String origin,
            @RequestParam @NotBlank String stopName,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate serviceDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.TIME) LocalTime serviceTime
    ) {
        return routeService.resolveDestinationStopForRoute(cityId, origin, stopName, serviceDate, serviceTime);
    }
}
