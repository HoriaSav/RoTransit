package com.rotransit.backend.service;

import com.rotransit.backend.dto.CityResponse;
import com.rotransit.backend.repository.CityRepository;
import java.util.List;
import org.springframework.stereotype.Service;

@Service
public class CityService {

    private final CityRepository cityRepository;

    public CityService(CityRepository cityRepository) {
        this.cityRepository = cityRepository;
    }

    public List<CityResponse> getSupportedCities() {
        return cityRepository.findAllByOrderByCountryAscNameAsc()
                .stream()
                .map(city -> new CityResponse(city.getId(), city.getName(), city.getCountry()))
                .toList();
    }
}
