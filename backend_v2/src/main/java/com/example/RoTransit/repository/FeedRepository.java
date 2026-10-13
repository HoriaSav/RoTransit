package com.example.RoTransit.repository;

import com.example.RoTransit.entity.Feed;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FeedRepository extends JpaRepository<Feed, Long> {

    // Feed.city is LAZY; for lists we load every city in the same query instead of one query per feed
    @Override
    @EntityGraph(attributePaths = "city")
    List<Feed> findAll();

    @Override
    @EntityGraph(attributePaths = "city")
    List<Feed> findAll(Sort sort);
}
