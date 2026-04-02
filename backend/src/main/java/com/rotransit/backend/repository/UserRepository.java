package com.rotransit.backend.repository;

import com.rotransit.backend.model.User;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<User, UUID> {

    Optional<User> findByProviderAndProviderUserId(String provider, String providerUserId);
}
