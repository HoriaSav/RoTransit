package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.rotransit.backend.dto.LegResponse;
import com.rotransit.backend.dto.RouteOptionResponse;
import com.rotransit.backend.dto.RouteSearchResponse;
import com.rotransit.backend.dto.SaveRouteRequest;
import com.rotransit.backend.model.City;
import com.rotransit.backend.model.SavedRoute;
import com.rotransit.backend.model.User;
import com.rotransit.backend.repository.CityRepository;
import com.rotransit.backend.repository.SavedRouteRepository;
import com.rotransit.backend.repository.UserRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class SavedRouteServiceUnitTest {

    @Mock
    private SavedRouteRepository savedRouteRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CityRepository cityRepository;
    @Mock
    private RouteService routeService;

    private SavedRouteService savedRouteService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        savedRouteService = new SavedRouteService(savedRouteRepository, userRepository, cityRepository, routeService);
    }

    @Test
    void saveRouteCreatesGuestUserWhenMissingAndPersistsRoute() {
        String deviceUserId = "guest-device";
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        UUID userId = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        UUID routeId = UUID.fromString("cccccccc-cccc-cccc-cccc-cccccccccccc");

        User persistedUser = userMock(userId, "guest", deviceUserId);
        City city = cityMock(cityId, "Brasov");
        SavedRoute persistedRoute = savedRouteMock(
                routeId,
                persistedUser,
                city,
                "Morning commute",
                "{\"legs\":[]}",
                Instant.parse("2026-04-01T12:00:00Z")
        );

        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenReturn(persistedUser);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(savedRouteRepository.save(any(SavedRoute.class))).thenReturn(persistedRoute);

        var response = savedRouteService.saveRoute(new SaveRouteRequest(deviceUserId, cityId, "Morning commute", "{\"legs\":[]}"));

        assertEquals(routeId, response.id());
        assertEquals(cityId, response.cityId());
        assertEquals("Brasov", response.cityName());
        assertEquals("Morning commute", response.label());
        verify(userRepository).save(any(User.class));
    }

    @Test
    void saveRouteThrowsWhenCityDoesNotExist() {
        UUID cityId = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        String deviceUserId = "guest-device";
        User existingUser = userMock(UUID.randomUUID(), "guest", deviceUserId);
        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.of(existingUser));
        when(cityRepository.findById(cityId)).thenReturn(Optional.empty());

        assertThrows(
                CityNotFoundException.class,
                () -> savedRouteService.saveRoute(new SaveRouteRequest(deviceUserId, cityId, null, "{\"legs\":[]}"))
        );
        verify(savedRouteRepository, never()).save(any(SavedRoute.class));
    }

    @Test
    void deleteRouteThrowsWhenRouteBelongsToDifferentUser() {
        String deviceUserId = "guest-1";
        UUID routeId = UUID.fromString("dddddddd-dddd-dddd-dddd-dddddddddddd");
        User currentUser = userMock(UUID.fromString("11111111-1111-1111-1111-111111111111"), "guest", deviceUserId);
        User otherUser = userMock(UUID.fromString("22222222-2222-2222-2222-222222222222"), "guest", "guest-2");
        City city = cityMock(UUID.randomUUID(), "Brasov");
        SavedRoute route = savedRouteMock(routeId, otherUser, city, "Label", "{\"legs\":[]}", Instant.now());

        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.of(currentUser));
        when(savedRouteRepository.findById(routeId)).thenReturn(Optional.of(route));

        assertThrows(SavedRouteNotFoundException.class, () -> savedRouteService.deleteRoute(deviceUserId, routeId));
        verify(savedRouteRepository, never()).delete(any(SavedRoute.class));
    }

    @Test
    void validateSavedRouteReturnsInvalidWhenMetadataJsonIsMalformed() {
        String deviceUserId = "guest-1";
        UUID routeId = UUID.fromString("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee");
        User user = userMock(UUID.randomUUID(), "guest", deviceUserId);
        City city = cityMock(UUID.randomUUID(), "Brasov");
        SavedRoute route = savedRouteMock(routeId, user, city, "Label", "{not json}", Instant.now());
        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.of(user));
        when(savedRouteRepository.findById(routeId)).thenReturn(Optional.of(route));

        var result = savedRouteService.validateSavedRoute(routeId, deviceUserId, LocalDate.now(), LocalTime.NOON);

        assertFalse(result.isValid());
        assertEquals("INVALID_SAVED_METADATA", result.reason());
        verify(routeService, never()).searchRoutes(any(), any(), any(Integer.class), any(Integer.class));
    }

    @Test
    void validateSavedRouteReturnsMatchFoundWhenStrictLegsMatch() {
        String deviceUserId = "guest-1";
        UUID cityId = UUID.fromString("12345678-1234-1234-1234-123456789012");
        UUID routeId = UUID.fromString("abcdefab-cdef-cdef-cdef-abcdefabcdef");
        User user = userMock(UUID.randomUUID(), "guest", deviceUserId);
        City city = cityMock(cityId, "Brasov");
        String metadata = """
                {
                  "legs": [
                    {"mode":"BUS","fromName":"A","toName":"B"},
                    {"mode":"WALK","fromName":"B","toName":"C"}
                  ]
                }
                """;
        SavedRoute route = savedRouteMock(routeId, user, city, "To work", metadata, Instant.now());

        RouteOptionResponse option = new RouteOptionResponse(
                1000L,
                1,
                20L,
                5,
                "rule",
                List.of(
                        new LegResponse("BUS", "A", "B", 1L, 2L, 100.0),
                        new LegResponse("WALK", "B", "C", 3L, 4L, 50.0)
                )
        );
        RouteSearchResponse searchResponse = new RouteSearchResponse(cityId, "Brasov", 0, 30, 1, List.of(option));

        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.of(user));
        when(savedRouteRepository.findById(routeId)).thenReturn(Optional.of(route));
        when(routeService.searchRoutes(eq(cityId), any(RouteSearchQuery.class), eq(0), eq(30))).thenReturn(searchResponse);

        var result = savedRouteService.validateSavedRoute(routeId, deviceUserId, LocalDate.of(2026, 4, 2), LocalTime.of(8, 0));

        assertTrue(result.isValid());
        assertEquals("MATCH_FOUND", result.reason());
    }

    @Test
    void getSavedRoutesWithCityFilterThrowsWhenCityMissing() {
        String deviceUserId = "guest-1";
        UUID cityId = UUID.fromString("ffffffff-ffff-ffff-ffff-ffffffffffff");
        User user = userMock(UUID.randomUUID(), "guest", deviceUserId);
        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.of(user));
        when(cityRepository.findById(cityId)).thenReturn(Optional.empty());

        assertThrows(CityNotFoundException.class, () -> savedRouteService.getSavedRoutes(deviceUserId, cityId));
    }

    @Test
    void findOrCreateGuestUserPersistsExpectedIdentityFields() {
        String deviceUserId = "guest-new";
        UUID cityId = UUID.fromString("11111111-2222-3333-4444-555555555555");
        UUID userId = UUID.fromString("66666666-7777-8888-9999-000000000000");
        User persistedUser = userMock(userId, "guest", deviceUserId);
        City city = cityMock(cityId, "Brasov");
        SavedRoute persistedRoute = savedRouteMock(
                UUID.randomUUID(),
                persistedUser,
                city,
                "Label",
                "{\"legs\":[]}",
                Instant.now()
        );

        when(userRepository.findByProviderAndProviderUserId("guest", deviceUserId)).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenReturn(persistedUser);
        when(cityRepository.findById(cityId)).thenReturn(Optional.of(city));
        when(savedRouteRepository.save(any(SavedRoute.class))).thenReturn(persistedRoute);

        savedRouteService.saveRoute(new SaveRouteRequest(deviceUserId, cityId, "Label", "{\"legs\":[]}"));

        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        assertEquals("guest", userCaptor.getValue().getProvider());
        assertEquals(deviceUserId, userCaptor.getValue().getProviderUserId());
    }

    private User userMock(UUID id, String provider, String providerUserId) {
        User user = org.mockito.Mockito.mock(User.class);
        when(user.getId()).thenReturn(id);
        when(user.getProvider()).thenReturn(provider);
        when(user.getProviderUserId()).thenReturn(providerUserId);
        return user;
    }

    private City cityMock(UUID id, String name) {
        City city = org.mockito.Mockito.mock(City.class);
        when(city.getId()).thenReturn(id);
        when(city.getName()).thenReturn(name);
        return city;
    }

    private SavedRoute savedRouteMock(
            UUID id,
            User user,
            City city,
            String label,
            String routeMetadata,
            Instant createdAt
    ) {
        SavedRoute route = org.mockito.Mockito.mock(SavedRoute.class);
        when(route.getId()).thenReturn(id);
        when(route.getUser()).thenReturn(user);
        when(route.getCity()).thenReturn(city);
        when(route.getLabel()).thenReturn(label);
        when(route.getRouteMetadata()).thenReturn(routeMetadata);
        when(route.getCreatedAt()).thenReturn(createdAt);
        return route;
    }
}
