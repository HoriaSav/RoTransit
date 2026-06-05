package com.rotransit.backend.controller;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.BusLineResponse;
import com.rotransit.backend.dto.OfflinePackMetaResponse;
import com.rotransit.backend.dto.OfflinePackResponse;
import com.rotransit.backend.dto.RouteStopResponse;
import com.rotransit.backend.dto.StopTimetableResponse;
import com.rotransit.backend.service.RouteService;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api/buses")
public class TransitCatalogController {

    private final RouteService routeService;
    private final ObjectMapper objectMapper;

    public TransitCatalogController(RouteService routeService, ObjectMapper objectMapper) {
        this.routeService = routeService;
        this.objectMapper = objectMapper;
    }

    @GetMapping
    public List<BusLineResponse> listBuses(@RequestParam UUID cityId) {
        return routeService.listBusLines(cityId);
    }

    @GetMapping("/offline-pack-meta")
    public OfflinePackMetaResponse offlinePackMeta(
            @RequestParam UUID cityId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate anchorMonday
    ) {
        return routeService.buildOfflinePackMeta(cityId, anchorMonday);
    }

    @GetMapping("/offline-pack")
    public ResponseEntity<byte[]> offlinePack(
            @RequestParam UUID cityId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate anchorMonday
    ) throws JsonProcessingException {
        OfflinePackResponse pack = routeService.buildOfflinePack(cityId, anchorMonday);
        byte[] body = objectMapper.writeValueAsBytes(pack);
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .contentLength(body.length)
                .body(body);
    }

    @GetMapping("/{routeId}/stops")
    public List<RouteStopResponse> routeStops(
            @PathVariable @NotBlank String routeId,
            @RequestParam UUID cityId,
            @RequestParam(required = false) String directionId
    ) {
        return routeService.routeStops(cityId, routeId, directionId);
    }

    @GetMapping("/{routeId}/timetable")
    public StopTimetableResponse routeTimetable(
            @PathVariable @NotBlank String routeId,
            @RequestParam UUID cityId,
            @RequestParam @NotBlank String stopId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate serviceDate,
            @RequestParam(required = false) String directionId
    ) {
        return routeService.routeStopTimes(cityId, routeId, stopId, serviceDate, directionId);
    }
}
