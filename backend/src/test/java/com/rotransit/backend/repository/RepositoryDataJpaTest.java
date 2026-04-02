package com.rotransit.backend.repository;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.rotransit.backend.model.City;
import com.rotransit.backend.model.SavedRoute;
import com.rotransit.backend.model.User;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.util.ReflectionTestUtils;

@DataJpaTest
@ActiveProfiles("test")
class RepositoryDataJpaTest {

    @Autowired
    private CityRepository cityRepository;
    @Autowired
    private UserRepository userRepository;
    @Autowired
    private SavedRouteRepository savedRouteRepository;

    @Test
    void cityRepositoryOrdersByCountryThenName() {
        City cluj = city("Cluj-Napoca", "Romania", "http://otp-cluj");
        City brasov = city("Brasov", "Romania", "http://otp-brasov");
        City vienna = city("Vienna", "Austria", "http://otp-vienna");
        cityRepository.saveAll(List.of(cluj, brasov, vienna));

        List<City> ordered = cityRepository.findAllByOrderByCountryAscNameAsc();

        assertEquals(3, ordered.size());
        assertEquals("Vienna", ordered.get(0).getName());
        assertEquals("Brasov", ordered.get(1).getName());
        assertEquals("Cluj-Napoca", ordered.get(2).getName());
    }

    @Test
    void userRepositoryFindsByProviderAndProviderUserId() {
        User user = new User();
        user.setProvider("guest");
        user.setProviderUserId("device-123");
        userRepository.save(user);

        Optional<User> found = userRepository.findByProviderAndProviderUserId("guest", "device-123");

        assertTrue(found.isPresent());
        assertEquals("guest", found.get().getProvider());
        assertEquals("device-123", found.get().getProviderUserId());
    }

    @Test
    void savedRouteRepositoryFiltersByUserAndCityAndOrdersNewestFirst() {
        User user = new User();
        user.setProvider("guest");
        user.setProviderUserId("device-x");
        User persistedUser = userRepository.save(user);

        City brasov = cityRepository.save(city("Brasov", "Romania", "http://otp-brasov"));
        City cluj = cityRepository.save(city("Cluj-Napoca", "Romania", "http://otp-cluj"));

        SavedRoute olderBrasov = savedRoute(persistedUser, brasov, "Older", "{\"legs\":[]}", Instant.parse("2026-04-01T10:00:00Z"));
        SavedRoute newerBrasov = savedRoute(persistedUser, brasov, "Newer", "{\"legs\":[]}", Instant.parse("2026-04-01T11:00:00Z"));
        SavedRoute clujRoute = savedRoute(persistedUser, cluj, "Cluj", "{\"legs\":[]}", Instant.parse("2026-04-01T12:00:00Z"));
        savedRouteRepository.saveAll(List.of(olderBrasov, newerBrasov, clujRoute));

        List<SavedRoute> byUser = savedRouteRepository.findByUserOrderByCreatedAtDesc(persistedUser);
        List<SavedRoute> byUserAndCity = savedRouteRepository.findByUserAndCityOrderByCreatedAtDesc(persistedUser, brasov);

        assertEquals(3, byUser.size());
        assertEquals("Cluj", byUser.get(0).getLabel());
        assertEquals("Newer", byUserAndCity.get(0).getLabel());
        assertEquals("Older", byUserAndCity.get(1).getLabel());
    }

    private City city(String name, String country, String otpBaseUrl) {
        City city = new City();
        ReflectionTestUtils.setField(city, "name", name);
        ReflectionTestUtils.setField(city, "country", country);
        ReflectionTestUtils.setField(city, "otpBaseUrl", otpBaseUrl);
        return city;
    }

    private SavedRoute savedRoute(User user, City city, String label, String metadata, Instant createdAt) {
        SavedRoute route = new SavedRoute();
        route.setUser(user);
        route.setCity(city);
        route.setLabel(label);
        route.setRouteMetadata(metadata);
        ReflectionTestUtils.setField(route, "createdAt", createdAt);
        return route;
    }
}
