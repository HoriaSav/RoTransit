package com.rotransit.backend.model;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import com.rotransit.backend.repository.CityRepository;
import com.rotransit.backend.repository.SavedRouteRepository;
import com.rotransit.backend.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.util.ReflectionTestUtils;

@DataJpaTest
@ActiveProfiles("test")
class SavedRouteEntityMappingTest {

    @Autowired
    private CityRepository cityRepository;
    @Autowired
    private UserRepository userRepository;
    @Autowired
    private SavedRouteRepository savedRouteRepository;

    @Test
    void savedRoutePersistsCityUserAndJsonMetadata() {
        City city = new City();
        ReflectionTestUtils.setField(city, "name", "Brasov");
        ReflectionTestUtils.setField(city, "country", "Romania");
        ReflectionTestUtils.setField(city, "otpBaseUrl", "http://otp:8080/otp");
        City persistedCity = cityRepository.save(city);

        User user = new User();
        user.setProvider("guest");
        user.setProviderUserId("device-1");
        User persistedUser = userRepository.save(user);

        SavedRoute route = new SavedRoute();
        route.setUser(persistedUser);
        route.setCity(persistedCity);
        route.setLabel("Morning");
        route.setRouteMetadata("{\"legs\":[{\"mode\":\"BUS\"}]}");
        SavedRoute persisted = savedRouteRepository.save(route);

        SavedRoute reloaded = savedRouteRepository.findById(persisted.getId()).orElseThrow();
        assertNotNull(reloaded.getId());
        assertEquals("Morning", reloaded.getLabel());
        assertEquals("{\"legs\":[{\"mode\":\"BUS\"}]}", reloaded.getRouteMetadata());
        assertEquals("Brasov", reloaded.getCity().getName());
        assertEquals("guest", reloaded.getUser().getProvider());
    }
}
