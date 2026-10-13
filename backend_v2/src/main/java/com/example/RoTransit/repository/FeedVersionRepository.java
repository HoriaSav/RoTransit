package com.example.RoTransit.repository;

import com.example.RoTransit.entity.FeedVersion;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;

public interface FeedVersionRepository extends JpaRepository<FeedVersion, Long> {

    Optional<FeedVersion> findByFeedIdAndStatus(Long feedId, String status);

    /** Versions of one feed with one of these statuses, newest first (used to keep only the newest files). */
    List<FeedVersion> findByFeedIdAndStatusInOrderByIdDesc(Long feedId, Collection<String> statuses);

    /** Whether any version row points at this file (several versions can share one file, see V1). */
    boolean existsByFilePath(String filePath);

    /** The newest row (successful or failed) of one feed: tells us how the last attempt went. */
    Optional<FeedVersion> findFirstByFeedIdOrderByIdDesc(Long feedId);

    // "join fetch v.feed" loads the feed in the same query, so v.getFeed().getId() never needs an extra query
    @Query("select v from FeedVersion v join fetch v.feed where v.status = :status")
    List<FeedVersion> findAllByStatus(@Param("status") String status);

    /** The newest row of every feed, in one query (ids only grow, so the biggest id is the latest attempt). */
    @Query("select v from FeedVersion v join fetch v.feed where v.id in (select max(v2.id) from FeedVersion v2 group by v2.feed.id)")
    List<FeedVersion> findLatestOfEachFeed();

    /** Every file path some row still points at (for the orphan file sweep). */
    @Query("select v.filePath from FeedVersion v where v.filePath is not null")
    List<String> findAllFilePaths();

    /** The feed's rows with this status, newest first (used to cap how many failed attempts are kept). */
    List<FeedVersion> findByFeedIdAndStatusOrderByIdDesc(Long feedId, String status);

    /**
     * Remembers that the source sent this version's file again. A single update statement, so nothing else in the row
     * can be overwritten by accident. @Transactional because an update needs a transaction.
     */
    @Transactional
    @Modifying
    @Query("update FeedVersion v set v.checkedAt = :checkedAt where v.id = :id")
    int markChecked(@Param("id") Long id, @Param("checkedAt") Instant checkedAt);

    /** Demotes the feed's upcoming version to "old" (a newer upcoming one replaces it). Same rules as markCurrentAsOld. */
    @Modifying
    @Query("update FeedVersion v set v.status = 'old' where v.feed.id = :feedId and v.status = 'upcoming'")
    int markUpcomingAsOld(@Param("feedId") Long feedId);

    /** Demotes the feed's current version to "old". Only call it inside the transaction that saves the new current one. */
    @Modifying
    @Query("update FeedVersion v set v.status = 'old' where v.feed.id = :feedId and v.status = 'current'")
    int markCurrentAsOld(@Param("feedId") Long feedId);

    /** Current version of every feed, keyed by feed id (feeds without one are simply missing from the map). */
    default Map<Long, FeedVersion> findCurrentByFeedId() {
        return findAllByStatus(FeedVersion.CURRENT).stream()
                .collect(Collectors.toMap(v -> v.getFeed().getId(), Function.identity()));
    }

    /** Upcoming version of every feed, keyed by feed id (most feeds have none). */
    default Map<Long, FeedVersion> findUpcomingByFeedId() {
        return findAllByStatus(FeedVersion.UPCOMING).stream()
                .collect(Collectors.toMap(v -> v.getFeed().getId(), Function.identity()));
    }

    /** Latest attempt of every feed, keyed by feed id. */
    default Map<Long, FeedVersion> findLatestByFeedId() {
        return findLatestOfEachFeed().stream()
                .collect(Collectors.toMap(v -> v.getFeed().getId(), Function.identity()));
    }
}
