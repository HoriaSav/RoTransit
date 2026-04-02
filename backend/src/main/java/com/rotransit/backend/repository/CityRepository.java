package com.rotransit.backend.repository;

import com.rotransit.backend.model.City;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CityRepository extends JpaRepository<City, UUID> {

    List<City> findAllByOrderByCountryAscNameAsc();
}
