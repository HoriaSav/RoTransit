package com.rotransit.backend.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

import com.rotransit.backend.model.City;
import com.rotransit.backend.repository.CityRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

class CityServiceUnitTest {

    @Mock
    private CityRepository cityRepository;

    private CityService cityService;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
        cityService = new CityService(cityRepository);
    }

    @Test
    void getSupportedCitiesMapsAndReturnsSortedRepositoryPayload() {
        City first = cityMock(UUID.fromString("11111111-1111-1111-1111-111111111111"), "Brasov", "Romania");
        City second = cityMock(UUID.fromString("22222222-2222-2222-2222-222222222222"), "Cluj-Napoca", "Romania");
        when(cityRepository.findAllByOrderByCountryAscNameAsc()).thenReturn(List.of(first, second));

        var result = cityService.getSupportedCities();

        assertEquals(2, result.size());
        assertEquals("Brasov", result.get(0).name());
        assertEquals("Romania", result.get(0).country());
        assertEquals("Cluj-Napoca", result.get(1).name());
    }

    @Test
    void getSupportedCitiesReturnsEmptyWhenRepositoryIsEmpty() {
        when(cityRepository.findAllByOrderByCountryAscNameAsc()).thenReturn(List.of());

        var result = cityService.getSupportedCities();

        assertEquals(0, result.size());
    }

    private City cityMock(UUID id, String name, String country) {
        City city = org.mockito.Mockito.mock(City.class);
        when(city.getId()).thenReturn(id);
        when(city.getName()).thenReturn(name);
        when(city.getCountry()).thenReturn(country);
        return city;
    }
}
