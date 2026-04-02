package com.rotransit.backend.controller;

import com.rotransit.backend.dto.SaveRouteRequest;
import com.rotransit.backend.dto.SavedRouteValidationResponse;
import com.rotransit.backend.dto.SavedRouteResponse;
import com.rotransit.backend.service.SavedRouteService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/api/routes")
public class SavedRouteController {

    private final SavedRouteService savedRouteService;

    public SavedRouteController(SavedRouteService savedRouteService) {
        this.savedRouteService = savedRouteService;
    }

    @PostMapping("/save")
    @ResponseStatus(HttpStatus.CREATED)
    public SavedRouteResponse save(@RequestBody @Valid SaveRouteRequest request) {
        return savedRouteService.saveRoute(request);
    }

    @GetMapping("/saved")
    public List<SavedRouteResponse> getSavedRoutes(
            @RequestParam @NotBlank String deviceUserId,
            @RequestParam(required = false) UUID cityId
    ) {
        return savedRouteService.getSavedRoutes(deviceUserId, cityId);
    }

    @DeleteMapping("/saved/{routeId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteSavedRoute(
            @PathVariable UUID routeId,
            @RequestParam @NotBlank String deviceUserId
    ) {
        savedRouteService.deleteRoute(deviceUserId, routeId);
    }

    @GetMapping("/saved/{routeId}/validate")
    public SavedRouteValidationResponse validateSavedRoute(
            @PathVariable UUID routeId,
            @RequestParam @NotBlank String deviceUserId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate serviceDate,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.TIME) LocalTime serviceTime
    ) {
        return savedRouteService.validateSavedRoute(routeId, deviceUserId, serviceDate, serviceTime);
    }
}
