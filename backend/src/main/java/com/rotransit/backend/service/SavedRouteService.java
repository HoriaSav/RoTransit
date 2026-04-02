package com.rotransit.backend.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rotransit.backend.dto.SaveRouteRequest;
import com.rotransit.backend.dto.SavedRouteValidationResponse;
import com.rotransit.backend.dto.SavedRouteResponse;
import com.rotransit.backend.model.City;
import com.rotransit.backend.model.SavedRoute;
import com.rotransit.backend.model.User;
import java.time.LocalDate;
import java.time.LocalTime;
import com.rotransit.backend.repository.CityRepository;
import com.rotransit.backend.repository.SavedRouteRepository;
import com.rotransit.backend.repository.UserRepository;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class SavedRouteService {

    private static final String GUEST_PROVIDER = "guest";
    private final SavedRouteRepository savedRouteRepository;
    private final UserRepository userRepository;
    private final CityRepository cityRepository;
    private final RouteService routeService;
    private final ObjectMapper objectMapper;

    public SavedRouteService(
            SavedRouteRepository savedRouteRepository,
            UserRepository userRepository,
            CityRepository cityRepository,
            RouteService routeService
    ) {
        this.savedRouteRepository = savedRouteRepository;
        this.userRepository = userRepository;
        this.cityRepository = cityRepository;
        this.routeService = routeService;
        this.objectMapper = new ObjectMapper();
    }

    @Transactional
    public SavedRouteResponse saveRoute(SaveRouteRequest request) {
        User user = findOrCreateGuestUser(request.deviceUserId());
        City city = cityRepository.findById(request.cityId())
                .orElseThrow(() -> new CityNotFoundException(request.cityId()));

        SavedRoute savedRoute = new SavedRoute();
        savedRoute.setUser(user);
        savedRoute.setCity(city);
        savedRoute.setLabel(request.label());
        savedRoute.setRouteMetadata(request.routeMetadata());
        SavedRoute persisted = savedRouteRepository.save(savedRoute);
        return toResponse(persisted);
    }

    @Transactional(readOnly = true)
    public List<SavedRouteResponse> getSavedRoutes(String deviceUserId, UUID cityId) {
        User user = findOrCreateGuestUser(deviceUserId);
        List<SavedRoute> routes = cityId == null
                ? savedRouteRepository.findByUserOrderByCreatedAtDesc(user)
                : savedRouteRepository.findByUserAndCityOrderByCreatedAtDesc(
                        user,
                        cityRepository.findById(cityId).orElseThrow(() -> new CityNotFoundException(cityId))
                );
        return routes.stream().map(this::toResponse).toList();
    }

    @Transactional
    public void deleteRoute(String deviceUserId, UUID routeId) {
        User user = findOrCreateGuestUser(deviceUserId);
        SavedRoute route = savedRouteRepository.findById(routeId)
                .orElseThrow(() -> new SavedRouteNotFoundException(routeId));
        if (!route.getUser().getId().equals(user.getId())) {
            throw new SavedRouteNotFoundException(routeId);
        }
        savedRouteRepository.delete(route);
    }

    @Transactional(readOnly = true)
    public SavedRouteValidationResponse validateSavedRoute(
            UUID routeId,
            String deviceUserId,
            LocalDate serviceDate,
            LocalTime serviceTime
    ) {
        User user = findOrCreateGuestUser(deviceUserId);
        SavedRoute route = savedRouteRepository.findById(routeId)
                .orElseThrow(() -> new SavedRouteNotFoundException(routeId));
        if (!route.getUser().getId().equals(user.getId())) {
            throw new SavedRouteNotFoundException(routeId);
        }

        JsonNode metadata;
        try {
            metadata = objectMapper.readTree(route.getRouteMetadata());
        } catch (Exception ex) {
            return new SavedRouteValidationResponse(false, "INVALID_SAVED_METADATA");
        }

        String origin = metadata.path("legs").path(0).path("fromName").asText("");
        int lastIndex = Math.max(0, metadata.path("legs").size() - 1);
        String destination = metadata.path("legs").path(lastIndex).path("toName").asText("");
        if (origin.isBlank() || destination.isBlank()) {
            return new SavedRouteValidationResponse(false, "MISSING_ORIGIN_DESTINATION");
        }

        var result = routeService.searchRoutes(
                route.getCity().getId(),
                new RouteSearchQuery(origin, destination, serviceDate, serviceTime, 1, 30),
                0,
                30
        );
        for (var option : result.routes()) {
            if (matchesStrict(option, metadata)) {
                return new SavedRouteValidationResponse(true, "MATCH_FOUND");
            }
        }
        return new SavedRouteValidationResponse(false, "NO_MATCHING_ITINERARY");
    }

    private SavedRouteResponse toResponse(SavedRoute route) {
        return new SavedRouteResponse(
                route.getId(),
                route.getCity().getId(),
                route.getCity().getName(),
                route.getLabel(),
                route.getRouteMetadata(),
                route.getCreatedAt()
        );
    }

    private User findOrCreateGuestUser(String deviceUserId) {
        return userRepository.findByProviderAndProviderUserId(GUEST_PROVIDER, deviceUserId)
                .orElseGet(() -> {
                    User user = new User();
                    user.setProvider(GUEST_PROVIDER);
                    user.setProviderUserId(deviceUserId);
                    return userRepository.save(user);
                });
    }

    private boolean matchesStrict(com.rotransit.backend.dto.RouteOptionResponse option, JsonNode metadata) {
        JsonNode savedLegs = metadata.path("legs");
        if (!savedLegs.isArray() || savedLegs.size() != option.legs().size()) {
            return false;
        }
        for (int i = 0; i < option.legs().size(); i++) {
            var live = option.legs().get(i);
            JsonNode saved = savedLegs.get(i);
            if (!live.mode().equalsIgnoreCase(saved.path("mode").asText(""))) {
                return false;
            }
            if (!live.fromName().equalsIgnoreCase(saved.path("fromName").asText(""))) {
                return false;
            }
            if (!live.toName().equalsIgnoreCase(saved.path("toName").asText(""))) {
                return false;
            }
        }
        return true;
    }
}
