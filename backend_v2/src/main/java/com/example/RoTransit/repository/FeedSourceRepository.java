package com.example.RoTransit.repository;

import com.example.RoTransit.entity.FeedSource;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface FeedSourceRepository extends JpaRepository<FeedSource, Long> {
    Optional<FeedSource> findByFeedIdAndPriority(Long feedId, int priority);
}
