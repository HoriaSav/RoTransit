package com.rotransit.backend.repository;

import com.rotransit.backend.model.City;
import com.rotransit.backend.model.SavedRoute;
import com.rotransit.backend.model.User;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SavedRouteRepository extends JpaRepository<SavedRoute, UUID> {

    List<SavedRoute> findByUserOrderByCreatedAtDesc(User user);

    List<SavedRoute> findByUserAndCityOrderByCreatedAtDesc(User user, City city);
}
