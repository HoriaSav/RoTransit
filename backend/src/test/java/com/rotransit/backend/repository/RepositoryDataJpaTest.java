package com.rotransit.backend.repository;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.rotransit.backend.model.City;
import java.util.List;
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

    private City city(String name, String country, String otpBaseUrl) {
        City city = new City();
        ReflectionTestUtils.setField(city, "name", name);
        ReflectionTestUtils.setField(city, "country", country);
        ReflectionTestUtils.setField(city, "otpBaseUrl", otpBaseUrl);
        return city;
    }
}
